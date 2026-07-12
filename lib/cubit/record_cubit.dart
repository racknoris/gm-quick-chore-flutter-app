import 'dart:async';
import 'dart:io';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/recording.dart';
import '../services/api_client.dart';
import '../services/background_recorder.dart';
import '../services/pending_uploads.dart';
import '../services/storage_service.dart';

/// The user-facing phases of the record -> upload -> poll -> display flow.
enum RecordPhase {
  idle,
  recording,
  paused, // recording paused; same file resumes on unpause
  uploading, // uploading audio to storage
  creating, // POST /recordings
  processing, // polling GET /recordings/:id
  done,
  failed,
}

class RecordState {
  const RecordState({
    required this.phase,
    this.recording,
    this.message,
  });

  final RecordPhase phase;
  final Recording? recording; // set when done
  final String? message; // status label or error message

  RecordState copyWith({
    RecordPhase? phase,
    Recording? recording,
    String? message,
  }) {
    return RecordState(
      phase: phase ?? this.phase,
      recording: recording ?? this.recording,
      message: message,
    );
  }

  static const idle = RecordState(phase: RecordPhase.idle);
}

/// Drives one recording end to end. Kept independent of the history list so the
/// screens compose cleanly.
class RecordCubit extends Cubit<RecordState> {
  RecordCubit({
    required ApiClient api,
    required StorageService storage,
    required BackgroundRecorder recorder,
    required PendingUploads pending,
  })  : _api = api,
        _storage = storage,
        _recorder = recorder,
        _pending = pending,
        super(RecordState.idle) {
    // Stopping from the notification (screen off / app backgrounded) funnels
    // through the same pipeline as the in-app Stop button.
    _recorder.onStopRequested = () {
      if (_isActive) stopAndProcess();
    };
    // Pause/resume from the notification: the service already applied it, so
    // just mirror the phase here.
    _recorder.onPauseRequested = () {
      if (state.phase == RecordPhase.recording) {
        emit(const RecordState(phase: RecordPhase.paused, message: 'Paused'));
      }
    };
    _recorder.onResumeRequested = () {
      if (state.phase == RecordPhase.paused) {
        emit(const RecordState(phase: RecordPhase.recording, message: 'Recording…'));
      }
    };
  }

  bool get _isActive =>
      state.phase == RecordPhase.recording || state.phase == RecordPhase.paused;

  final ApiClient _api;
  final StorageService _storage;
  final BackgroundRecorder _recorder;
  final PendingUploads _pending;

  Timer? _pollTimer;
  bool _resuming = false;

  Future<void> startRecording() async {
    if (!await _recorder.hasPermission()) {
      emit(RecordState.idle.copyWith(
        phase: RecordPhase.failed,
        message: 'Microphone permission denied.',
      ));
      return;
    }
    try {
      // Recording runs in a foreground service, so it survives the screen going
      // off or the app being backgrounded.
      await _recorder.start();
      emit(const RecordState(phase: RecordPhase.recording, message: 'Recording…'));
    } catch (e) {
      _fail(e.toString());
    }
  }

  /// Pause the in-progress recording; the same file resumes on [resume].
  void pause() {
    if (state.phase != RecordPhase.recording) return;
    _recorder.pause();
    emit(const RecordState(phase: RecordPhase.paused, message: 'Paused'));
  }

  void resume() {
    if (state.phase != RecordPhase.paused) return;
    _recorder.resume();
    emit(const RecordState(phase: RecordPhase.recording, message: 'Recording…'));
  }

  /// Stops recording and runs the full pipeline: enqueue -> upload -> poll.
  Future<void> stopAndProcess() async {
    final String localPath;
    try {
      localPath = await _recorder.stop();
    } catch (e) {
      _fail(e.toString());
      return;
    }
    if (!File(localPath).existsSync() || File(localPath).lengthSync() == 0) {
      _fail('No audio was recorded.');
      return;
    }

    // Move the finalized audio into the durable upload queue BEFORE touching the
    // network. From here on the recording cannot be lost: if the upload fails or
    // the process is killed, the queued file is retried on the next launch.
    final String queuedPath;
    try {
      queuedPath = await _pending.enqueue(localPath);
    } catch (e) {
      _fail(e.toString());
      return;
    }

    try {
      emit(const RecordState(phase: RecordPhase.uploading, message: 'Uploading…'));
      final jobId = await _uploadQueued(queuedPath);
      emit(const RecordState(phase: RecordPhase.processing, message: 'Processing…'));
      await _poll(jobId);
    } catch (e) {
      // The file stays in the queue and will be retried on the next launch.
      _fail(e.toString());
    }
  }

  /// Uploads one queued recording and registers it with the backend, then drops
  /// it from the queue once the backend owns it (audio in R2 + a recording row).
  /// Returns the job id. Shared by the live Stop flow and [resumePending].
  Future<String> _uploadQueued(String queuedPath) async {
    // Get a presigned R2 URL, upload the audio directly to R2, then create the
    // job with the returned key.
    final target = await _api.getUploadUrl();
    await _storage.uploadToPresignedUrl(
      uploadUrl: target.uploadUrl,
      localFilePath: queuedPath,
      contentType: target.contentType,
    );
    final jobId = await _api.createRecording(target.audioPath);
    // The backend now owns the audio + a recording row — safe to drop the local
    // copy. Removing only after createRecording (not after the R2 PUT) avoids
    // orphaning audio in R2 with no recording pointing at it.
    await _pending.remove(queuedPath);
    return jobId;
  }

  /// Recovers recordings left un-uploaded by a previous session (a killed
  /// process, a crash right after Stop). Best-effort and silent — recovered
  /// recordings surface in the history list, not the record button. Safe to call
  /// on every launch once authenticated; a failed file is left for next time.
  Future<void> resumePending() async {
    if (_resuming || _isActive) return;
    _resuming = true;
    try {
      // Rescue a finalized-but-un-enqueued scratch file: the process may have
      // died in the sliver between Stop finalizing the audio and enqueue moving
      // it. Only when no recording is in progress, so we never grab a live file.
      final scratch = await currentRecordingFilePath();
      final scratchFile = File(scratch);
      if (await scratchFile.exists() && await scratchFile.length() > 0) {
        try {
          await _pending.enqueue(scratch);
        } catch (_) {/* leave it; onStart will clear a truly-stale file */}
      }

      for (final path in await _pending.list()) {
        try {
          await _uploadQueued(path);
        } catch (_) {/* leave it in the queue; retry next launch */}
      }
    } finally {
      _resuming = false;
    }
  }

  /// Polling strategy from the docs: every 2s for the first 20s, then every 5s,
  /// give up after ~3 minutes.
  Future<void> _poll(String jobId) async {
    final start = DateTime.now();
    _pollTimer?.cancel();

    Future<void> tick() async {
      try {
        final rec = await _api.getRecording(jobId);
        if (rec.status == RecordingStatus.done) {
          emit(RecordState(phase: RecordPhase.done, recording: rec));
          return;
        }
        if (rec.status == RecordingStatus.failed) {
          emit(RecordState(
            phase: RecordPhase.failed,
            recording: rec,
            message: rec.friendlyError,
          ));
          return;
        }
      } catch (e) {
        _fail(e.toString());
        return;
      }

      final elapsed = DateTime.now().difference(start);
      if (elapsed.inSeconds > 180) {
        _fail('Still processing. Check back shortly.');
        return;
      }
      final interval =
          elapsed.inSeconds < 20 ? const Duration(seconds: 2) : const Duration(seconds: 5);
      _pollTimer = Timer(interval, tick);
    }

    await tick();
  }

  void reset() {
    _pollTimer?.cancel();
    emit(RecordState.idle);
  }

  void _fail(String message) {
    _pollTimer?.cancel();
    emit(RecordState(phase: RecordPhase.failed, message: message));
  }

  @override
  Future<void> close() {
    _pollTimer?.cancel();
    _recorder.onStopRequested = null;
    _recorder.onPauseRequested = null;
    _recorder.onResumeRequested = null;
    return super.close();
  }
}

import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import '../models/recording.dart';
import '../services/api_client.dart';
import '../services/audio_recorder.dart';
import '../services/storage_service.dart';

/// The user-facing phases of the record -> upload -> poll -> display flow.
enum RecordPhase {
  idle,
  recording,
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
    required AudioRecorderService recorder,
  })  : _api = api,
        _storage = storage,
        _recorder = recorder,
        super(RecordState.idle);

  final ApiClient _api;
  final StorageService _storage;
  final AudioRecorderService _recorder;
  final _uuid = const Uuid();

  String? _recordingId;
  Timer? _pollTimer;

  Future<void> startRecording() async {
    if (!await _recorder.hasPermission()) {
      emit(RecordState.idle.copyWith(
        phase: RecordPhase.failed,
        message: 'Microphone permission denied.',
      ));
      return;
    }
    _recordingId = _uuid.v4();
    await _recorder.start(_recordingId!);
    emit(const RecordState(phase: RecordPhase.recording, message: 'Recording…'));
  }

  /// Stops recording and runs the full pipeline: upload -> create -> poll.
  Future<void> stopAndProcess() async {
    final localPath = await _recorder.stop();
    final recordingId = _recordingId;
    if (localPath == null || recordingId == null) {
      _fail('No audio was recorded.');
      return;
    }

    try {
      emit(const RecordState(phase: RecordPhase.uploading, message: 'Uploading…'));
      // Get a presigned R2 URL, upload the audio directly to R2, then create
      // the job with the returned key.
      final target = await _api.getUploadUrl();
      await _storage.uploadToPresignedUrl(
        uploadUrl: target.uploadUrl,
        localFilePath: localPath,
        contentType: target.contentType,
      );

      emit(const RecordState(phase: RecordPhase.creating, message: 'Creating chores…'));
      final jobId = await _api.createRecording(target.audioPath);

      emit(const RecordState(phase: RecordPhase.processing, message: 'Processing…'));
      await _poll(jobId);
    } catch (e) {
      _fail(e.toString());
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
    _recordingId = null;
    emit(RecordState.idle);
  }

  void _fail(String message) {
    _pollTimer?.cancel();
    emit(RecordState(phase: RecordPhase.failed, message: message));
  }

  @override
  Future<void> close() {
    _pollTimer?.cancel();
    _recorder.dispose();
    return super.close();
  }
}

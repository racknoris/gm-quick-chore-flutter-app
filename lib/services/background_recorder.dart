import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

const String _kStopAction = 'gm_stop';
const String _kPauseAction = 'gm_pause';
const String _kResumeAction = 'gm_resume';
const String _recordingFileName = 'gm_recording.m4a';

/// Path shared by BOTH isolates: the foreground-service isolate records to it,
/// the main isolate uploads from it. `getApplicationSupportDirectory` resolves
/// to the same location in both isolates of the same app.
Future<String> currentRecordingFilePath() async {
  final dir = await getApplicationSupportDirectory();
  return p.join(dir.path, _recordingFileName);
}

/// Speech-tuned recording config (AAC-LC, 64 kbps, 16 kHz mono; Android uses the
/// VOICE_RECOGNITION source). Kept in sync with the app's recording settings.
const RecordConfig _kRecordConfig = RecordConfig(
  encoder: AudioEncoder.aacLc,
  bitRate: 64000,
  sampleRate: 16000,
  numChannels: 1,
  androidConfig: AndroidRecordConfig(
    audioSource: AndroidAudioSource.voiceRecognition,
  ),
);

// ---------------------------------------------------------------------------
// Foreground-service isolate: the recorder lives HERE so it keeps running when
// the screen is off / the app is backgrounded.
// ---------------------------------------------------------------------------

@pragma('vm:entry-point')
void startBackgroundRecorder() {
  FlutterForegroundTask.setTaskHandler(_RecordingTaskHandler());
}

class _RecordingTaskHandler extends TaskHandler {
  final AudioRecorder _recorder = AudioRecorder();
  bool _paused = false;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    final path = await currentRecordingFilePath();
    final file = File(path);
    if (await file.exists()) await file.delete(); // clear a stale recording
    await _recorder.start(_kRecordConfig, path: path);
    _updateNotification();
  }

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    await _recorder.stop(); // finalizes the .m4a on disk
    await _recorder.dispose();
  }

  @override
  void onNotificationButtonPressed(String id) {
    switch (id) {
      // Stop funnels to the main isolate, which runs the upload pipeline.
      case _kStopAction:
        FlutterForegroundTask.sendDataToMain(_kStopAction);
      // Pause/Resume act locally, then echo to main so the cubit's phase
      // tracks a notification-driven change.
      case _kPauseAction:
        _applyPause();
        FlutterForegroundTask.sendDataToMain(_kPauseAction);
      case _kResumeAction:
        _applyResume();
        FlutterForegroundTask.sendDataToMain(_kResumeAction);
    }
  }

  @override
  void onReceiveData(Object data) {
    // Pause/Resume commands sent from the app UI (main isolate).
    if (data == _kPauseAction) _applyPause();
    if (data == _kResumeAction) _applyResume();
  }

  Future<void> _applyPause() async {
    if (_paused) return;
    _paused = true;
    await _recorder.pause();
    _updateNotification();
  }

  Future<void> _applyResume() async {
    if (!_paused) return;
    _paused = false;
    await _recorder.resume();
    _updateNotification();
  }

  void _updateNotification() {
    FlutterForegroundTask.updateService(
      notificationTitle: 'GM Quick Chore',
      notificationText: _paused ? 'Paused' : 'Recording your chores…',
      notificationButtons: [
        NotificationButton(
          id: _paused ? _kResumeAction : _kPauseAction,
          text: _paused ? 'Resume' : 'Pause',
        ),
        const NotificationButton(id: _kStopAction, text: 'Stop'),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Main isolate: controls the service and hands the finalized file to the app.
// ---------------------------------------------------------------------------

class BackgroundRecorder {
  /// Called when the user stops recording from the notification (not the app UI).
  VoidCallback? onStopRequested;

  /// Called when pause/resume is triggered from the notification, so the cubit
  /// can sync its phase (app-UI-driven pause/resume updates the phase directly).
  VoidCallback? onPauseRequested;
  VoidCallback? onResumeRequested;

  /// Configure the plugin + communication port. Call once in `main()`.
  void init() {
    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.addTaskDataCallback(_onData);
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'gm_recording',
        channelName: 'GM Quick Chore Recording',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );
  }

  void _onData(Object data) {
    if (data == _kStopAction) onStopRequested?.call();
    if (data == _kPauseAction) onPauseRequested?.call();
    if (data == _kResumeAction) onResumeRequested?.call();
  }

  /// Pause/resume the in-progress recording (same file continues on resume).
  void pause() => FlutterForegroundTask.sendDataToTask(_kPauseAction);
  void resume() => FlutterForegroundTask.sendDataToTask(_kResumeAction);

  Future<bool> hasPermission() => AudioRecorder().hasPermission();

  /// Starts the foreground service; recording begins in its isolate.
  Future<void> start() async {
    final perm = await FlutterForegroundTask.checkNotificationPermission();
    if (perm != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }

    final result = await FlutterForegroundTask.startService(
      serviceId: 400,
      serviceTypes: const [ForegroundServiceTypes.microphone],
      notificationTitle: 'GM Quick Chore',
      notificationText: 'Starting…',
      callback: startBackgroundRecorder,
    );
    if (result is ServiceRequestFailure) {
      throw Exception('Could not start recording service: ${result.error}');
    }
  }

  /// Stops the service (finalizing the audio) and returns the recorded file path.
  Future<String> stop() async {
    await FlutterForegroundTask.stopService();
    final path = await currentRecordingFilePath();
    await _awaitFileReady(path);
    return path;
  }

  /// Wait briefly for the service isolate to flush + close the .m4a after stop.
  Future<void> _awaitFileReady(String path) async {
    final file = File(path);
    for (var i = 0; i < 30; i++) {
      if (await file.exists() && await file.length() > 0) return;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  Future<bool> get isRunning => FlutterForegroundTask.isRunningService;
}

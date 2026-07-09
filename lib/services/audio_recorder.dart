import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Wraps the `record` package. Records short m4a/aac clips to a temp file,
/// per the recording format/limits in the docs.
class AudioRecorderService {
  final AudioRecorder _recorder = AudioRecorder();

  Future<bool> hasPermission() => _recorder.hasPermission();

  /// Starts recording to a temp .m4a file named for [recordingId] so the local
  /// file lines up with the storage path convention.
  Future<void> start(String recordingId) async {
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/$recordingId.m4a';
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc),
      path: path,
    );
  }

  /// Stops recording and returns the local file path (or null if nothing).
  Future<String?> stop() => _recorder.stop();

  Future<bool> isRecording() => _recorder.isRecording();

  void dispose() => _recorder.dispose();
}

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Wraps the `record` package. Records short m4a/aac clips to a temp file,
/// per the recording format/limits in the docs.
class AudioRecorderService {
  final AudioRecorder _recorder = AudioRecorder();

  Future<bool> hasPermission() => _recorder.hasPermission();

  /// Starts recording to a temp .m4a file named for [recordingId] so the local
  /// file lines up with the storage path convention.
  ///
  /// Tuned for speech-to-text: AAC/.m4a, 64 kbps, 16 kHz mono. 16 kHz matches
  /// what gpt-4o-transcribe uses internally (higher is wasted bytes), and mono
  /// at 64 kbps keeps 30 min ≈ 14 MB — well under OpenAI's 25 MB limit. On
  /// Android we use the VOICE_RECOGNITION source for speech-tuned capture
  /// (noise suppression / AGC); iOS ignores androidConfig and records fine.
  Future<void> start(String recordingId) async {
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/$recordingId.m4a';
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 64000,
        sampleRate: 16000,
        numChannels: 1,
        androidConfig: AndroidRecordConfig(
          audioSource: AndroidAudioSource.voiceRecognition,
        ),
      ),
      path: path,
    );
  }

  /// Stops recording and returns the local file path (or null if nothing).
  Future<String?> stop() => _recorder.stop();

  Future<bool> isRecording() => _recorder.isRecording();

  void dispose() => _recorder.dispose();
}

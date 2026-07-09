import 'package:equatable/equatable.dart';

import 'chore.dart';

enum RecordingStatus { uploaded, processing, done, failed, unknown }

RecordingStatus _statusFromString(String? s) {
  switch (s) {
    case 'uploaded':
      return RecordingStatus.uploaded;
    case 'processing':
      return RecordingStatus.processing;
    case 'done':
      return RecordingStatus.done;
    case 'failed':
      return RecordingStatus.failed;
    default:
      return RecordingStatus.unknown;
  }
}

/// A recording job + its results. Matches the recording object in API.md.
class Recording extends Equatable {
  const Recording({
    required this.id,
    required this.status,
    this.title,
    this.transcript,
    this.error,
    this.chores = const [],
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final RecordingStatus status;
  final String? title;
  final String? transcript;
  final String? error; // machine code when failed
  final List<Chore> chores;
  final DateTime? createdAt; // the recording date
  final DateTime? updatedAt;

  bool get isTerminal =>
      status == RecordingStatus.done || status == RecordingStatus.failed;

  factory Recording.fromJson(Map<String, dynamic> json) {
    final choresJson = (json['chores'] as List<dynamic>? ?? []);
    return Recording(
      id: json['id'] as String,
      status: _statusFromString(json['status'] as String?),
      title: json['title'] as String?,
      transcript: json['transcript'] as String?,
      error: json['error'] as String?,
      chores: choresJson
          .map((c) => Chore.fromJson(c as Map<String, dynamic>))
          .toList(),
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? ''),
    );
  }

  /// Maps a failure `error` code to a user-facing message (per the API contract).
  String get friendlyError {
    switch (error) {
      case 'transcription_failed':
        return "Couldn't understand the recording. Try again.";
      case 'network_error':
      case 'openai_unavailable':
        return 'Connection problem. Tap to retry.';
      default:
        return 'Something went wrong. Tap to retry.';
    }
  }

  @override
  List<Object?> get props => [id, status, title, transcript, error, chores];
}

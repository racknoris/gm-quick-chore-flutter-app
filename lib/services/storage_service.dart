import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';

/// Uploads audio to Supabase Storage using the user-scoped path convention
///   recordings/{user_id}/{recording_id}.m4a
/// and returns the full audio_path the backend expects.
class StorageService {
  Future<String> uploadRecording({
    required String recordingId,
    required String localFilePath,
  }) async {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('Not authenticated — cannot upload.');
    }

    // Object path within the bucket: {user_id}/{recording_id}.m4a
    final objectPath = '$userId/$recordingId.m4a';

    await client.storage.from(AppConfig.storageBucket).upload(
          objectPath,
          File(localFilePath),
          fileOptions: const FileOptions(
            contentType: 'audio/m4a',
            upsert: true,
          ),
        );

    // audio_path includes the bucket prefix, matching the backend contract.
    return '${AppConfig.storageBucket}/$objectPath';
  }
}

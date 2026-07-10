import 'dart:io';

import 'package:http/http.dart' as http;

/// Uploads audio directly to Cloudflare R2 using a presigned PUT URL minted by
/// the backend. The app never holds R2 credentials — it only ever sees the
/// short-lived signed URL.
class StorageService {
  StorageService({http.Client? client}) : _http = client ?? http.Client();

  final http.Client _http;

  /// PUTs the local file to [uploadUrl]. [contentType] MUST match what the URL
  /// was signed with, or R2 rejects the request.
  Future<void> uploadToPresignedUrl({
    required String uploadUrl,
    required String localFilePath,
    required String contentType,
  }) async {
    final bytes = await File(localFilePath).readAsBytes();
    final res = await _http.put(
      Uri.parse(uploadUrl),
      headers: {'Content-Type': contentType},
      body: bytes,
    );
    if (res.statusCode != 200) {
      throw Exception('Upload failed (${res.statusCode}).');
    }
  }
}

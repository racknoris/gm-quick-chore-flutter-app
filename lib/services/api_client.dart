import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../models/recording.dart';
import '../models/chore.dart';

/// Thin client for the Heroku backend. Every request carries the Supabase JWT;
/// the backend derives user_id from it (we never send user_id in a body).
class ApiClient {
  ApiClient({http.Client? client}) : _http = client ?? http.Client();

  final http.Client _http;

  Map<String, String> _headers() {
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Uri _uri(String path) => Uri.parse('${AppConfig.backendUrl}$path');

  Never _throwFromResponse(http.Response res) {
    String message = 'Request failed (${res.statusCode}).';
    try {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final err = body['error'] as Map<String, dynamic>?;
      if (err != null) message = err['message'] as String? ?? message;
    } catch (_) {/* keep default */}
    throw ApiException(res.statusCode, message);
  }

  /// POST /recordings/upload-url — get a presigned R2 URL to upload audio to.
  /// The app PUTs the file to [UploadTarget.uploadUrl], then calls
  /// [createRecording] with [UploadTarget.audioPath].
  Future<UploadTarget> getUploadUrl() async {
    final res = await _http.post(_uri('/recordings/upload-url'), headers: _headers());
    if (res.statusCode != 200) _throwFromResponse(res);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return UploadTarget(
      uploadUrl: body['upload_url'] as String,
      audioPath: body['audio_path'] as String,
      contentType: body['content_type'] as String? ?? 'audio/m4a',
    );
  }

  /// POST /recordings — create a job, returns the job id. Processing is async.
  Future<String> createRecording(String audioPath) async {
    final res = await _http.post(
      _uri('/recordings'),
      headers: _headers(),
      body: jsonEncode({'audio_path': audioPath}),
    );
    if (res.statusCode != 202) _throwFromResponse(res);
    return (jsonDecode(res.body) as Map<String, dynamic>)['job_id'] as String;
  }

  /// GET /recordings/:id — poll status / fetch chores.
  Future<Recording> getRecording(String id) async {
    final res = await _http.get(_uri('/recordings/$id'), headers: _headers());
    if (res.statusCode != 200) _throwFromResponse(res);
    return Recording.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// GET /recordings — the user's recordings, newest first.
  Future<List<Recording>> listRecordings() async {
    final res = await _http.get(_uri('/recordings'), headers: _headers());
    if (res.statusCode != 200) _throwFromResponse(res);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final list = body['recordings'] as List<dynamic>? ?? [];
    return list
        .map((r) => Recording.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// POST /recordings/:id/retry — reprocess a failed job.
  Future<void> retryRecording(String id) async {
    final res =
        await _http.post(_uri('/recordings/$id/retry'), headers: _headers());
    if (res.statusCode != 202) _throwFromResponse(res);
  }

  /// PATCH /chores/:id — toggle is_done and/or edit content.
  Future<Chore> updateChore(String id, {bool? isDone, String? content}) async {
    final res = await _http.patch(
      _uri('/chores/$id'),
      headers: _headers(),
      body: jsonEncode({
        if (isDone != null) 'is_done': isDone,
        if (content != null) 'content': content,
      }),
    );
    if (res.statusCode != 200) _throwFromResponse(res);
    return Chore.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// DELETE /chores/:id
  Future<void> deleteChore(String id) async {
    final res = await _http.delete(_uri('/chores/$id'), headers: _headers());
    if (res.statusCode != 204) _throwFromResponse(res);
  }
}

/// Where + how to upload an audio file (from POST /recordings/upload-url).
class UploadTarget {
  const UploadTarget({
    required this.uploadUrl,
    required this.audioPath,
    required this.contentType,
  });

  final String uploadUrl; // presigned R2 PUT URL
  final String audioPath; // R2 key to send back in POST /recordings
  final String contentType; // must match what the URL was signed with
}

class ApiException implements Exception {
  ApiException(this.statusCode, this.message);
  final int statusCode;
  final String message;
  @override
  String toString() => message;
}

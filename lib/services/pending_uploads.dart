import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// A durable, crash-safe queue of finalized recordings awaiting upload.
///
/// Each `.m4a` in the queue directory is one un-uploaded recording. The file's
/// **existence is the marker** — there is no separate metadata to keep in sync,
/// so the queue survives a process kill or a device reset untouched.
///
/// The recorder streams to a single fixed scratch file; on Stop we MOVE that
/// file in here under a unique name (an atomic rename on the same filesystem).
/// Because the queue lives in its own directory and every entry has a unique
/// name, a brand-new recording can never overwrite one that hasn't uploaded yet.
class PendingUploads {
  static const _dirName = 'pending_uploads';
  final _uuid = const Uuid();

  Future<Directory> _dir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, _dirName));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Moves [finalizedPath] into the queue under a unique name and returns the
  /// new path. The move is a rename within the same filesystem, so it is atomic:
  /// the file is either at its old path or fully in the queue, never half-there.
  Future<String> enqueue(String finalizedPath) async {
    final dir = await _dir();
    final dest = p.join(dir.path, '${_uuid.v4()}.m4a');
    await File(finalizedPath).rename(dest);
    return dest;
  }

  /// Every queued recording, oldest first (upload in capture order).
  Future<List<String>> list() async {
    final dir = await _dir();
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.m4a'))
        .toList()
      ..sort((a, b) => a.statSync().modified.compareTo(b.statSync().modified));
    return files.map((f) => f.path).toList();
  }

  /// Removes a queued file once the backend owns the recording (audio in R2 +
  /// a recording row). Safe to call if the file is already gone.
  Future<void> remove(String path) async {
    final f = File(path);
    if (await f.exists()) await f.delete();
  }
}

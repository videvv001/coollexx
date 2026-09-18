import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Persists user-taken card photos as files in the app's own container.
/// Only file paths are kept in the database — never image blobs.
class PhotoStore {
  PhotoStore._();
  static final PhotoStore instance = PhotoStore._();

  static const _uuid = Uuid();

  Future<Directory> _photosDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final photosDir = Directory(p.join(dir.path, 'photos'));
    if (!await photosDir.exists()) {
      await photosDir.create(recursive: true);
    }
    return photosDir;
  }

  /// Copies a captured image file into permanent storage and returns its
  /// saved path.
  Future<String> save(File sourceFile) async {
    final dir = await _photosDir();
    final ext = p.extension(sourceFile.path).isEmpty
        ? '.jpg'
        : p.extension(sourceFile.path);
    final dest = File(p.join(dir.path, '${_uuid.v4()}$ext'));
    await sourceFile.copy(dest.path);
    return dest.path;
  }

  Future<void> delete(String path) async {
    final f = File(path);
    if (await f.exists()) {
      await f.delete();
    }
  }
}

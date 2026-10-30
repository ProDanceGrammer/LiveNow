import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../data/database.dart';

/// Largest photo the hub stores or serves (the phone resizes to ~1600 px JPEG,
/// so real photos are far below this).
const kMaxAiPhotoBytes = 8 * 1024 * 1024;

/// A stored photo: its bytes and mime type.
typedef AiStoredPhoto = ({String mime, Uint8List data});

/// An id that is safe to use as a file name: letters, digits and dashes only
/// (UUIDs). No dots, no separators, so nothing can leave the folder.
bool isSafeBlobId(String id) => RegExp(r'^[A-Za-z0-9-]{8,64}$').hasMatch(id);

/// The hub's photo originals: one file per `ai_blobs` row, `<root>/<id>.jpg|png`.
/// The phone shows the picture itself, so no thumbnails are made here.
class AiPhotoStore {
  AiPhotoStore(this.root);

  final Directory root;

  static String extensionFor(String mime) =>
      mime.toLowerCase() == 'image/png' ? 'png' : 'jpg';

  File _file(String blobId, String ext) {
    if (!isSafeBlobId(blobId)) throw ArgumentError.value(blobId, 'blobId');
    return File('${root.path}${Platform.pathSeparator}$blobId.$ext');
  }

  /// Writes the photo atomically (a temp file, then a rename), replacing an
  /// older copy with the same id (also one of the other type).
  Future<void> save(String blobId, Uint8List bytes, String mime) async {
    if (bytes.isEmpty || bytes.length > kMaxAiPhotoBytes) {
      throw ArgumentError('photo size');
    }
    final ext = extensionFor(mime);
    final target = _file(blobId, ext);
    await root.create(recursive: true);
    final tmp = File('${target.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(target.path);
    final other = _file(blobId, ext == 'png' ? 'jpg' : 'png');
    if (await other.exists()) await other.delete();
  }

  /// The photo, or null when it is missing, too big or the id is not safe.
  Future<AiStoredPhoto?> read(String blobId) async {
    if (!isSafeBlobId(blobId)) return null;
    for (final ext in const ['jpg', 'png']) {
      final f = _file(blobId, ext);
      if (!await f.exists()) continue;
      if (await f.length() > kMaxAiPhotoBytes) return null;
      return (
        mime: ext == 'png' ? 'image/png' : 'image/jpeg',
        data: await f.readAsBytes(),
      );
    }
    return null;
  }

  Future<bool> exists(String blobId) async {
    if (!isSafeBlobId(blobId)) return false;
    for (final ext in const ['jpg', 'png']) {
      if (await _file(blobId, ext).exists()) return true;
    }
    return false;
  }

  Future<void> delete(String blobId) async {
    if (!isSafeBlobId(blobId)) return;
    for (final ext in const ['jpg', 'png']) {
      final f = _file(blobId, ext);
      if (await f.exists()) await f.delete();
    }
  }

  /// Deletes photo files last written longer ago than [age] (retention);
  /// returns how many were removed. Stray temp files are cleaned the same way.
  Future<int> purgeOlderThan(Duration age, {DateTime? now}) async {
    if (!await root.exists()) return 0;
    final limit = (now ?? DateTime.now()).subtract(age);
    var n = 0;
    await for (final e in root.list(followLinks: false)) {
      if (e is! File) continue;
      if ((await e.lastModified()).isBefore(limit)) {
        await e.delete();
        n++;
      }
    }
    return n;
  }

  /// The file part of storing a photo that arrived through sync: decodes the
  /// row's base64 `data` into a file. The caller then sets `stored_on_hub_at`
  /// and clears `data` silently.
  Future<void> storeBlobFromRow(AiBlob row) async {
    final data = row.data;
    if (data == null || data.isEmpty) {
      throw ArgumentError('the blob row has no data');
    }
    // base64 inflates by 4/3: refuse before decoding something huge.
    if (data.length > kMaxAiPhotoBytes * 4 ~/ 3 + 8) {
      throw ArgumentError('photo size');
    }
    await save(row.id, base64.decode(data), row.mime);
  }
}

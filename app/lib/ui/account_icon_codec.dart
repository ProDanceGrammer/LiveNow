import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

/// The picture of an account is stored as a small square PNG in base64 text
/// (column `budget_accounts.icon`), so it syncs and backs up like any other
/// column. These helpers turn a chosen image file into that text and back.

/// Edge of the stored square, in pixels (shown at up to ~48 logical px).
const kAccountIconPixels = 96;

/// Files above this are refused before decoding.
const kAccountIconMaxFileBytes = 10 * 1024 * 1024;

/// A stored icon above this many characters is ignored (a hostile backup).
const kAccountIconMaxChars = 64 * 1024;

class AccountIconException implements Exception {
  final String message;
  const AccountIconException(this.message);
  @override
  String toString() => message;
}

/// Decodes any image the engine understands (PNG, JPEG, GIF's first frame,
/// WebP, BMP), centre-crops it to a square, scales it to
/// [kAccountIconPixels] and returns the PNG as base64.
/// Throws [AccountIconException] for a too large or unreadable file.
Future<String> encodeAccountIcon(Uint8List bytes) async {
  if (bytes.length > kAccountIconMaxFileBytes) {
    throw const AccountIconException('That image is larger than 10 MB.');
  }
  ui.Codec? codec;
  ui.Image? source;
  ui.Image? out;
  try {
    codec = await ui.instantiateImageCodec(bytes);
    source = (await codec.getNextFrame()).image;
    final w = source.width, h = source.height;
    if (w <= 0 || h <= 0) {
      throw const AccountIconException('That image has no pixels.');
    }
    final side = math.min(w, h).toDouble();
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawImageRect(
      source,
      ui.Rect.fromLTWH((w - side) / 2, (h - side) / 2, side, side),
      ui.Rect.fromLTWH(
        0,
        0,
        kAccountIconPixels.toDouble(),
        kAccountIconPixels.toDouble(),
      ),
      ui.Paint()
        ..filterQuality = ui.FilterQuality.high
        ..isAntiAlias = true,
    );
    final picture = recorder.endRecording();
    out = await picture.toImage(kAccountIconPixels, kAccountIconPixels);
    picture.dispose();
    final data = await out.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) {
      throw const AccountIconException('That image could not be converted.');
    }
    final text = base64Encode(data.buffer.asUint8List());
    if (text.length > kAccountIconMaxChars) {
      throw const AccountIconException('That image is too detailed.');
    }
    return text;
  } on AccountIconException {
    rethrow;
  } catch (_) {
    throw const AccountIconException(
      'That file is not an image this app can read.',
    );
  } finally {
    source?.dispose();
    out?.dispose();
    codec?.dispose();
  }
}

// Decoded bytes of the icons on screen, so a list does not base64-decode the
// same string on every rebuild. Small LRU keyed by the stored text itself.
final LinkedHashMap<String, Uint8List?> _decoded = LinkedHashMap();
const _decodedLimit = 48;

/// The PNG bytes of a stored icon, or null when [icon] is empty, too large or
/// not valid base64 (the purse is shown instead). Memoised.
Uint8List? decodeAccountIcon(String? icon) {
  if (icon == null || icon.isEmpty || icon.length > kAccountIconMaxChars) {
    return null;
  }
  if (_decoded.containsKey(icon)) {
    final v = _decoded.remove(icon);
    _decoded[icon] = v; // most recently used goes last
    return v;
  }
  Uint8List? bytes;
  try {
    bytes = base64Decode(icon);
  } catch (_) {
    bytes = null;
  }
  _decoded[icon] = bytes;
  if (_decoded.length > _decodedLimit) _decoded.remove(_decoded.keys.first);
  return bytes;
}

/// Asks for a picture from the phone's PHOTO LIBRARY (the Files picker below
/// cannot browse Photos) and returns its bytes (null = cancelled). Phones only.
final accountIconPhotoPickerProvider =
    Provider<Future<Uint8List?> Function()>(
      (ref) => () async {
        final picked = await ImagePicker().pickImage(
          source: ImageSource.gallery,
          maxWidth: 512,
          maxHeight: 512,
        );
        return picked?.readAsBytes();
      },
    );

/// Asks for an image file and returns its bytes (null = cancelled). A provider
/// so tests can replace the native file dialog. iOS ignores extensions: it
/// needs the type identifier `public.image`.
final accountIconPickerProvider = Provider<Future<Uint8List?> Function()>(
  (ref) => () async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Image',
          extensions: ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'],
          uniformTypeIdentifiers: ['public.image'],
          mimeTypes: ['image/*'],
        ),
      ],
    );
    return file?.readAsBytes();
  },
);

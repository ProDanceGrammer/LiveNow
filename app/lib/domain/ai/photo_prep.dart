import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// The largest photo read for preparation (a phone camera JPEG is 2-8 MB).
const kMaxPhotoInputBytes = 20 * 1024 * 1024;

/// A prepared photo: JPEG [bytes] and their pixel size.
typedef PreparedPhoto = ({Uint8List bytes, int width, int height});

/// Makes a receipt photo small enough to sync and good enough to read: applies
/// the EXIF rotation, scales it so the long side is at most [longSide] pixels
/// (never up) and re-encodes it as JPEG. Pure Dart, CPU heavy: on a phone call
/// it from an isolate (`compute`). Throws [FormatException] for input over
/// [kMaxPhotoInputBytes] or bytes that are not an image.
PreparedPhoto prepareReceiptPhoto(
  Uint8List original, {
  int longSide = 1600,
  int quality = 85,
}) {
  if (original.length > kMaxPhotoInputBytes) {
    throw const FormatException('That photo is too large (over 20 MB).');
  }
  img.Image? image;
  try {
    image = img.decodeImage(original);
  } on Object {
    image = null; // a truncated or foreign file makes decoders throw
  }
  if (image == null) {
    throw const FormatException('That file is not a readable image.');
  }
  image = img.bakeOrientation(image);
  final long = image.width > image.height ? image.width : image.height;
  if (long > longSide) {
    image = image.width >= image.height
        ? img.copyResize(image, width: longSide)
        : img.copyResize(image, height: longSide);
  }
  final bytes = Uint8List.fromList(img.encodeJpg(image, quality: quality));
  return (bytes: bytes, width: image.width, height: image.height);
}

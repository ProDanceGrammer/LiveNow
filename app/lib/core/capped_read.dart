import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

/// Largest import file read into memory as one string. Real exports are well
/// below this (a saved Notion page is a few MB); a bigger one is a mistake or
/// an attack, and `readAsString` would load all of it at once.
const kMaxImportFileBytes = 64 * 1024 * 1024;

/// Turns the bytes of a text file into a string: UTF-8 (a leading byte-order
/// mark is dropped) or UTF-16 with a byte-order mark (Excel's "Unicode text").
/// Anything else that is not valid UTF-8 (a picture, a spreadsheet, a binary)
/// throws a [FormatException] that says so, instead of the raw decoder error.
String decodeImportText(Uint8List bytes, {String name = 'This file'}) {
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
    return _utf16(bytes, Endian.little, name);
  }
  if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
    return _utf16(bytes, Endian.big, name);
  }
  var start = 0;
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    start = 3;
  }
  try {
    return utf8.decode(
      start == 0 ? bytes : Uint8List.sublistView(bytes, start),
    );
  } on FormatException {
    throw FormatException('$name is not a text file (UTF-8)');
  }
}

String _utf16(Uint8List bytes, Endian endian, String name) {
  final body = bytes.length - 2;
  if (body.isOdd) throw FormatException('$name is not a valid text file');
  final data = ByteData.sublistView(bytes, 2);
  final units = List<int>.generate(
    body ~/ 2,
    (i) => data.getUint16(i * 2, endian),
    growable: false,
  );
  try {
    return String.fromCharCodes(units);
  } on Object {
    throw FormatException('$name is not a valid text file');
  }
}

String _mb(int bytes) => '${bytes ~/ (1024 * 1024)} MB';

/// Reads a picked file as text, refusing one over [maxBytes] before reading it.
/// Throws a [FormatException] (the importers already report those to the user)
/// for a file that is too large, unreadable or not text.
Future<String> readTextCapped(
  XFile file, {
  int maxBytes = kMaxImportFileBytes,
}) async {
  final Uint8List bytes;
  try {
    if (await file.length() > maxBytes) {
      throw FormatException(
        '${file.name} is too large (more than ${_mb(maxBytes)})',
      );
    }
    bytes = await file.readAsBytes();
  } on FileSystemException {
    throw FormatException('${file.name} could not be read');
  }
  if (bytes.length > maxBytes) {
    throw FormatException(
      '${file.name} is too large (more than ${_mb(maxBytes)})',
    );
  }
  return decodeImportText(bytes, name: file.name);
}

/// Reads picked bytes (an image) with the same up-front size check.
Future<Uint8List> readBytesCapped(XFile file, {required int maxBytes}) async {
  try {
    if (await file.length() > maxBytes) {
      throw FormatException(
        '${file.name} is too large (more than ${_mb(maxBytes)})',
      );
    }
    return await file.readAsBytes();
  } on FileSystemException {
    throw FormatException('${file.name} could not be read');
  }
}

/// Like [readTextCapped] for a plain [File] (a small file the app itself
/// expects, such as the hub's pairing text).
Future<String> readFileTextCapped(File file, {required int maxBytes}) async {
  final name = file.uri.pathSegments.isEmpty ? 'file' : file.uri.pathSegments.last;
  try {
    if (await file.length() > maxBytes) {
      throw FormatException('$name is too large');
    }
    return decodeImportText(await file.readAsBytes(), name: name);
  } on FileSystemException {
    throw FormatException('$name could not be read');
  }
}

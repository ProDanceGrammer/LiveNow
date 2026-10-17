import 'package:file_selector/file_selector.dart';

/// Largest import file read into memory as one string. Real exports are well
/// below this (a saved Notion page is a few MB); a bigger one is a mistake or
/// an attack, and `readAsString` would load all of it at once.
const kMaxImportFileBytes = 64 * 1024 * 1024;

/// Reads a picked file as text, refusing one over [maxBytes] before reading it.
/// Throws a [FormatException] (the importers already report those to the user).
Future<String> readTextCapped(
  XFile file, {
  int maxBytes = kMaxImportFileBytes,
}) async {
  if (await file.length() > maxBytes) {
    throw FormatException(
      '${file.name} is too large (more than ${maxBytes ~/ (1024 * 1024)} MB)',
    );
  }
  return file.readAsString();
}

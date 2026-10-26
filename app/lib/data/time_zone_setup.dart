import 'dart:io';

import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/timezone.dart' as tz;

import '../core/settings.dart';
import 'accounts/profile_paths.dart';

// Which timezone the app lives in: the computer's own by default, or a zone
// chosen in Settings (kept in a per-DEVICE file, so a phone and a PC can
// differ). Applied once at start-up: the day arithmetic everywhere reads
// AppSettings.timeZoneName.

const _fileName = 'time_zone.txt';

// Never touch the real app-data folder or ask the OS from `flutter test`.
final bool _underTest = Platform.environment.containsKey('FLUTTER_TEST');

/// Whether the timezone database knows [name].
bool isKnownTimeZone(String name) {
  try {
    tz.getLocation(name);
    return true;
  } on Object {
    return false;
  }
}

Future<File> _file() async =>
    File('${(await appSupportRoot()).path}/$_fileName');

/// The zone chosen in Settings, or null = follow the computer.
Future<String?> readTimeZoneOverride() async {
  if (_underTest) return null;
  try {
    final text = (await (await _file()).readAsString()).trim();
    return text.isEmpty || !isKnownTimeZone(text) ? null : text;
  } on Object {
    return null;
  }
}

/// Saves the choice ([name] null = follow the computer). Best-effort.
Future<void> writeTimeZoneOverride(String? name) async {
  if (_underTest) return;
  try {
    final f = await _file();
    if (name == null) {
      if (await f.exists()) await f.delete();
    } else {
      await f.create(recursive: true);
      await f.writeAsString(name);
    }
  } on Object {
    // The choice then applies until the app closes only.
  }
}

/// The operating system's zone as an IANA name, or null when it cannot be
/// read or the database does not know it.
Future<String?> detectDeviceTimeZone() async {
  if (_underTest) return null;
  try {
    final id = (await FlutterTimezone.getLocalTimezone()).identifier;
    return isKnownTimeZone(id) ? id : null;
  } on Object {
    return null;
  }
}

/// Start-up: the override, else the computer's zone, else the default.
Future<void> applyConfiguredTimeZone() async {
  final name =
      await readTimeZoneOverride() ??
      await detectDeviceTimeZone() ??
      AppSettings.defaultTimeZoneName;
  AppSettings.setTimeZoneName(name);
}

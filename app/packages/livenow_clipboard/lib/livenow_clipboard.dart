import 'dart:async';

import 'package:flutter/services.dart';

/// A statement file (CSV / XLSX / XLS): its name and bytes.
typedef StatementFile = ({String name, Uint8List bytes});

/// Every image on the iOS clipboard (several photos copied in Photos paste as
/// several images), statement files on the clipboard and files opened in
/// LiveNow from another app (share sheet / "Open in"). Only iOS has a native
/// side: elsewhere the calls throw [MissingPluginException] and the caller
/// falls back to `pasteboard` (or does nothing).
class LivenowClipboard {
  static const _channel = MethodChannel('livenow_clipboard');
  static final _incoming = StreamController<void>.broadcast();
  static bool _handlerSet = false;

  /// True when the clipboard holds an image. Does not read the content, so
  /// iOS shows no "Allow Paste" prompt.
  static Future<bool> hasImages() async =>
      await _channel.invokeMethod<bool>('hasImages') ?? false;

  /// The bytes of every image on the clipboard (JPEG/PNG as copied, any other
  /// image type re-encoded as JPEG), in clipboard order.
  static Future<List<Uint8List>> images() async {
    final list = await _channel.invokeMethod<List<Object?>>('images');
    return [
      for (final e in list ?? const <Object?>[])
        if (e is Uint8List) e,
    ];
  }

  /// True when the clipboard holds a csv/xlsx/xls item or a file URL to one.
  /// Reads no content (no "Allow Paste" prompt).
  static Future<bool> hasFiles() async =>
      await _channel.invokeMethod<bool>('hasFiles') ?? false;

  /// The statement files on the clipboard (name, bytes), in clipboard order.
  static Future<List<StatementFile>> files() async {
    final list = await _channel.invokeMethod<List<Object?>>('files');
    return [
      for (final e in list ?? const <Object?>[])
        if (e is Map && e['bytes'] is Uint8List)
          (name: '${e['name'] ?? 'statement.csv'}', bytes: e['bytes'] as Uint8List),
    ];
  }

  /// The file another app opened in LiveNow, or null. Returns it ONCE: the
  /// native side forgets it.
  static Future<StatementFile?> takeIncomingFile() async {
    final e = await _channel.invokeMethod<Object?>('takeIncomingFile');
    if (e is Map && e['bytes'] is Uint8List) {
      return (
        name: '${e['name'] ?? 'statement.csv'}',
        bytes: e['bytes'] as Uint8List,
      );
    }
    return null;
  }

  /// Fires when a file arrives while the app runs; call [takeIncomingFile]
  /// to fetch it.
  static Stream<void> get onIncomingFile {
    if (!_handlerSet) {
      _handlerSet = true;
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'incomingFile') _incoming.add(null);
        return null;
      });
    }
    return _incoming.stream;
  }
}

import 'package:flutter/services.dart';

/// Every image on the iOS clipboard (several photos copied in Photos paste as
/// several images). Only iOS has a native side: elsewhere the calls throw
/// [MissingPluginException] and the caller falls back to `pasteboard`.
class LivenowClipboard {
  static const _channel = MethodChannel('livenow_clipboard');

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
}

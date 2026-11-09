import 'dart:io';

import '../data/ai/ocr_client.dart';

/// Starts the hub PC's OCR service when it is not running, so receipts do not
/// depend on the "LiveNow AI" logon task (`app/windows/hub/ai/install_ai.ps1`)
/// having been registered. It starts exactly what that task starts: the
/// installed venv's `pythonw.exe ocr_service.py --port <port> --log ocr.log`
/// from `%LOCALAPPDATA%\LiveNowHub\ai`, detached, so it keeps running after
/// the hub stops. Only on Windows, only for a loopback URL, only when the
/// service is installed; never throws.
class OcrLauncher {
  OcrLauncher({
    String? aiDir,
    bool? isWindows,
    Future<bool> Function(String url)? health,
    Future<void> Function(String exe, List<String> args, String workDir)? start,
    bool Function(String path)? exists,
    DateTime Function()? clock,
    Future<void> Function(Duration)? sleep,
    this.startupWait = const Duration(seconds: 90),
    this.pollEvery = const Duration(seconds: 2),
    this.minRelaunchGap = const Duration(minutes: 2),
    void Function(String line)? log,
  }) : _aiDir = aiDir ?? _defaultAiDir(),
       _isWindows = isWindows ?? Platform.isWindows,
       _health = health ?? ((url) => OcrClient(baseUrl: url).health()),
       _start = start ?? _startDetached,
       _exists = exists ?? ((p) => File(p).existsSync()),
       _clock = clock ?? DateTime.now,
       _sleep = sleep ?? Future<void>.delayed,
       _log = log ?? ((_) {});

  /// RapidOCR loads its models before it answers `/health`.
  final Duration startupWait;
  final Duration pollEvery;

  /// A service that dies right after start is not restarted in a tight loop.
  final Duration minRelaunchGap;

  final String? _aiDir;
  final bool _isWindows;
  final Future<bool> Function(String url) _health;
  final Future<void> Function(String exe, List<String> args, String workDir) _start;
  final bool Function(String path) _exists;
  final DateTime Function() _clock;
  final Future<void> Function(Duration) _sleep;
  final void Function(String) _log;

  DateTime? _lastLaunch;
  bool _launching = false;

  /// True when the service answers (already, or after starting it).
  Future<bool> ensureRunning(String ocrUrl) async {
    try {
      if (await _health(ocrUrl)) return true;
      final uri = Uri.tryParse(ocrUrl);
      final dir = _aiDir;
      if (!_isWindows || uri == null || !_isLoopback(uri.host) || dir == null) {
        return false;
      }
      final exe = '$dir\\venv\\Scripts\\pythonw.exe';
      final script = '$dir\\ocr_service.py';
      if (!_exists(exe) || !_exists(script)) return false;
      final now = _clock();
      final last = _lastLaunch;
      if (_launching || (last != null && now.difference(last) < minRelaunchGap)) {
        return false;
      }
      _launching = true;
      _lastLaunch = now;
      try {
        _log('AI: starting the OCR service ($exe, port ${uri.port})');
        await _start(exe, [
          script,
          '--port',
          '${uri.port}',
          '--log',
          '$dir\\ocr.log',
        ], dir);
        final polls = startupWait.inMilliseconds ~/ pollEvery.inMilliseconds;
        for (var i = 0; i < polls; i++) {
          await _sleep(pollEvery);
          if (await _health(ocrUrl)) {
            _log('AI: OCR service is up');
            return true;
          }
        }
        _log('AI: the OCR service did not answer within ${startupWait.inSeconds} s');
        return false;
      } finally {
        _launching = false;
      }
    } on Object catch (e) {
      _log('AI: could not start the OCR service: $e');
      return false;
    }
  }

  static bool _isLoopback(String host) =>
      host == '127.0.0.1' || host == 'localhost' || host == '::1' || host == '[::1]';

  static String? _defaultAiDir() {
    final base = Platform.environment['LOCALAPPDATA'];
    return base == null || base.isEmpty ? null : '$base\\LiveNowHub\\ai';
  }

  static Future<void> _startDetached(
    String exe,
    List<String> args,
    String workDir,
  ) async {
    await Process.start(
      exe,
      args,
      workingDirectory: workDir,
      mode: ProcessStartMode.detached,
    );
  }
}

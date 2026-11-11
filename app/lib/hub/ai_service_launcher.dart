import 'dart:io';

import '../data/ai/llm_client.dart';
import '../data/ai/ocr_client.dart';

/// Starts the hub PC's OCR service and model server (Ollama) when they are not
/// running, so receipts depend neither on the "LiveNow AI" logon task
/// (`app/windows/hub/ai/install_ai.ps1`) having been registered nor on
/// Ollama's tray app keeping its server alive (its auto-updater stops it).
///
/// - OCR: exactly what that task starts, the installed venv's
///   `pythonw.exe ocr_service.py --port <port> --log ocr.log` from
///   `%LOCALAPPDATA%\LiveNowHub\ai`.
/// - Model server: `%LOCALAPPDATA%\Programs\Ollama\ollama.exe serve` with
///   `OLLAMA_HOST=127.0.0.1:<port>`.
///
/// Both start detached (they keep running after the hub stops), only on
/// Windows, only for a loopback URL, only when installed. Never throws.
class AiServiceLauncher {
  AiServiceLauncher({
    String? aiDir,
    String? ollamaExe,
    bool? isWindows,
    Future<bool> Function(String url)? ocrHealth,
    Future<bool> Function(String url)? modelHealth,
    Future<void> Function(
      String exe,
      List<String> args,
      String workDir,
      Map<String, String> environment,
    )?
    start,
    bool Function(String path)? exists,
    DateTime Function()? clock,
    Future<void> Function(Duration)? sleep,
    this.ocrStartupWait = const Duration(seconds: 90),
    this.modelStartupWait = const Duration(seconds: 60),
    this.pollEvery = const Duration(seconds: 2),
    this.minRelaunchGap = const Duration(minutes: 2),
    void Function(String line)? log,
  }) : _aiDir = aiDir ?? _localAppData(r'LiveNowHub\ai'),
       _ollamaExe = ollamaExe ?? _localAppData(r'Programs\Ollama\ollama.exe'),
       _isWindows = isWindows ?? Platform.isWindows,
       _ocrHealth = ocrHealth ?? ((url) => OcrClient(baseUrl: url).health()),
       _modelHealth =
           modelHealth ?? ((url) => LlmClient(baseUrl: url, model: '').health()),
       _start = start ?? _startDetached,
       _exists = exists ?? ((p) => File(p).existsSync()),
       _clock = clock ?? DateTime.now,
       _sleep = sleep ?? Future<void>.delayed,
       _log = log ?? ((_) {});

  /// RapidOCR loads its models before it answers `/health`.
  final Duration ocrStartupWait;

  /// `ollama serve` probes the GPU first: ~20-35 s on the dev PC (models load per request).
  final Duration modelStartupWait;
  final Duration pollEvery;

  /// A service that dies right after start is not restarted in a tight loop.
  final Duration minRelaunchGap;

  final String? _aiDir;
  final String? _ollamaExe;
  final bool _isWindows;
  final Future<bool> Function(String url) _ocrHealth;
  final Future<bool> Function(String url) _modelHealth;
  final Future<void> Function(
    String exe,
    List<String> args,
    String workDir,
    Map<String, String> environment,
  )
  _start;
  final bool Function(String path) _exists;
  final DateTime Function() _clock;
  final Future<void> Function(Duration) _sleep;
  final void Function(String) _log;

  final Map<String, DateTime> _lastLaunch = {};
  final Set<String> _launching = {};

  /// True when the OCR service answers (already, or after starting it).
  Future<bool> ensureOcr(String url) {
    final dir = _aiDir;
    final port = Uri.tryParse(url)?.port;
    return _ensure(
      name: 'the OCR service',
      url: url,
      health: _ocrHealth,
      startupWait: ocrStartupWait,
      command: dir == null || port == null
          ? null
          : (
              exe: '$dir\\venv\\Scripts\\pythonw.exe',
              args: ['$dir\\ocr_service.py', '--port', '$port', '--log', '$dir\\ocr.log'],
              workDir: dir,
              environment: const <String, String>{},
              needs: ['$dir\\venv\\Scripts\\pythonw.exe', '$dir\\ocr_service.py'],
            ),
    );
  }

  /// True when the model server answers (already, or after starting Ollama).
  Future<bool> ensureModel(String url) {
    final exe = _ollamaExe;
    final port = Uri.tryParse(url)?.port;
    return _ensure(
      name: 'the model server',
      url: url,
      health: _modelHealth,
      startupWait: modelStartupWait,
      command: exe == null || port == null
          ? null
          : (
              exe: exe,
              args: const ['serve'],
              workDir: File(exe).parent.path,
              environment: {'OLLAMA_HOST': '127.0.0.1:$port'},
              needs: [exe],
            ),
    );
  }

  Future<bool> _ensure({
    required String name,
    required String url,
    required Future<bool> Function(String url) health,
    required Duration startupWait,
    required ({
      String exe,
      List<String> args,
      String workDir,
      Map<String, String> environment,
      List<String> needs,
    })?
    command,
  }) async {
    try {
      if (await health(url)) return true;
      final uri = Uri.tryParse(url);
      if (!_isWindows || uri == null || !_isLoopback(uri.host) || command == null) {
        return false;
      }
      if (!command.needs.every(_exists)) return false;
      final now = _clock();
      final last = _lastLaunch[name];
      if (_launching.contains(name) ||
          (last != null && now.difference(last) < minRelaunchGap)) {
        return false;
      }
      _launching.add(name);
      _lastLaunch[name] = now;
      try {
        _log('AI: starting $name (${command.exe}, port ${uri.port})');
        await _start(command.exe, command.args, command.workDir, command.environment);
        final polls = startupWait.inMilliseconds ~/ pollEvery.inMilliseconds;
        for (var i = 0; i < polls; i++) {
          await _sleep(pollEvery);
          if (await health(url)) {
            _log('AI: $name is up');
            return true;
          }
        }
        _log('AI: $name did not answer within ${startupWait.inSeconds} s');
        return false;
      } finally {
        _launching.remove(name);
      }
    } on Object catch (e) {
      _log('AI: could not start $name: $e');
      return false;
    }
  }

  static bool _isLoopback(String host) =>
      host == '127.0.0.1' || host == 'localhost' || host == '::1' || host == '[::1]';

  static String? _localAppData(String sub) {
    final base = Platform.environment['LOCALAPPDATA'];
    return base == null || base.isEmpty ? null : '$base\\$sub';
  }

  static Future<void> _startDetached(
    String exe,
    List<String> args,
    String workDir,
    Map<String, String> environment,
  ) async {
    await Process.start(
      exe,
      args,
      workingDirectory: workDir,
      environment: environment,
      mode: ProcessStartMode.detached,
    );
  }
}

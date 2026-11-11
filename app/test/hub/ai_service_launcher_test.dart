import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/hub/ai_service_launcher.dart';

const _dir = r'C:\Users\u\AppData\Local\LiveNowHub\ai';
const _ollama = r'C:\Users\u\AppData\Local\Programs\Ollama\ollama.exe';
const _ocrUrl = 'http://127.0.0.1:47655';
const _modelUrl = 'http://127.0.0.1:11434';

void main() {
  late List<List<String>> started;
  late List<Map<String, String>> envs;
  late Set<String> up;
  late int healthCalls;
  late DateTime now;

  setUp(() {
    started = [];
    envs = [];
    up = {};
    healthCalls = 0;
    now = DateTime.utc(2026, 11, 10, 1);
  });

  AiServiceLauncher make({
    bool isWindows = true,
    bool installed = true,
    int upAfterPolls = 2,
  }) {
    Future<bool> health(String service) async {
      healthCalls++;
      // Comes up after a few polls once it was started.
      if (started.any((c) => c.first.contains(service)) && healthCalls > upAfterPolls) {
        up.add(service);
      }
      return up.contains(service);
    }

    return AiServiceLauncher(
      aiDir: _dir,
      ollamaExe: _ollama,
      isWindows: isWindows,
      ocrHealth: (_) => health('pythonw'),
      modelHealth: (_) => health('ollama'),
      start: (exe, args, wd, env) async {
        started.add([exe, ...args, wd]);
        envs.add(env);
      },
      exists: (p) => installed,
      clock: () => now,
      sleep: (_) async {},
      ocrStartupWait: const Duration(seconds: 10),
      modelStartupWait: const Duration(seconds: 10),
      pollEvery: const Duration(seconds: 1),
    );
  }

  test('running services are left alone', () async {
    up = {'pythonw', 'ollama'};
    final l = make();
    expect(await l.ensureOcr(_ocrUrl), isTrue);
    expect(await l.ensureModel(_modelUrl), isTrue);
    expect(started, isEmpty);
  });

  test('starts the installed OCR service like the logon task does, waits for /health', () async {
    expect(await make().ensureOcr(_ocrUrl), isTrue);
    expect(started, [
      [
        '$_dir\\venv\\Scripts\\pythonw.exe',
        '$_dir\\ocr_service.py',
        '--port',
        '47655',
        '--log',
        '$_dir\\ocr.log',
        _dir,
      ],
    ]);
  });

  test('starts "ollama serve" on the configured port, waits until it answers', () async {
    expect(await make().ensureModel(_modelUrl), isTrue);
    expect(started, [
      [_ollama, 'serve', r'C:\Users\u\AppData\Local\Programs\Ollama'],
    ]);
    expect(envs.single, {'OLLAMA_HOST': '127.0.0.1:11434'});
  });

  test('starts nothing when not installed, not Windows, or not on this PC', () async {
    expect(await make(installed: false).ensureOcr(_ocrUrl), isFalse);
    expect(await make(installed: false).ensureModel(_modelUrl), isFalse);
    expect(await make(isWindows: false).ensureModel(_modelUrl), isFalse);
    expect(await make().ensureOcr('http://192.168.1.5:47655'), isFalse);
    expect(await make().ensureModel('https://api.example.com'), isFalse);
    expect(started, isEmpty);
  });

  test('a service that does not come up is not relaunched in a tight loop; the other one still starts', () async {
    final l = make(upAfterPolls: 1 << 30);
    expect(await l.ensureModel(_modelUrl), isFalse);
    expect(await l.ensureModel(_modelUrl), isFalse);
    expect(started, hasLength(1));
    expect(await l.ensureOcr(_ocrUrl), isFalse);
    expect(started, hasLength(2), reason: 'throttled per service');
    now = now.add(const Duration(minutes: 3));
    expect(await l.ensureModel(_modelUrl), isFalse);
    expect(started, hasLength(3));
  });

  test('a failing start is reported as false, never thrown', () async {
    final l = AiServiceLauncher(
      aiDir: _dir,
      ollamaExe: _ollama,
      isWindows: true,
      ocrHealth: (_) async => false,
      modelHealth: (_) async => false,
      start: (_, _, _, _) async => throw StateError('no exe'),
      exists: (_) => true,
      sleep: (_) async {},
    );
    expect(await l.ensureOcr(_ocrUrl), isFalse);
    expect(await l.ensureModel(_modelUrl), isFalse);
  });
}

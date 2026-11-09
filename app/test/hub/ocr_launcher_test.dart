import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/hub/ocr_launcher.dart';

const _dir = r'C:\Users\u\AppData\Local\LiveNowHub\ai';
const _url = 'http://127.0.0.1:47655';

void main() {
  late List<List<String>> started;
  late bool up;
  late int healthCalls;
  late DateTime now;

  setUp(() {
    started = [];
    up = false;
    healthCalls = 0;
    now = DateTime.utc(2026, 11, 9, 20);
  });

  OcrLauncher make({
    bool isWindows = true,
    bool installed = true,
    int upAfterPolls = 2,
  }) => OcrLauncher(
    aiDir: _dir,
    isWindows: isWindows,
    health: (url) async {
      healthCalls++;
      // Comes up after a few polls once it was started.
      if (started.isNotEmpty && healthCalls > upAfterPolls) up = true;
      return up;
    },
    start: (exe, args, wd) async => started.add([exe, ...args, wd]),
    exists: (p) => installed,
    clock: () => now,
    sleep: (_) async {},
    startupWait: const Duration(seconds: 10),
    pollEvery: const Duration(seconds: 1),
  );

  test('a running service is left alone', () async {
    up = true;
    expect(await make().ensureRunning(_url), isTrue);
    expect(started, isEmpty);
  });

  test('starts the installed service like the logon task does, waits for /health', () async {
    expect(await make().ensureRunning(_url), isTrue);
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

  test('starts nothing when not installed, not Windows, or not on this PC', () async {
    expect(await make(installed: false).ensureRunning(_url), isFalse);
    expect(await make(isWindows: false).ensureRunning(_url), isFalse);
    expect(await make().ensureRunning('http://192.168.1.5:47655'), isFalse);
    expect(started, isEmpty);
  });

  test('a service that does not come up is not relaunched in a tight loop', () async {
    final l = make(upAfterPolls: 1 << 30);
    expect(await l.ensureRunning(_url), isFalse);
    expect(await l.ensureRunning(_url), isFalse);
    expect(started, hasLength(1));
    now = now.add(const Duration(minutes: 3));
    expect(await l.ensureRunning(_url), isFalse);
    expect(started, hasLength(2));
  });

  test('a failing start is reported as false, never thrown', () async {
    final l = OcrLauncher(
      aiDir: _dir,
      isWindows: true,
      health: (_) async => false,
      start: (_, _, _) async => throw StateError('no python'),
      exists: (_) => true,
      sleep: (_) async {},
    );
    expect(await l.ensureRunning(_url), isFalse);
  });
}

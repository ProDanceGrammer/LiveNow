import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/core/platform_info.dart';
import 'package:livenow/ui/shortcut_keys.dart';
import 'package:livenow/ui/sync_providers.dart';

void main() {
  group('primaryActivator', () {
    test('is Ctrl+key off a Mac', () {
      expect(isMacPlatform, isFalse);
      final a = primaryActivator(LogicalKeyboardKey.keyZ);
      expect(a.control, isTrue);
      expect(a.meta, isFalse);
    });

    test('is Cmd+key on a Mac, with Shift when asked', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        expect(isMacPlatform, isTrue);
        final a = primaryActivator(LogicalKeyboardKey.keyL, shift: true);
        expect(a.meta, isTrue);
        expect(a.control, isFalse);
        expect(a.shift, isTrue);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  group('hubStartCommand', () {
    Future<ProcessResult> fakeRun(String exe, List<String> args) async =>
        ProcessResult(0, 0, '501\n', '');

    test('Windows starts the scheduled task', () async {
      final c = await hubStartCommand(fakeRun, os: 'windows');
      expect(c!.$1, 'schtasks');
      expect(c.$2, ['/run', '/tn', 'LiveNow Hub']);
    });

    test('macOS kickstarts the launchd agent of the current user', () async {
      final c = await hubStartCommand(fakeRun, os: 'macos');
      expect(c!.$1, 'launchctl');
      expect(c.$2, ['kickstart', '-k', 'gui/501/io.livenow.hub']);
    });

    test('other systems have no hub job', () async {
      expect(await hubStartCommand(fakeRun, os: 'linux'), isNull);
    });
  });
}

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/ai/ai_chat_service.dart';
import 'package:livenow/domain/postpone_rules.dart';
import 'package:livenow/ui/ai_ui_providers.dart';
import 'package:livenow/ui/providers.dart';
import 'package:livenow/ui/screens/ai_chat_screen.dart';
import 'package:livenow/ui/sync_providers.dart';
import 'package:livenow/ui/widgets/keyboard_hide_button.dart';

import '../domain/ai/ai_test_support.dart';

class _Hub extends HubConnected {
  @override
  bool build() => true;
}

void main() {
  setUpAll(initPostponeTimeZoneData);
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  late AppDatabase db;
  late String thread;

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pump(const Duration(milliseconds: 10));
    }
  }

  Future<void> mount(
    WidgetTester tester, {
    List<Uint8List> clipboard = const [],
    Widget? extra,
  }) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(tester.view.resetViewInsets);
    db = memoryDb();
    await tester.runAsync(() async {
      thread = await AiChatService(db).createThread(title: 'T');
    });
    final overrides = <Override>[
      databaseProvider.overrideWithValue(db),
      hubConnectedProvider.overrideWith(_Hub.new),
      aiClipboardPhotosProvider.overrideWithValue(
        ClipboardPhotos(
          has: () async => clipboard.isNotEmpty,
          read: () async => clipboard,
        ),
      ),
      aiPhotoPrepProvider.overrideWithValue(
        (b) async => (bytes: b, width: 10, height: 20),
      ),
    ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          builder: (context, c) => KeyboardHideLayer(child: c!),
          home: AiChatScreen(threadId: thread),
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
    await tester.runAsync(db.close);
  }

  final png = Uint8List.fromList([
    0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 1, 2, 3, //
  ]);

  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('ai-chat-input')));
    await tester.pump();
    tester
        .state<EditableTextState>(find.byType(EditableText))
        .showToolbar();
    await settle(tester);
  }

  testWidgets('clipboard PNG: "Paste photo" adds a pending photo', (
    tester,
  ) async {
    await mount(tester, clipboard: [png]);
    await openMenu(tester);
    expect(find.text('Paste photo'), findsOneWidget);
    await tester.tap(find.text('Paste photo'));
    await settle(tester);
    expect(find.byKey(const ValueKey('ai-chat-pending-0')), findsOneWidget);
    await finish(tester);
  });

  testWidgets('several copied photos: "Paste photo" adds them all', (
    tester,
  ) async {
    await mount(tester, clipboard: [png, png, png]);
    await openMenu(tester);
    await tester.tap(find.text('Paste photo'));
    await settle(tester);
    for (var i = 0; i < 3; i++) {
      expect(find.byKey(ValueKey('ai-chat-pending-$i')), findsOneWidget);
    }
    await finish(tester);
  });

  testWidgets('text-only clipboard: no "Paste photo" item', (tester) async {
    await mount(tester);
    await openMenu(tester);
    expect(find.text('Paste photo'), findsNothing);
    expect(find.byKey(const ValueKey('ai-chat-pending-0')), findsNothing);
    await finish(tester);
  });

  testWidgets('iOS keyboard: Send sits above the hide button', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await mount(tester);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final hide = tester.getRect(find.byKey(const ValueKey('keyboard-hide')));
    final send = tester.getRect(find.byKey(const ValueKey('ai-chat-send')));
    expect(send.overlaps(hide), isFalse);
    expect(send.bottom, lessThanOrEqualTo(hide.top));
    debugDefaultTargetPlatformOverride = null;
    await finish(tester);
  });

  testWidgets('iOS keyboard: a Scaffold FAB clears the hide button', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, c) => KeyboardHideLayer(child: c!),
        home: Scaffold(
          body: const SizedBox.expand(),
          floatingActionButton: FloatingActionButton(
            key: const ValueKey('fab'),
            onPressed: () {},
            child: const Icon(Icons.add),
          ),
        ),
      ),
    );
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    final hide = tester.getRect(find.byKey(const ValueKey('keyboard-hide')));
    final fab = tester.getRect(find.byKey(const ValueKey('fab')));
    expect(fab.overlaps(hide), isFalse);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('not iOS: no strip, the child sees the real inset', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    late double seen;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, c) => KeyboardHideLayer(child: c!),
        home: Builder(
          builder: (context) {
            seen = MediaQuery.viewInsetsOf(context).bottom;
            return const SizedBox();
          },
        ),
      ),
    );
    expect(find.byKey(const ValueKey('keyboard-hide')), findsNothing);
    expect(seen, 300);
    debugDefaultTargetPlatformOverride = null;
  });
}

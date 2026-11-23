import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/postpone_rules.dart';
import 'package:livenow/main.dart';
import 'package:livenow/ui/providers.dart';
import 'package:livenow/ui/screens/ai_threads_screen.dart';
import 'package:livenow/ui/screens/settings_screen.dart';
import 'package:livenow/ui/widgets/glass.dart';

Future<void> _pumpApp(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(db.close);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: const LiveNowApp(),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 1));
}

final _button = find.byKey(const ValueKey('ai-chat-button'));

/// Goes to a section: rail label on desktop, bottom bar label on phone.
Future<void> _goTo(WidgetTester tester, String label, int i) async {
  final phone = find.byKey(const ValueKey('phone-nav'));
  await tester.tap(
    phone.evaluate().isNotEmpty
        ? find
              .descendant(of: phone, matching: find.byType(NavigationDestination))
              .at(i)
        : find.text(label).first,
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(initPostponeTimeZoneData);

  for (final size in const [Size(400, 800), Size(1400, 900)]) {
    testWidgets('assistant button in every section at $size', (tester) async {
      await _pumpApp(tester, size);

      const sections = ['Actions', 'Growth directions', 'Budget'];
      for (var i = 0; i < sections.length; i++) {
        await _goTo(tester, sections[i], i);
        expect(_button, findsOneWidget, reason: sections[i]);
      }

      await tester.tap(_button);
      await tester.pumpAndSettle();
      expect(find.byType(AiThreadsScreen), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(AiThreadsScreen), findsNothing);

      await _unmount(tester);
    });
  }

  for (final open in <String, Future<void> Function(BuildContext)>{
    'AiThreadsScreen': AiThreadsScreen.open,
    'SettingsScreen': SettingsScreen.open,
  }.entries) {
    testWidgets('pushed ${open.key} sits on an opaque GlassPage', (
      tester,
    ) async {
      await _pumpApp(tester, const Size(400, 800));
      open.value(tester.element(find.byType(Scaffold).first));
      await tester.pumpAndSettle();
      final page = find.byType(GlassPage);
      expect(page, findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w.key == const ValueKey<String>('glass-page') ||
              w.key == const ValueKey<String>('glass-page-fallback'),
        ),
        findsOneWidget,
      );
      expect(
        tester.getSize(find.byType(GlassPage)),
        const Size(400, 800),
      );
      await _unmount(tester);
    });
  }
}

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/postpone_rules.dart';
import 'package:livenow/main.dart';
import 'package:livenow/ui/providers.dart';
import 'package:livenow/ui/theme_mode.dart';

void main() {
  setUpAll(initPostponeTimeZoneData);

  testWidgets('dark mode toggles via provider, menu and Ctrl+Shift+L', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const LiveNowApp(),
      ),
    );
    await tester.pumpAndSettle();

    // 'Current Actions' is both the app bar title and a label of the Actions
    // switch; probe the theme at the title.
    Brightness brightness() => Theme.of(
      tester.element(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('Current Actions'),
        ),
      ),
    ).brightness;

    expect(brightness(), Brightness.light);

    container.read(themeModeProvider.notifier).setMode(ThemeMode.dark);
    await tester.pumpAndSettle();
    expect(brightness(), Brightness.dark);

    // Ctrl+Shift+L toggles back (once, not twice).
    Future<void> chord() async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
    }

    await chord();
    expect(brightness(), Brightness.light);

    // Works with a dialog open too.
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    expect(find.text('New action'), findsOneWidget);
    await chord();
    expect(brightness(), Brightness.dark);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    // The View menu item reflects state and toggles.
    await tester.tap(find.text('View'));
    await tester.pumpAndSettle();
    expect(find.text('Dark mode'), findsOneWidget);
    expect(
      tester.widget<CheckboxMenuButton>(find.byType(CheckboxMenuButton)).value,
      isTrue,
    );
    await tester.tap(find.text('Dark mode'));
    await tester.pumpAndSettle();
    expect(brightness(), Brightness.light);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });
}

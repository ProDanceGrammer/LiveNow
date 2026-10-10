import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/data/queries.dart';
import 'package:livenow/domain/postpone_rules.dart';
import 'package:livenow/main.dart';
import 'package:livenow/ui/current_icons.dart';
import 'package:livenow/ui/providers.dart';
import 'package:livenow/ui/widgets/action_card.dart';

void main() {
  setUpAll(initPostponeTimeZoneData);

  // A card whose time line is long (it spans two days) with an urgency and
  // four direction emoji: the very case of the overflow screenshot.
  final item = ActionListItem(
    id: 'a1',
    name: '[#23] Розробка застосунку',
    done: false,
    startAt: DateTime.utc(2026, 10, 9, 19, 40),
    endAt: DateTime.utc(2026, 10, 9, 20, 48),
    isAllDay: false,
  );

  Future<void> pumpCard(
    WidgetTester tester, {
    required double width,
    bool? iconsOn,
  }) async {
    tester.view.physicalSize = Size(width, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          actionDirectionIconsProvider.overrideWithValue({'a1': '💻🧠🎾😜'}),
          actionUrgencyProvider.overrideWithValue({'a1': -91}),
          if (iconsOn != null)
            currentIconsProvider.overrideWith(
              () => CurrentIconsNotifier(iconsOn),
            ),
        ],
        child: MaterialApp(
          home: Scaffold(body: ActionCard(action: item)),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  final badge = find.byKey(const ValueKey('actionCardIcons'));

  group('card layout', () {
    // An overflow is a FlutterError, which fails the test by itself.
    for (final width in [900.0, 520.0, 420.0, 340.0]) {
      testWidgets('long time line + urgency + badge fit at $width px', (
        tester,
      ) async {
        await pumpCard(tester, width: width);
        expect(tester.takeException(), isNull);
        expect(badge, findsOneWidget);
        expect(find.byKey(const ValueKey('actionUrgencyChip')), findsOneWidget);
        await unmount(tester);
      });
    }

    testWidgets('the time label wraps instead of pushing the badge out', (
      tester,
    ) async {
      await pumpCard(tester, width: 340);
      final card = tester.getRect(find.byType(ActionCard));
      final badgeRect = tester.getRect(badge);
      expect(badgeRect.right, lessThanOrEqualTo(card.right));
      expect(badgeRect.left, greaterThanOrEqualTo(card.left));
      await unmount(tester);
    });
  });

  group('hiding the direction icons', () {
    testWidgets('on by default; off removes the badge, urgency stays', (
      tester,
    ) async {
      await pumpCard(tester, width: 600);
      expect(badge, findsOneWidget);
      await unmount(tester);

      await pumpCard(tester, width: 600, iconsOn: false);
      expect(badge, findsNothing);
      expect(find.byKey(const ValueKey('actionUrgencyChip')), findsOneWidget);
      expect(find.textContaining('Розробка'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('the Actions tab bar has the switch on Current only', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 900);
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

      final toggle = find.byKey(const ValueKey('current-icons-toggle'));
      final container = ProviderScope.containerOf(
        tester.element(find.byType(Scaffold).first),
      );
      expect(toggle, findsOneWidget);
      expect(container.read(currentIconsProvider), isTrue);

      await tester.tap(toggle);
      await tester.pump();
      expect(container.read(currentIconsProvider), isFalse);
      await tester.tap(toggle);
      await tester.pump();
      expect(container.read(currentIconsProvider), isTrue);

      // Not on the Calendar tab (it has its own switch).
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('actions-switch')),
          matching: find.text('Calendar'),
        ),
      );
      await tester.pumpAndSettle();
      expect(toggle, findsNothing);

      await unmount(tester);
    });
  });
}

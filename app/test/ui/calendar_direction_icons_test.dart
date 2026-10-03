import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/action_service.dart';
import 'package:livenow/domain/growth_rules.dart';
import 'package:livenow/domain/metric_service.dart';
import 'package:livenow/domain/postpone_rules.dart';
import 'package:livenow/ui/calendar_icons.dart';
import 'package:livenow/ui/providers.dart';
import 'package:livenow/ui/views/calendar_layout.dart';
import 'package:livenow/ui/views/calendar_view.dart';

void main() {
  setUpAll(initPostponeTimeZoneData);

  group('actionDirectionIconsProvider', () {
    test(
      'joins icons in a stable order, caps at 4 + n, skips blanks',
      () async {
        final db = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(db.close);
        final container = ProviderContainer(
          overrides: [databaseProvider.overrideWithValue(db)],
        );
        addTearDown(container.dispose);
        final sub = container.listen(actionDirectionIconsProvider, (_, _) {});
        addTearDown(sub.close);

        final metrics = MetricService(db);
        Future<String> metric(String name, String? icon) => metrics.saveMetric(
          name: name,
          kind: MetricKind.boolean,
          icon: Value(icon),
        );
        final ids = [
          await metric('a', 'A'),
          await metric('b', 'B'),
          await metric('c', 'C'),
          await metric('d', 'D'),
          await metric('e', 'E'),
          await metric('f', 'F'),
        ];
        final blank = await metric('blank', '  ');
        final plain = await metric('plain', null);

        final actions = container.read(actionServiceProvider);
        final many = await actions.createAction(name: 'many', metricIds: ids);
        final one = await actions.createAction(
          name: 'one',
          metricIds: [ids[1], blank],
        );
        final none = await actions.createAction(
          name: 'none',
          metricIds: [blank, plain],
        );
        await actions.createAction(name: 'unlinked');

        await Future<void>.delayed(const Duration(milliseconds: 300));
        final m = container.read(actionDirectionIconsProvider);
        expect(m[many], 'A B C D +2');
        expect(m[one], 'B');
        expect(m.containsKey(none), isFalse);
        expect(m.length, 2);
      },
    );
  });

  group('direction emojis on the calendar', () {
    late AppDatabase db;

    DateTime at(int hour, [int minute = 0]) =>
        DateTime.fromMillisecondsSinceEpoch(
          localDayStart(DateTime.now().toUtc()).millisecondsSinceEpoch +
              Duration(hours: hour, minutes: minute).inMilliseconds,
          isUtc: true,
        );

    testWidgets('tall block and all-day chip show them, short block does not', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 1700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      late String tall, shortId, chip;
      await tester.runAsync(() async {
        final s = ActionService(db);
        tall = await s.createAction(
          name: 'Tall',
          startAt: at(10),
          endAt: at(12),
        );
        shortId = await s.createAction(
          name: 'Short',
          startAt: at(14),
          endAt: at(14, 10),
        );
        chip = await s.createAction(
          name: 'Chip',
          startAt: at(0),
          isAllDay: true,
        );
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            calendarVisibleHoursProvider.overrideWith((ref) => 24),
            calendarIconsProvider.overrideWith(() => CalendarIconsNotifier(true)),
            actionDirectionIconsProvider.overrideWith(
              (ref) => {
                tall: '\u{1F381} \u{26A1}',
                shortId: '\u{1F3E6}',
                chip: '\u{270D} \u{1F3E6}',
              },
            ),
          ],
          child: const MaterialApp(home: Scaffold(body: CalendarView())),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        find.descendant(
          of: find.byKey(ValueKey('event-$tall')),
          matching: find.text('\u{1F381} \u{26A1}'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(ValueKey('event-$shortId')),
          matching: find.text('\u{1F3E6}'),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byKey(ValueKey('allday-$chip')),
          matching: find.text('\u{270D} \u{1F3E6}'),
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 1));
    });

    testWidgets('badge on narrow lanes and ~30 px blocks, tooltips on hover', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 1700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      late String lane1, lane2, mid, tall, tiny, chip;
      await tester.runAsync(() async {
        final s = ActionService(db);
        lane1 = await s.createAction(
          name: 'Lane one with a long name',
          startAt: at(8),
          endAt: at(10),
        );
        lane2 = await s.createAction(
          name: 'Lane two with a long name',
          startAt: at(8),
          endAt: at(10),
        );
        mid = await s.createAction(
          name: 'Mid',
          startAt: at(12),
          endAt: at(12, 40),
        );
        tall = await s.createAction(
          name: 'Tall',
          startAt: at(15),
          endAt: at(18),
        );
        tiny = await s.createAction(
          name: 'Tiny',
          startAt: at(20),
          endAt: at(20, 10),
        );
        chip = await s.createAction(
          name: 'Chip',
          startAt: at(0),
          isAllDay: true,
        );
      });
      const two = '\u{1F381} \u{26A1}';
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            calendarVisibleHoursProvider.overrideWith((ref) => 24),
            calendarIconsProvider.overrideWith(() => CalendarIconsNotifier(true)),
            actionDirectionIconsProvider.overrideWith(
              (ref) => {
                lane1: two,
                lane2: two,
                mid: two,
                tall: two,
                tiny: two,
                chip: two,
              },
            ),
            actionDirectionNamesProvider.overrideWith(
              (ref) => {
                lane1: ['Gift', 'Zap'],
                lane2: ['Gift', 'Zap'],
                mid: ['Gift', 'Zap'],
                tall: ['Gift', 'Zap'],
                tiny: ['Gift', 'Zap'],
                chip: ['Gift', 'Zap'],
              },
            ),
          ],
          child: const MaterialApp(home: Scaffold(body: CalendarView())),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      Finder badge(String id) => find.descendant(
        of: find.byKey(ValueKey('event-$id')),
        matching: find.text(two),
      );
      expect(badge(lane1), findsOneWidget);
      expect(badge(lane2), findsOneWidget);
      expect(badge(mid), findsOneWidget);
      expect(badge(tall), findsOneWidget);
      expect(badge(tiny), findsNothing);

      // Tall block: the badge sits inside the block, not past its bottom.
      final blockRect = tester.getRect(find.byKey(ValueKey('event-$tall')));
      final badgeRect = tester.getRect(badge(tall));
      expect(badgeRect.bottom, lessThanOrEqualTo(blockRect.bottom - 2 + 0.5));
      expect(badgeRect.right, lessThanOrEqualTo(blockRect.right - 2 + 0.5));

      // Idle: no tooltips. Hover: one per direction, with the names.
      expect(find.text('Gift'), findsNothing);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      // One lightweight overlay tip for the emoji under the pointer: the
      // left end of the badge is the first emoji, the right end the second.
      final rect = tester.getRect(badge(tall));
      await mouse.moveTo(Offset(rect.left + 2, rect.center.dy));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Gift'), findsOneWidget);
      expect(find.text('Zap'), findsNothing);
      await mouse.moveTo(Offset(rect.right - 2, rect.center.dy));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Zap'), findsOneWidget);
      expect(find.text('Gift'), findsNothing);
      await mouse.moveTo(const Offset(5, 5));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Zap'), findsNothing);
      expect(find.text('Gift'), findsNothing);

      // The all-day chip's badge has tooltips too.
      final chipRect = tester.getRect(
        find.descendant(
          of: find.byKey(ValueKey('allday-$chip')),
          matching: find.text(two),
        ),
      );
      await mouse.moveTo(Offset(chipRect.left + 2, chipRect.center.dy));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Gift'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 1));
    });

    testWidgets('default is OFF; the toolbar switch shows then hides them', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 1700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      late String tall, chip;
      await tester.runAsync(() async {
        final s = ActionService(db);
        tall = await s.createAction(
          name: 'Tall',
          startAt: at(10),
          endAt: at(12),
        );
        chip = await s.createAction(
          name: 'Chip',
          startAt: at(0),
          isAllDay: true,
        );
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            calendarVisibleHoursProvider.overrideWith((ref) => 24),
            actionDirectionIconsProvider.overrideWith(
              (ref) => {tall: '\u{1F381}', chip: '\u{1F381}'},
            ),
          ],
          child: const MaterialApp(home: Scaffold(body: CalendarView())),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byKey(ValueKey('block-icons-$tall')), findsNothing);
      expect(find.text('\u{1F381}'), findsNothing);
      expect(find.byTooltip('Show growth direction icons'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('calendar-icons-toggle')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byKey(ValueKey('block-icons-$tall')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(ValueKey('allday-$chip')),
          matching: find.text('\u{1F381}'),
        ),
        findsOneWidget,
      );
      expect(find.byTooltip('Hide growth direction icons'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('calendar-icons-toggle')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byKey(ValueKey('block-icons-$tall')), findsNothing);
      expect(find.text('\u{1F381}'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 1));
    });

    testWidgets('all-day strip cells have no left border, chips no outline', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      late String chip;
      await tester.runAsync(() async {
        chip = await ActionService(db)
            .createAction(name: 'Chip', startAt: at(0), isAllDay: true);
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: const MaterialApp(home: Scaffold(body: CalendarView())),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final cell = tester.widget<Container>(
        find.byKey(const ValueKey('strip-cell-0')),
      );
      final deco = cell.decoration as BoxDecoration?;
      expect(deco?.border, isNull);
      final material = tester.widget<Material>(
        find
            .descendant(
              of: find.byKey(ValueKey('allday-$chip')),
              matching: find.byType(Material),
            )
            .first,
      );
      final shape = material.shape as RoundedRectangleBorder;
      expect(shape.side, BorderSide.none);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 1));
    });
  });
}

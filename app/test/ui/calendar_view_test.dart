import 'package:drift/drift.dart' show BooleanExpressionOperators;
import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/core/time_codec.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/postpone_rules.dart';
import 'package:livenow/ui/providers.dart';
import 'package:livenow/ui/views/calendar_layout.dart';
import 'package:livenow/ui/views/calendar_view.dart';

void main() {
  setUpAll(initPostponeTimeZoneData);

  late AppDatabase db;
  late ProviderContainer container;

  // Local (Europe/Istanbul, UTC+3) midnight today; events sit on today.
  DateTime at(int hour, [int minute = 0]) => DateTime.fromMillisecondsSinceEpoch(
    localDayStart(DateTime.now().toUtc()).millisecondsSinceEpoch +
        Duration(hours: hour, minutes: minute).inMilliseconds,
    isUtc: true,
  );

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: Scaffold(body: CalendarView())),
      ),
    );
    container = ProviderScope.containerOf(tester.element(find.byType(CalendarView)));
  }

  Future<String> create(
    WidgetTester tester, {
    String name = 'Alpha',
    DateTime? startAt,
    DateTime? endAt,
    bool isAllDay = false,
  }) async {
    return (await tester.runAsync(
      () => container
          .read(actionServiceProvider)
          .createAction(
            name: name,
            startAt: startAt,
            endAt: endAt,
            isAllDay: isAllDay,
          ),
    ))!;
  }

  /// Lets Drift's streams deliver, then rebuilds.
  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  Future<ActionRow> row(WidgetTester tester, String id) async =>
      (await tester.runAsync(
        () => (db.select(db.actionsTable)..where((t) => t.id.equals(id))).getSingle(),
      ))!;

  Future<void> useDays(WidgetTester tester, int n) async {
    await tester.tap(find.byTooltip('$n days'));
    await settle(tester);
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  /// Real mouse drag starting [localFrom] inside [block], moving by [delta].
  Future<void> dragBy(
    WidgetTester tester,
    Finder block,
    Offset localFrom,
    Offset delta,
  ) async {
    final g = await tester.startGesture(
      tester.getTopLeft(block) + localFrom,
      kind: PointerDeviceKind.mouse,
    );
    await g.moveBy(const Offset(0, 1));
    await tester.pump();
    await g.moveBy(delta - const Offset(0, 1));
    await tester.pump();
    await tester.runAsync(() async {
      await g.up();
      await Future<void>.delayed(const Duration(milliseconds: 250));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// Puts a mouse over [target] so its hover toolbar shows.
  Future<TestGesture> hover(WidgetTester tester, Finder target) async {
    final m = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await m.addPointer(location: const Offset(1, 1));
    addTearDown(m.removePointer);
    await m.moveTo(tester.getCenter(target));
    await tester.pump();
    return m;
  }

  testWidgets('day-count selector renders 2..7 columns', (tester) async {
    await pump(tester);
    await settle(tester);
    int columns() => find
        .byWidgetPredicate(
          (w) => w.key is ValueKey && '${(w.key as ValueKey).value}'.startsWith('day-header-'),
        )
        .evaluate()
        .length;
    expect(columns(), 7);
    for (var n = 2; n <= 7; n++) {
      await tester.tap(find.byTooltip('$n days'));
      await tester.pump();
      expect(columns(), n, reason: '$n days');
    }
    await unmount(tester);
  });

  testWidgets('timed event shows name and duration', (tester) async {
    await pump(tester);
    await create(tester, startAt: at(10), endAt: at(11, 30));
    await useDays(tester, 3);
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('1 hour 30 min'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('body drag moves the event, snapped to 10 minutes', (tester) async {
    await pump(tester);
    final id = await create(tester, startAt: at(10), endAt: at(11));
    await useDays(tester, 3);
    // 17 px = 21.25 min -> snaps to 20.
    await dragBy(tester, find.byKey(ValueKey('event-$id')), const Offset(30, 24), const Offset(0, 17));
    final r = await row(tester, id);
    expect(dateTimeFromDb(r.startAt), at(10, 20));
    expect(dateTimeFromDb(r.endAt), at(11, 20));
    await unmount(tester);
  });

  testWidgets('bottom handle changes the duration in 10 min steps', (tester) async {
    await pump(tester);
    final id = await create(tester, startAt: at(10), endAt: at(11));
    await useDays(tester, 3);
    final block = find.byKey(ValueKey('event-$id'));
    // 16 px = 20 min.
    await dragBy(tester, block, const Offset(30, 46), const Offset(0, 16));
    var r = await row(tester, id);
    expect(dateTimeFromDb(r.startAt), at(10));
    expect(dateTimeFromDb(r.endAt), at(11, 20));

    // Dragging far up clamps to the 10 min minimum.
    await dragBy(tester, block, Offset(30, tester.getSize(block).height - 2), const Offset(0, -400));
    r = await row(tester, id);
    expect(dateTimeFromDb(r.startAt), at(10));
    expect(dateTimeFromDb(r.endAt), at(10, 10));
    await unmount(tester);
  });

  testWidgets('top handle changes the start', (tester) async {
    await pump(tester);
    final id = await create(tester, startAt: at(10), endAt: at(11));
    await useDays(tester, 3);
    await dragBy(tester, find.byKey(ValueKey('event-$id')), const Offset(30, 2), const Offset(0, 16));
    final r = await row(tester, id);
    expect(dateTimeFromDb(r.startAt), at(10, 20));
    expect(dateTimeFromDb(r.endAt), at(11));
    await unmount(tester);
  });

  testWidgets('sideways drag moves the event a whole day', (tester) async {
    await pump(tester);
    final id = await create(tester, startAt: at(10), endAt: at(11));
    await useDays(tester, 3);
    final dayW = (1400 - 56) / 3;
    await dragBy(tester, find.byKey(ValueKey('event-$id')), const Offset(30, 24), Offset(dayW + 10, 0));
    final r = await row(tester, id);
    expect(dateTimeFromDb(r.startAt), at(10).add(const Duration(days: 1)));
    expect(dateTimeFromDb(r.endAt), at(11).add(const Duration(days: 1)));
    await unmount(tester);
  });

  testWidgets('a ghost shows during the drag and Undo restores afterwards', (tester) async {
    await pump(tester);
    final id = await create(tester, startAt: at(10), endAt: at(11));
    await useDays(tester, 3);
    final block = find.byKey(ValueKey('event-$id'));

    final g = await tester.startGesture(
      tester.getTopLeft(block) + const Offset(30, 24),
      kind: PointerDeviceKind.mouse,
    );
    await g.moveBy(const Offset(0, 40));
    await tester.pump();
    expect(find.byKey(const ValueKey('drag-ghost')), findsOneWidget);
    await tester.runAsync(() async {
      await g.up();
      await Future<void>.delayed(const Duration(milliseconds: 250));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('drag-ghost')), findsNothing);

    expect(dateTimeFromDb((await row(tester, id)).startAt), at(10, 50));
    expect(find.text('Moved'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.text('Undo'));
      await Future<void>.delayed(const Duration(milliseconds: 250));
    });
    final r = await row(tester, id);
    expect(dateTimeFromDb(r.startAt), at(10));
    expect(dateTimeFromDb(r.endAt), at(11));

    await tester.pump(const Duration(seconds: 1));
    await unmount(tester);
  });

  testWidgets('all-day action shows in the strip, not the grid', (tester) async {
    await pump(tester);
    final id = await create(tester, name: 'Holiday', startAt: at(0), isAllDay: true);
    await useDays(tester, 3);
    expect(find.byKey(ValueKey('allday-$id')), findsOneWidget);
    expect(find.text('Holiday'), findsOneWidget);
    expect(find.byKey(ValueKey('event-$id')), findsNothing);
    await unmount(tester);
  });

  group('hover toolbar', () {
    testWidgets('Start marks the action running', (tester) async {
      await pump(tester);
      final id = await create(tester, startAt: at(10), endAt: at(11));
      await useDays(tester, 3);
      await hover(tester, find.byKey(ValueKey('event-$id')));
      expect(find.byTooltip('Start'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('Start'));
        await Future<void>.delayed(const Duration(milliseconds: 250));
      });
      final occ = await tester.runAsync(
        () => (db.select(db.actionOccurrencesTable)
              ..where((t) => t.actionId.equals(id) & t.finishedAt.isNull()))
            .get(),
      );
      expect(occ, hasLength(1));
      await tester.pump(const Duration(seconds: 1));
      await unmount(tester);
    });

    testWidgets('Finish sets done', (tester) async {
      await pump(tester);
      final id = await create(tester, startAt: at(10), endAt: at(11));
      await useDays(tester, 3);
      await hover(tester, find.byKey(ValueKey('event-$id')));
      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('Finish'));
        await Future<void>.delayed(const Duration(milliseconds: 250));
      });
      expect((await row(tester, id)).done, isTrue);
      await tester.pump(const Duration(seconds: 1));
      await unmount(tester);
    });

    testWidgets('+7 days postpones a week, also on an all-day chip', (tester) async {
      await pump(tester);
      final id = await create(tester, startAt: at(10), endAt: at(11));
      final allDay = await create(tester, name: 'Holiday', startAt: at(0), isAllDay: true);
      await useDays(tester, 3);

      final m = await hover(tester, find.byKey(ValueKey('event-$id')));
      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('Postpone +7 days'));
        await Future<void>.delayed(const Duration(milliseconds: 250));
      });
      final limit = DateTime.now().toUtc().add(const Duration(days: 6));
      expect(dateTimeFromDb((await row(tester, id)).startAt)!.isAfter(limit), isTrue);

      await tester.pump(const Duration(seconds: 1));
      await settle(tester);
      await m.moveTo(tester.getCenter(find.byKey(ValueKey('allday-$allDay'))));
      await tester.pump();
      expect(find.byTooltip('Postpone +7 days'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('toolbar stays clickable for a 10-minute (8 px) block', (tester) async {
      await pump(tester);
      final id = await create(tester, startAt: at(10), endAt: at(10, 10));
      await useDays(tester, 3);
      final block = find.byKey(ValueKey('event-$id'));
      expect(tester.getSize(block).height, closeTo(8, 0.01));
      final m = await hover(tester, block);

      // Move from the block onto the toolbar (above its top-right corner).
      final tool = find.byTooltip('Finish');
      expect(tool, findsOneWidget);
      await m.moveTo(tester.getCenter(tool));
      await tester.pump();
      expect(find.byTooltip('Finish'), findsOneWidget);

      await tester.runAsync(() async {
        await tester.tap(tool);
        await Future<void>.delayed(const Duration(milliseconds: 250));
      });
      expect((await row(tester, id)).done, isTrue);
      await tester.pump(const Duration(seconds: 1));
      await unmount(tester);
    });
  });
}

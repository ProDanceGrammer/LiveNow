import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/data/queries.dart';
import 'package:livenow/domain/postpone_rules.dart';
import 'package:livenow/ui/dialog_stack.dart';
import 'package:livenow/ui/providers.dart';
import 'package:livenow/ui/time_format.dart';
import 'package:livenow/ui/widgets/action_card.dart';
import 'package:livenow/ui/widgets/action_time_label.dart';
import 'package:livenow/ui/widgets/date_time_field.dart';

// Europe/Istanbul is UTC+3 all year, so 11:30Z reads 14:30.
void main() {
  setUpAll(initPostponeTimeZoneData);

  late AppDatabase db;
  late String actionId;

  Future<void> pumpCard(
    WidgetTester tester, {
    required DateTime start,
    DateTime? end,
    bool isAllDay = false,
  }) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(resetStackedDialogsForTest);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    late ActionListItem item;
    await tester.runAsync(() async {
      actionId =
          await ProviderContainer(
                overrides: [databaseProvider.overrideWithValue(db)],
              )
              .read(actionServiceProvider)
              .createAction(
                name: 'Read a Bible',
                startAt: start,
                endAt: end,
                isAllDay: isAllDay,
              );
      item = ActionListItem.fromRow(
        await (db.select(
          db.actionsTable,
        )..where((t) => t.id.equals(actionId))).getSingle(),
      );
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          home: Scaffold(body: ActionCard(action: item)),
        ),
      ),
    );
  }

  Future<ActionRow> row(WidgetTester tester) async => (await tester.runAsync(
    () => (db.select(
      db.actionsTable,
    )..where((t) => t.id.equals(actionId))).getSingle(),
  ))!;

  Future<void> openDialog(WidgetTester tester) async {
    await tester.tap(find.byType(ActionTimeLabel));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  String seg(WidgetTester tester, String key) => tester
      .widget<Text>(
        find.descendant(
          of: find.byKey(ValueKey(key)),
          matching: find.byType(Text),
        ),
      )
      .data!;

  /// Segments whose container is highlighted (the cursor).
  List<String> cursor(WidgetTester tester) {
    final out = <String>[];
    for (final row in ['start', 'end']) {
      for (final u in ['hour', 'minute', 'day', 'month', 'year']) {
        final f = find.byKey(ValueKey('time-$row-$u'));
        if (f.evaluate().isEmpty) continue;
        final d = tester.widget<Container>(f).decoration as BoxDecoration;
        if (d.color != null) out.add('$row-$u');
      }
    }
    return out;
  }

  Future<void> ctrl(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
  }

  Future<void> key(WidgetTester tester, LogicalKeyboardKey k) async {
    await tester.sendKeyEvent(k);
    await tester.pump();
  }

  Future<void> afterWrite(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 250)),
    );
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  final start = DateTime.utc(2026, 10, 2, 11, 30); // 14:30
  final end = DateTime.utc(2026, 10, 2, 12, 30); // 15:30

  testWidgets('opens on the start minutes with both rows filled in', (
    tester,
  ) async {
    await pumpCard(tester, start: start, end: end);
    await openDialog(tester);

    expect(cursor(tester), ['start-minute']);
    expect(seg(tester, 'time-start-hour'), '14');
    expect(seg(tester, 'time-start-minute'), '30');
    expect(seg(tester, 'time-start-day'), '02');
    expect(seg(tester, 'time-start-month'), '10');
    expect(seg(tester, 'time-start-year'), '2026');
    expect(seg(tester, 'time-end-hour'), '15');
    await key(tester, LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(AlertDialog), findsNothing);
    await unmount(tester);
  });

  testWidgets('Ctrl+Up carries 59 minutes into the next hour', (tester) async {
    await pumpCard(tester, start: DateTime.utc(2026, 10, 2, 11, 59), end: end);
    await openDialog(tester);
    await ctrl(tester, LogicalKeyboardKey.arrowUp);
    expect(seg(tester, 'time-start-hour'), '15');
    expect(seg(tester, 'time-start-minute'), '00');
    await ctrl(tester, LogicalKeyboardKey.arrowDown);
    expect(seg(tester, 'time-start-hour'), '14');
    expect(seg(tester, 'time-start-minute'), '59');
    await key(tester, LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 400));
    await unmount(tester);
  });

  testWidgets('arrows move the cursor, plain Down/Up switch rows', (
    tester,
  ) async {
    await pumpCard(tester, start: start, end: end);
    await openDialog(tester);

    await key(tester, LogicalKeyboardKey.arrowLeft);
    expect(cursor(tester), ['start-hour']);
    await key(tester, LogicalKeyboardKey.arrowLeft);
    expect(cursor(tester), ['start-hour']);
    for (final expected in [
      'start-minute',
      'start-day',
      'start-month',
      'start-year',
    ]) {
      await key(tester, LogicalKeyboardKey.arrowRight);
      expect(cursor(tester), [expected]);
    }

    // Down goes to the END row, same segment; fresh dialog -> minutes.
    await key(tester, LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 400));
    await openDialog(tester);
    await key(tester, LogicalKeyboardKey.arrowDown);
    expect(cursor(tester), ['end-minute']);
    await ctrl(tester, LogicalKeyboardKey.arrowUp);
    expect(seg(tester, 'time-end-minute'), '31');
    expect(seg(tester, 'time-start-minute'), '30');
    await key(tester, LogicalKeyboardKey.arrowUp);
    expect(cursor(tester), ['start-minute']);
    await key(tester, LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 400));
    await unmount(tester);
  });

  testWidgets('typed digits replace the segment and clamp', (tester) async {
    await pumpCard(tester, start: start, end: end);
    await openDialog(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit4);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit5);
    await tester.pump();
    expect(seg(tester, 'time-start-minute'), '45');
    await tester.sendKeyEvent(LogicalKeyboardKey.digit9);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit9);
    await tester.pump();
    expect(seg(tester, 'time-start-minute'), '59');
    await key(tester, LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 400));
    await unmount(tester);
  });

  testWidgets('end before start shows a message and blocks Enter', (
    tester,
  ) async {
    await pumpCard(tester, start: start, end: start);
    await openDialog(tester);
    // Moving the START now carries the end along, so the error needs the END
    // itself to go before the start.
    await key(tester, LogicalKeyboardKey.arrowDown);
    await ctrl(tester, LogicalKeyboardKey.arrowDown);
    expect(find.byKey(const ValueKey('time-error')), findsOneWidget);
    await key(tester, LogicalKeyboardKey.enter);
    expect(find.byType(AlertDialog), findsOneWidget);
    await ctrl(tester, LogicalKeyboardKey.arrowUp);
    expect(find.byKey(const ValueKey('time-error')), findsNothing);
    await key(tester, LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 400));
    await unmount(tester);
  });

  testWidgets('Enter saves through the undo helper; Undo restores', (
    tester,
  ) async {
    await pumpCard(tester, start: start, end: end);
    await openDialog(tester);
    // Start 14:31: the end follows (15:31), keeping the length.
    await ctrl(tester, LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await afterWrite(tester);

    expect(find.byType(AlertDialog), findsNothing);
    final saved = await row(tester);
    expect(DateTime.parse(saved.startAt!), DateTime.utc(2026, 10, 2, 11, 31));
    expect(DateTime.parse(saved.endAt!), DateTime.utc(2026, 10, 2, 12, 31));
    expect(find.text('Time changed'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.text('Undo'));
      await Future<void>.delayed(const Duration(milliseconds: 250));
    });
    final back = await row(tester);
    expect(DateTime.parse(back.startAt!), start);
    expect(DateTime.parse(back.endAt!), end);
    await unmount(tester);
  });

  testWidgets('all-day actions only edit the date', (tester) async {
    await pumpCard(
      tester,
      start: DateTime.utc(2026, 10, 1, 21), // 2 Oct 00:00 Istanbul
      isAllDay: true,
    );
    await openDialog(tester);
    expect(find.byKey(const ValueKey('time-start-hour')), findsNothing);
    expect(cursor(tester), ['start-day']);
    await ctrl(tester, LogicalKeyboardKey.arrowUp);
    expect(seg(tester, 'time-start-day'), '03');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await afterWrite(tester);
    expect(
      DateTime.parse((await row(tester)).startAt!),
      DateTime.utc(2026, 10, 2, 21),
    );
    await unmount(tester);
  });

  testWidgets('DateTimeField returns the value without a DB write', (
    tester,
  ) async {
    addTearDown(resetStackedDialogsForTest);
    // The keyboard editor is the wide-layout one (a phone gets the wheel).
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    DateTime? got = start;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => DateTimeField(
              label: 'Scheduled start',
              value: got,
              includeTime: true,
              onChanged: (v) => setState(() => got = v),
            ),
          ),
        ),
      ),
    );
    expect(find.text('Scheduled start: 02-10-2026 14:30'), findsOneWidget);
    expect(find.text('Pick'), findsNothing);
    await tester.tap(find.text('Scheduled start: 02-10-2026 14:30'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('time-end-minute')), findsNothing);
    await ctrl(tester, LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(got, DateTime.utc(2026, 10, 2, 11, 31));
    expect(find.text('Scheduled start: 02-10-2026 14:31'), findsOneWidget);
  });

  test('time_format converts between UTC and Istanbul wall time', () {
    expect(wallFromUtc(start), DateTime.utc(2026, 10, 2, 14, 30));
    expect(utcFromWall(DateTime.utc(2026, 10, 2, 14, 30)), start);
    expect(formatUtcDateTime(start), '02-10-2026 14:30');
    expect(formatUtcDateTime(start, includeTime: false), '02-10-2026');
    expect(formatTimeRange(start, end, nowUtc: start), '14:30 → 15:30');
    expect(
      formatTimeRange(start, end, nowUtc: DateTime.utc(2026, 10, 5)),
      '02-10-2026 14:30 → 15:30', // the same date is printed once
    );
    // Another day: both dates; today's start stays a bare time.
    expect(
      formatTimeRange(start, DateTime.utc(2026, 10, 3, 23), nowUtc: start),
      '14:30 → 04-10-2026 02:00',
    );
    expect(
      formatTimeRange(start, DateTime.utc(2026, 10, 3, 23),
          nowUtc: DateTime.utc(2026, 10, 5)),
      '02-10-2026 14:30 → 04-10-2026 02:00',
    );
  });

  test('formatShortSchedule: day first, same date printed once', () {
    String? f(DateTime? a, DateTime? b, {bool allDay = false}) =>
        formatShortSchedule(a, b, isAllDay: allDay);
    final s = DateTime.utc(2026, 10, 3, 10, 0); // 13:00
    final e = DateTime.utc(2026, 10, 3, 11, 40); // 14:40
    expect(f(s, e), '03-10-2026 13:00 → 14:40');
    expect(f(s, null), '03-10-2026 13:00');
    expect(f(s, e, allDay: true), '03-10-2026');
    expect(
      f(s, DateTime.utc(2026, 10, 4, 6)),
      '03-10-2026 13:00 → 04-10-2026 09:00',
    );
    expect(f(null, e), isNull);
  });
}

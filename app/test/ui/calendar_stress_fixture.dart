import 'dart:math';

import 'package:drift/drift.dart' show Value;
import 'package:livenow/core/time_codec.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/plan_rules.dart';
import 'package:livenow/domain/plan_service.dart';
import 'package:livenow/domain/action_service.dart';
import 'package:livenow/ui/views/calendar_layout.dart';

/// Monday (local midnight, as a UTC instant) of the week the calendar shows.
DateTime stressWeekStart() => calendarAnchorStart(DateTime.now().toUtc(), 7);

/// [perDay] timed actions for each of [days] days: deterministic
/// (`Random(seed)`), 5 min - 2 h long, starting anywhere in the day so that
/// together they cover 00:00-24:00 with plenty of overlap.
Future<List<String>> seedBusyWeek(
  AppDatabase db, {
  int days = 7,
  int perDay = 100,
  int seed = 7,
}) async {
  final rnd = Random(seed);
  final weekStart = stressWeekStart();
  final now = dateTimeToDb(DateTime.now())!;
  final ids = <String>[];
  final rows = <ActionsTableCompanion>[];
  for (var d = 0; d < days; d++) {
    final day = calendarAddDays(weekStart, d);
    for (var i = 0; i < perDay; i++) {
      final startMin = rnd.nextInt(24 * 60);
      final len = 5 + rnd.nextInt(116); // 5..120
      final start = day.add(Duration(minutes: startMin));
      final id = 'stress-$d-$i';
      ids.add(id);
      rows.add(
        ActionsTableCompanion.insert(
          id: id,
          name: 'Event $d/$i with a rather long name to wrap',
          startAt: Value(dateTimeToDb(start)),
          endAt: Value(dateTimeToDb(start.add(Duration(minutes: len)))),
          createdAt: now,
          updatedAt: now,
        ),
      );
    }
  }
  await db.batch((b) => b.insertAll(db.actionsTable, rows));
  return ids;
}

/// [count] events that all start at [hour]:[minute] of the first viewed day
/// (lane packing worst case); ends vary so they never nest trivially.
Future<List<String>> seedSameStart(
  AppDatabase db, {
  int count = 100,
  int hour = 10,
  int minute = 0,
}) async {
  final start = stressWeekStart().add(Duration(hours: hour, minutes: minute));
  final now = dateTimeToDb(DateTime.now())!;
  final ids = [for (var i = 0; i < count; i++) 'same-$i'];
  await db.batch(
    (b) => b.insertAll(db.actionsTable, [
      for (var i = 0; i < count; i++)
        ActionsTableCompanion.insert(
          id: ids[i],
          name: 'Same start $i',
          startAt: Value(dateTimeToDb(start)),
          endAt: Value(dateTimeToDb(start.add(Duration(minutes: 5 + i)))),
          createdAt: now,
          updatedAt: now,
        ),
    ]),
  );
  return ids;
}

/// [count] all-day actions on the first viewed day.
Future<List<String>> seedAllDay(AppDatabase db, {int count = 100}) async {
  final day = stressWeekStart();
  final now = dateTimeToDb(DateTime.now())!;
  final ids = [for (var i = 0; i < count; i++) 'allday-$i'];
  await db.batch(
    (b) => b.insertAll(db.actionsTable, [
      for (var i = 0; i < count; i++)
        ActionsTableCompanion.insert(
          id: ids[i],
          name: 'All-day item $i',
          startAt: Value(dateTimeToDb(day)),
          endAt: Value(dateTimeToDb(day.add(const Duration(days: 1)))),
          isAllDay: const Value(true),
          createdAt: now,
          updatedAt: now,
        ),
    ]),
  );
  return ids;
}

/// One daily plan item with [perDay] occurrences (5 min - 2 h, `Random(seed)`),
/// i.e. [perDay] ghost blocks on every visible day in planning mode.
Future<String> seedPlanGhosts(
  AppDatabase db, {
  int perDay = 100,
  int seed = 11,
}) {
  final rnd = Random(seed);
  final plans = PlanService(db, ActionService(db));
  return plans.saveItem(
    PlanItemInput(
      name: 'Ghost',
      kind: PlanKind.cycle,
      startDate: planDateOf(DateTime.now()).subtract(const Duration(days: 30)),
      cycle: CycleRule(
        cycleDays: 1,
        occurrences: [
          for (var i = 0; i < perDay; i++)
            CycleOccurrence(
              day: 0,
              startMin: rnd.nextInt(24 * 60 - 5),
              durationMin: 5 + rnd.nextInt(116),
            ),
        ],
      ),
    ),
  );
}

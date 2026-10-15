import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/action_service.dart';
import 'package:livenow/domain/plan_rules.dart';
import 'package:livenow/domain/plan_service.dart';
import 'package:livenow/domain/postpone_rules.dart';

/// "This weekday only": a change of one occurrence's time that reaches only the
/// weekdays of its date, by stretching the cycle to whole weeks.
void main() {
  setUpAll(initPostponeTimeZoneData);

  late AppDatabase db;
  late PlanService plans;

  setUp(() {
    db = AppDatabase.forTesting(
      NativeDatabase.memory(
        setup: (raw) => raw.execute('PRAGMA foreign_keys = ON;'),
      ),
    );
    plans = PlanService(db, ActionService(db));
  });
  tearDown(() => db.close());

  // Mon 19 Oct 2026 is the pattern start (a Monday).
  DateTime day(int d) => planDate(2026, 10, d);
  final now = DateTime.utc(2026, 10, 19, 5);

  Future<String> item({int cycleDays = 1, DateTime? start}) => plans.saveItem(
    PlanItemInput(
      name: 'Run',
      kind: PlanKind.cycle,
      startDate: start ?? day(19),
      cycle: CycleRule(
        cycleDays: cycleDays,
        occurrences: const [
          CycleOccurrence(day: 0, startMin: 9 * 60, durationMin: 30),
        ],
      ),
    ),
  );

  Future<List<PlanOccurrence>> week(String id, {int from = 19, int to = 25}) async {
    final data = plans.decode(
      (await plans.items()).firstWhere((r) => r.id == id),
    );
    final overrides = [
      for (final o in await db.select(db.planOverridesTable).get())
        plans.decodeOverride(o),
    ];
    return occurrencesInRange(data, day(from), day(to), overrides: overrides);
  }

  test('a daily item changes on that weekday only', () async {
    final id = await item();
    // Tuesday 20 Oct, 09:00 -> 10:00, "this weekday only".
    await plans.shiftWeekday(id, day(20), 0, startMin: 10 * 60, durationMin: 30);

    final data = plans.decode((await plans.items()).single);
    expect(data.cycle!.cycleDays, 7);
    expect(data.cycle!.occurrences, hasLength(7));
    expect(data.startDate, day(19)); // the start does not move

    for (final weeks in [0, 1, 2]) {
      final o = await week(id, from: 19 + 7 * weeks, to: 25 + 7 * weeks);
      expect(o, hasLength(7));
      for (final x in o) {
        // Tuesday is the 2nd day of each week.
        final tuesday = x.date.weekday == DateTime.tuesday;
        expect(x.startMin, tuesday ? 10 * 60 : 9 * 60, reason: '${x.date}');
      }
    }
  });

  test('already created actions keep their place: nothing is created twice', () async {
    final id = await item();
    final first = await plans.confirm(from: day(19), to: day(30), nowUtc: now);
    expect(first.createdIds, isNotEmpty);

    await plans.shiftWeekday(id, day(21), 0, startMin: 11 * 60, durationMin: 30);
    final again = await plans.confirm(from: day(19), to: day(30), nowUtc: now);
    // Same dates, same occurrence numbers (the keys were renumbered).
    expect(again.createdIds, isEmpty);
    expect(
      (await db.select(db.actionsTable).get()).length,
      first.createdIds.length,
    );
  });

  test('single-day edits stay on their own day', () async {
    final id = await item();
    await plans.setOverride(
      itemId: id,
      date: day(22), // Thursday
      index: 0,
      skipped: true,
    );
    await plans.shiftWeekday(id, day(20), 0, startMin: 10 * 60, durationMin: 30);
    final o = await week(id);
    expect(o.where((x) => x.date == day(22)), isEmpty, reason: 'still skipped');
    expect(o, hasLength(6));
    expect(o.firstWhere((x) => x.date == day(20)).startMin, 10 * 60);
  });

  test('a 3-day cycle is stretched to 21 days, one row of seven changes', () async {
    final id = await item(cycleDays: 3);
    await plans.shiftWeekday(id, day(19), 0, startMin: 8 * 60, durationMin: 30);
    final data = plans.decode((await plans.items()).single);
    expect(data.cycle!.cycleDays, 21);
    expect(data.cycle!.occurrences, hasLength(7));
    expect(
      data.cycle!.occurrences.where((o) => o.startMin == 8 * 60),
      hasLength(1),
    );
    // Over 3 weeks the days are the same as before: one in three.
    final o = await week(id, from: 19, to: 39);
    expect(o, hasLength(7));
    expect(o.where((x) => x.startMin == 8 * 60), hasLength(1));
    expect(o.first.date, day(19));
    expect(o.first.startMin, 8 * 60);
  });

  test('a cycle of whole weeks is just the whole pattern', () async {
    final id = await item(cycleDays: 7);
    await plans.shiftWeekday(id, day(19), 0, startMin: 8 * 60, durationMin: 45);
    final data = plans.decode((await plans.items()).single);
    expect(data.cycle!.cycleDays, 7);
    expect(data.cycle!.occurrences.single.startMin, 8 * 60);
    expect(data.cycle!.occurrences.single.durationMin, 45);
  });
}

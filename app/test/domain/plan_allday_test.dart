import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/core/ids.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/action_service.dart';
import 'package:livenow/domain/plan_rules.dart';
import 'package:livenow/domain/plan_service.dart';
import 'package:livenow/domain/postpone_rules.dart';

/// All-day rows of a plan item: the rule, the generated occurrences, the real
/// all-day actions a confirmation makes, and Previous / Next being left out.
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

  // Mon 19 Oct 2026 08:00 local (05:00Z).
  final now = DateTime.utc(2026, 10, 19, 5);
  DateTime day(int d) => planDate(2026, 10, d);

  Future<String> restDay({String? templateId, PlanExtras? extras}) =>
      plans.saveItem(
        PlanItemInput(
          name: 'Rest day',
          templateId: templateId,
          kind: PlanKind.cycle,
          startDate: day(19),
          cycle: CycleRule(
            cycleDays: 7,
            occurrences: [
              CycleOccurrence(
                day: 0, // Monday = today
                startMin: 9 * 60, // ignored for an all-day row
                allDay: true,
                extras: extras ?? const PlanExtras(),
              ),
              const CycleOccurrence(day: 2, startMin: 18 * 60, durationMin: 60),
            ],
          ),
        ),
      );

  test('the rule keeps the flag and old rules are not all-day', () {
    const o = CycleOccurrence(day: 1, startMin: 60, allDay: true);
    expect(CycleOccurrence.fromJson(o.toJson()).allDay, isTrue);
    expect(CycleOccurrence.fromJson({'day': 1, 'startMin': 60}).allDay, isFalse);
    const m = MonthlyRule(allDay: true);
    expect(MonthlyRule.fromJson(m.toJson()).allDay, isTrue);
  });

  test('an all-day occurrence sits at its day midnight with no length', () {
    final item = PlanItemData(
      id: 'i',
      name: 'Rest day',
      kind: PlanKind.cycle,
      startDate: day(19),
      cycle: const CycleRule(
        cycleDays: 7,
        occurrences: [CycleOccurrence(day: 0, startMin: 600, allDay: true)],
      ),
    );
    final o = occurrencesInRange(item, day(19), day(25)).single;
    expect(o.allDay, isTrue);
    expect(o.startMin, 0);
    expect(o.durationMin, 0);
    // Istanbul midnight of 19 Oct = 21:00Z the day before.
    expect(o.startUtc, DateTime.utc(2026, 10, 18, 21));
    expect(o.endUtc, o.startUtc);
  });

  test('describePlan says all day', () {
    final item = PlanItemData(
      id: 'i',
      name: 'x',
      kind: PlanKind.cycle,
      startDate: day(19),
      cycle: const CycleRule(
        cycleDays: 7,
        occurrences: [
          CycleOccurrence(day: 6, startMin: 600, allDay: true),
          CycleOccurrence(day: 0, startMin: 540),
        ],
      ),
    );
    expect(describePlan(item), 'Weekly: Mon 09:00, Sun all day');
  });

  test('confirm creates a real ALL-DAY action, today included', () async {
    final id = await restDay();
    final r = await plans.confirm(from: day(19), to: day(21), nowUtc: now);
    expect(r.createdIds, hasLength(2)); // Monday (all-day, today) + Wednesday
    final rows = await db.select(db.actionsTable).get();
    final rest = rows.firstWhere((a) => a.isAllDay);
    expect(rest.name, 'Rest day');
    expect(rest.endAt, isNull);
    expect(rest.planItemId, id);
    expect(rest.startAt, isNotNull);
    expect(rows.where((a) => !a.isAllDay), hasLength(1));
    // Confirming again creates nothing new.
    final again = await plans.confirm(from: day(19), to: day(21), nowUtc: now);
    expect(again.createdIds, isEmpty);
  });

  test('a timed template still gives an all-day action for an all-day row', () async {
    final t = newId();
    await db
        .into(db.actionTemplatesTable)
        .insert(
          ActionTemplatesTableCompanion.insert(
            id: t,
            name: 'Rest',
            payload: jsonEncode({'name': 'Rest', 'estimatedMinutes': 30}),
          ),
        );
    await restDay(templateId: t);
    await plans.confirm(from: day(19), to: day(19), nowUtc: now);
    final a = (await db.select(db.actionsTable).get()).single;
    expect(a.isAllDay, isTrue);
    expect(a.endAt, isNull);
    expect(a.name, 'Rest');
  });

  test('Previous / Next of an all-day row are not created', () async {
    await restDay(
      extras: const PlanExtras(
        prev: [PlanCompanion(name: 'Before', minutes: 30)],
        next: [PlanCompanion(name: 'After', minutes: 30)],
      ),
    );
    final r = await plans.confirm(from: day(19), to: day(19), nowUtc: now);
    expect(r.createdIds, hasLength(1));
    expect(await db.select(db.actionDependenciesTable).get(), isEmpty);
  });

  test('removeFuture takes an untouched all-day action of today', () async {
    final id = await restDay();
    await plans.confirm(from: day(19), to: day(19), nowUtc: now);
    final undo = await plans.removeFuture(id, nowUtc: now);
    expect(undo!.count, 1);
  });
}

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/core/ids.dart';
import 'package:livenow/core/time_codec.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/action_service.dart';
import 'package:livenow/domain/plan_rules.dart';
import 'package:livenow/domain/plan_service.dart';
import 'package:livenow/domain/postpone_rules.dart';

/// Counts the SELECTs the database is asked for.
class _CountSelects extends QueryInterceptor {
  int selects = 0;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    selects++;
    return executor.runSelect(statement, args);
  }
}

/// Planning mode used to read the whole last-30-days history once PER plan item
/// (to find the template's average length); it is one read for all items now.
void main() {
  setUpAll(initPostponeTimeZoneData);

  late _CountSelects counter;
  late AppDatabase db;

  setUp(() {
    counter = _CountSelects();
    db = AppDatabase.forTesting(NativeDatabase.memory().interceptWith(counter));
  });
  tearDown(() => db.close());

  test('40 template plan items over 3000 finished actions: bounded work', () async {
    final actions = ActionService(db);
    final plans = PlanService(db, actions);
    final today = planDateOf(DateTime.now());

    final end = DateTime.now().toUtc().subtract(const Duration(days: 1));
    await db.batch((b) {
      for (var i = 0; i < 3000; i++) {
        final e = end.subtract(Duration(minutes: i));
        final s = e.subtract(const Duration(minutes: 25));
        b.insert(
          db.actionsTable,
          ActionsTableCompanion.insert(
            id: newId(),
            name: 'Task ${i % 80}',
            createdAt: dateTimeToDb(s)!,
            updatedAt: dateTimeToDb(e)!,
            done: const Value(true),
            startAt: Value(dateTimeToDb(s)),
            endAt: Value(dateTimeToDb(e)),
            completedAt: Value(dateTimeToDb(e)),
          ),
        );
      }
    });
    for (var i = 0; i < 40; i++) {
      final templateId = newId();
      await db
          .into(db.actionTemplatesTable)
          .insert(
            ActionTemplatesTableCompanion.insert(
              id: templateId,
              name: 'Task $i',
              payload: jsonEncode({'name': 'Task $i', 'estimatedMinutes': 45}),
            ),
          );
      await plans.saveItem(
        PlanItemInput(
          name: 'Plan $i',
          templateId: templateId,
          kind: PlanKind.cycle,
          startDate: today.subtract(const Duration(days: 30)),
          cycle: CycleRule(
            cycleDays: 1,
            occurrences: [CycleOccurrence(day: 0, startMin: 6 * 60 + i * 10)],
          ),
        ),
      );
    }

    counter.selects = 0;
    final watch = Stopwatch()..start();
    final out = await plans.occurrences(
      today.subtract(const Duration(days: 14)),
      today.add(const Duration(days: 21)),
    );
    watch.stop();

    // 40 items x 36 days.
    expect(out, hasLength(40 * 36));
    // The average of finished runs wins over the manual 45 minutes.
    expect(out.first.durationMin, 25);
    // items + overrides + templates + countable activities + finished actions:
    // a handful of reads, not two per item.
    expect(counter.selects, lessThan(10));
    expect(watch.elapsed, lessThan(const Duration(seconds: 3)));
  });
}

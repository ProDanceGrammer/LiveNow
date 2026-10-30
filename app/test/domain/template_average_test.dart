import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/core/ids.dart';
import 'package:livenow/core/time_codec.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/action_service.dart';
import 'package:livenow/domain/postpone_rules.dart';

void main() {
  late AppDatabase db;
  late ActionService service;

  setUpAll(initPostponeTimeZoneData);
  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    service = ActionService(db);
  });
  tearDown(() => db.close());

  /// A finished run of [minutes] that ended [daysAgo] days ago.
  Future<void> run(
    String name,
    int minutes, {
    int daysAgo = 1,
    String? activityId,
  }) async {
    final end = DateTime.now().toUtc().subtract(Duration(days: daysAgo));
    final start = end.subtract(Duration(minutes: minutes));
    await db
        .into(db.actionsTable)
        .insert(
          ActionsTableCompanion.insert(
            id: newId(),
            name: name,
            createdAt: dateTimeToDb(start)!,
            updatedAt: dateTimeToDb(end)!,
            done: const Value(true),
            startAt: Value(dateTimeToDb(start)),
            endAt: Value(dateTimeToDb(end)),
            completedAt: Value(dateTimeToDb(end)),
            countableActivityId: Value(activityId),
          ),
        );
  }

  Future<String> template(Map<String, dynamic> payload) async {
    final id = newId();
    await db
        .into(db.actionTemplatesTable)
        .insert(
          ActionTemplatesTableCompanion.insert(
            id: id,
            name: payload['name'] as String,
            payload: jsonEncode(payload),
          ),
        );
    return id;
  }

  Future<Duration> createdLength(String templateId) async {
    final id = await service.createFromTemplateStarted(templateId);
    final a = await (db.select(
      db.actionsTable,
    )..where((t) => t.id.equals(id))).getSingle();
    return dateTimeFromDb(a.endAt)!.difference(dateTimeFromDb(a.startAt)!);
  }

  test('average = mean of same-name runs, [#n] copies included, last 30 days',
      () async {
    await run('Read', 20);
    await run('[#2] Read', 40);
    await run('Read', 600, daysAgo: 45); // too old
    await run('Other', 90);
    expect(await service.templateAverage('Read'), const Duration(minutes: 30));
    expect(await service.templateAverage('Nothing'), isNull);
  });

  test('averagesByName: many names in one call, keyed by normalized name',
      () async {
    final activityId = await service.createCountableActivity('Study');
    await run('Read', 20);
    await run('[#2] Read', 40);
    await run('Chapter', 50, activityId: activityId);
    await run('Run', 90, daysAgo: 45); // too old
    final m = await service.averagesByName(['Read', 'Study', 'Run', 'None']);
    expect(m['read'], const Duration(minutes: 30));
    expect(m['study'], const Duration(minutes: 50));
    expect(m.containsKey('run'), isFalse);
    expect(m.containsKey('none'), isFalse);
    expect(await service.averagesByName(const []), isEmpty);
  });

  test('templateDurations answers many templates like templateDuration', () async {
    await run('Walk', 20);
    final avg = await template({'name': 'Walk', 'estimatedMinutes': 45});
    final manual = await template({
      'name': 'Swim',
      'estimatedMinutes': 45,
    });
    final off = await template({
      'name': 'Walk',
      'estimatedMinutes': 45,
      'useAverage': false,
    });
    final none = await template({'name': 'Nap'});
    final all = await service.templateDurations([avg, manual, off, none, 'missing']);
    expect(all[avg], const Duration(minutes: 20));
    expect(all[manual], const Duration(minutes: 45));
    expect(all[off], const Duration(minutes: 45));
    expect(all[none], const Duration(minutes: 60));
    expect(all.containsKey('missing'), isFalse);
    for (final id in [avg, manual, off, none]) {
      expect(await service.templateDuration(id), all[id]);
    }
  });

  test('runs linked to the same-name Countable Activity count too', () async {
    final activityId = await service.createCountableActivity('Read');
    await run('Read', 20);
    await run('Chapter study', 40, activityId: activityId);
    expect(await service.templateAverage('read'), const Duration(minutes: 30));
  });

  test('default (no flag) = on: the average wins, manual is the fallback',
      () async {
    await run('Walk', 20);
    final t = await template({'name': 'Walk', 'estimatedMinutes': 45});
    expect(await createdLength(t), const Duration(minutes: 20));

    final noRuns = await template({'name': 'Swim', 'estimatedMinutes': 45});
    expect(await createdLength(noRuns), const Duration(minutes: 45));
  });

  test('flag explicitly off: manual time wins, average is the fallback',
      () async {
    await run('Walk', 20);
    final manual = await template({
      'name': 'Walk',
      'estimatedMinutes': 45,
      'useAverage': false,
    });
    expect(await createdLength(manual), const Duration(minutes: 45));

    final noManual = await template({'name': 'Walk', 'useAverage': false});
    expect(await createdLength(noManual), const Duration(minutes: 20));
  });

  test('diaryBlocks of a template land on the created action', () async {
    final t = await template({
      'name': 'Diary',
      'estimatedMinutes': 30,
      'diaryBlocks': ' KBT, Home ',
    });
    final id = await service.createFromTemplateStarted(t);
    final a = await (db.select(
      db.actionsTable,
    )..where((r) => r.id.equals(id))).getSingle();
    expect(a.resultNote, 'KBT, Home');

    final plain = await template({'name': 'Plain'});
    final id2 = await service.createFromTemplate(plain);
    final b = await (db.select(
      db.actionsTable,
    )..where((r) => r.id.equals(id2))).getSingle();
    expect(b.resultNote, isNull);
  });
}

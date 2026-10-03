import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/actions_csv.dart';
import 'package:livenow/domain/growth_rules.dart';
import 'package:livenow/domain/metric_service.dart';
import 'package:livenow/domain/postpone_rules.dart';
import 'package:livenow/domain/template_import_service.dart';

// Representative rows copied from dev/data/actions/*_no_duplicates_activities.csv.
const _csv = '''
Name,Datetime,Next actions and time,Previous actions and time,Growth Direction
↗️ Занесення в Notion,03/10/2026 11:30 → 12:30,,,"Я багато виконую задачі, що стосуються систематизації"
😴 Сон,03/10/2026 23:00 → 04/10/2026 8:00,,,Я достатньо сплю
💧 Випити літр води,03/10/2026,,,Невідомий напрям
🍓 Базар,03/10/2026 17:00 → 19:01,,"🛍️ Зробити перед покупками October 3, 2026 4:45 PM → 4:59 PM",
↗️ Занесення в Notion,04/10/2026 9:00 → 9:30,,,
''';

void main() {
  setUpAll(initPostponeTimeZoneData);

  late AppDatabase db;
  late TemplateImportService service;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    service = TemplateImportService(db);
    final metrics = MetricService(db);
    await metrics.saveMetric(
      name: 'Я багато виконую задачі, що стосуються систематизації',
      kind: MetricKind.boolean,
    );
    await metrics.saveMetric(
      name: 'Я достатньо сплю',
      kind: MetricKind.boolean,
    );
  });

  tearDown(() => db.close());

  test(
    'parser reads an end that carries its own date (9 h across midnight)',
    () {
      final sleep = parseActionsCsv(_csv).actions
          .firstWhere((a) => a.name.contains('Сон'));
      expect(sleep.end!.difference(sleep.start!).inMinutes, 540);
    },
  );

  test(
    'creates templates only: durations, directions, no actions/links',
    () async {
      final r = await service.importCsv(_csv);
      expect(r.created, 4);
      expect(r.skipped, 1); // repeated name inside the file
      expect(r.linksIgnored, 1);
      expect(r.unmatchedDirections, ['Невідомий напрям']);

      final byName = {
        for (final t in await db.select(db.actionTemplatesTable).get())
          t.name: jsonDecode(t.payload) as Map<String, dynamic>,
      };
      expect(byName['↗️ Занесення в Notion']!['estimatedMinutes'], 60);
      expect(
        (byName['↗️ Занесення в Notion']!['metricIds'] as List),
        hasLength(1),
      );
      expect(byName['😴 Сон']!['estimatedMinutes'], 540);
      expect(byName['🍓 Базар']!['estimatedMinutes'], 121);
      final allDay = byName['💧 Випити літр води']!;
      expect(allDay['isAllDay'], isTrue);
      expect(allDay.containsKey('estimatedMinutes'), isFalse);
      expect(allDay['metricIds'], isEmpty);

      expect(await db.select(db.actionsTable).get(), isEmpty);
      expect(await db.select(db.actionMetricsTable).get(), isEmpty);
    },
  );

  test('re-import skips existing names', () async {
    await service.importCsv(_csv);
    final r = await service.importCsv(_csv);
    expect(r.created, 0);
    expect(r.skipped, 5);
    expect(await db.select(db.actionTemplatesTable).get(), hasLength(4));
  });
}

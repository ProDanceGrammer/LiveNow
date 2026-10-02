import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/action_import_service.dart';
import 'package:livenow/domain/growth_rules.dart';
import 'package:livenow/domain/metric_service.dart';
import 'package:livenow/domain/postpone_rules.dart';

const _csv = '''
Name,Datetime,Next actions and time,Previous actions and time,Growth Direction
🛍️ Зробити перед покупками,03/10/2026 16:45 → 16:59,"🍓 Базар October 3, 2026 5:00 PM → 7:01 PM",,"Я роблю багато, щоб мої очікування справджувались"
🍓 Базар,03/10/2026 17:00 → 19:01,,"🛍️ Зробити перед покупками October 3, 2026 4:45 PM → 4:59 PM,Давня задача July 5, 2026 11:45 PM → July 6, 2026 3:45 AM","Я регулярно перевіряю канали зв’язку зі мною,Невідомий напрям"
💧 Випити літр води,03/10/2026,,,
''';

void main() {
  setUpAll(initPostponeTimeZoneData);

  late AppDatabase db;
  late ActionImportService service;

  setUp(() async {
    db = AppDatabase.forTesting(
      NativeDatabase.memory(
        setup: (raw) => raw.execute('PRAGMA foreign_keys = ON;'),
      ),
    );
    service = ActionImportService(db);
    final metrics = MetricService(db);
    await metrics.saveMetric(
      name: 'Я роблю багато, щоб мої очікування справджувались',
      kind: MetricKind.boolean,
    );
    await metrics.saveMetric(
      name: "Я регулярно перевіряю канали зв'язку зі мною",
      kind: MetricKind.boolean,
    );
  });

  tearDown(() => db.close());

  test('creates actions, links directions, one edge from both cells', () async {
    final r = await service.importCsv(_csv);
    expect(r.created, 3);
    expect(r.skippedDuplicates, 0);
    expect(r.edgesCreated, 1);
    expect(r.unmatchedDirections, ['Невідомий напрям']);
    expect(r.unresolvedRefs, hasLength(1));
    expect(r.unresolvedRefs.single, contains('Давня задача'));
    expect(r.rejectedEdges, isEmpty);

    final actions = await db.select(db.actionsTable).get();
    final before = actions.firstWhere(
      (a) => a.name.contains('перед покупками'),
    );
    final bazaar = actions.firstWhere((a) => a.name.contains('Базар'));
    final water = actions.firstWhere((a) => a.name.contains('води'));
    expect(water.isAllDay, isTrue);
    expect(before.startAt, '2026-10-03T13:45:00.000000Z');

    final deps = await db.select(db.actionDependenciesTable).get();
    expect(deps.single.predecessorId, before.id);
    expect(deps.single.successorId, bazaar.id);

    final links = await db.select(db.actionMetricsTable).get();
    expect(links.where((l) => l.actionId == before.id), hasLength(1));
    expect(links.where((l) => l.actionId == bazaar.id), hasLength(1));
    expect(links.where((l) => l.actionId == water.id), isEmpty);
  });

  test('re-import is idempotent', () async {
    await service.importCsv(_csv);
    final r = await service.importCsv(_csv);
    expect(r.created, 0);
    expect(r.skippedDuplicates, 3);
    expect(r.edgesCreated, 0);
    expect(await db.select(db.actionsTable).get(), hasLength(3));
    expect(await db.select(db.actionDependenciesTable).get(), hasLength(1));
  });

  test('refs resolve to actions already in the database', () async {
    await service.importCsv(
      'Name,Datetime,Next actions and time,Previous actions and time,Growth Direction\n'
      '🍓 Базар,03/10/2026 17:00 → 19:01,,,\n',
    );
    final r = await service.importCsv(
      'Name,Datetime,Next actions and time,Previous actions and time,Growth Direction\n'
      '🛍️ Зробити,03/10/2026 16:45 → 16:59,"🍓 Базар October 3, 2026 5:00 PM → 7:01 PM",,\n',
    );
    expect(r.created, 1);
    expect(r.edgesCreated, 1);
    expect(r.unresolvedRefs, isEmpty);
  });

  test('a cyclic edge is reported, not fatal', () async {
    final r = await service.importCsv(
      'Name,Datetime,Next actions and time,Previous actions and time,Growth Direction\n'
      'A,03/10/2026 10:00 → 11:00,"B October 3, 2026 12:00 PM → 1:00 PM",,\n'
      'B,03/10/2026 12:00 → 13:00,"A October 3, 2026 10:00 AM → 11:00 AM",,\n',
    );
    expect(r.created, 2);
    expect(r.edgesCreated, 1);
    expect(r.rejectedEdges, ['B -> A']);
  });

  test('bad file changes nothing', () async {
    await expectLater(service.importCsv('Foo\nbar\n'), throwsFormatException);
    expect(await db.select(db.actionsTable).get(), isEmpty);
  });
}

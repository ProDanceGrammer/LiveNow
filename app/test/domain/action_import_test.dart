import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/action_import_service.dart';
import 'package:livenow/domain/action_service.dart';
import 'package:livenow/domain/actions_csv.dart';
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

  group('Done column (all-day actions)', () {
    const header =
        'Name,Datetime,Next actions and time,Previous actions and time,'
        'Growth Direction,Done\n';

    Future<Map<String, ActionRow>> actionsByName() async => {
      for (final a in await db.select(db.actionsTable).get()) a.name: a,
    };

    test('parseYesNo reads Yes/No in any case, anything else is null', () {
      expect(parseYesNo('Yes'), isTrue);
      expect(parseYesNo(' YES '), isTrue);
      expect(parseYesNo('No'), isFalse);
      expect(parseYesNo('no'), isFalse);
      expect(parseYesNo(''), isNull);
      expect(parseYesNo('maybe'), isNull);
    });

    test('the parser keeps Done per row; the header is case-insensitive', () {
      final parsed = parseActionsCsv(
        'Name,Datetime,done\nA,03/10/2026,Yes\nB,04/10/2026,No\nC,05/10/2026,\n',
      );
      expect(parsed.actions.map((a) => a.done), [true, false, null]);
      // No Done column at all: every row is null.
      expect(
        parseActionsCsv('Name,Datetime\nA,03/10/2026\n').actions.single.done,
        isNull,
      );
    });

    test(
      'marks all-day actions done, leaves timed ones to their end time',
      () async {
        final r = await service.importCsv(
          '${header}'
          '💧 Water,03/10/2026,,,,Yes\n'
          '🧹 Chores,04/10/2026,,,,No\n'
          'Timed,03/10/2026 10:00 → 11:00,,,,Yes\n'
          'No value,05/10/2026,,,,\n',
        );
        expect(r.created, 4);
        expect(r.doneApplied, 1); // only Water changed from the default
        expect(r.doneIgnoredTimed, 1);

        final rows = await actionsByName();
        expect(rows['💧 Water']!.done, isTrue);
        expect(rows['💧 Water']!.completedAt, isNotNull);
        expect(rows['🧹 Chores']!.done, isFalse);
        expect(rows['No value']!.done, isFalse);
        expect(rows['Timed']!.done, isFalse); // derived, not the manual flag
      },
    );

    test('a re-import updates the flag of existing all-day actions', () async {
      await service.importCsv(
        '${header}💧 Water,03/10/2026,,,,Yes\n🧹 Chores,04/10/2026,,,,No\n',
      );
      final r = await service.importCsv(
        '${header}💧 Water,03/10/2026,,,,No\n🧹 Chores,04/10/2026,,,,Yes\n',
      );
      expect(r.created, 0);
      expect(r.skippedDuplicates, 2);
      expect(r.doneApplied, 2);

      final rows = await actionsByName();
      expect(rows['💧 Water']!.done, isFalse);
      expect(rows['💧 Water']!.completedAt, isNull);
      expect(rows['🧹 Chores']!.done, isTrue);

      // Same values again: nothing to change.
      final again = await service.importCsv(
        '${header}💧 Water,03/10/2026,,,,No\n🧹 Chores,04/10/2026,,,,Yes\n',
      );
      expect(again.doneApplied, 0);
    });

    test('a file without the column never touches the done flag', () async {
      await service.importCsv('Name,Datetime\n💧 Water,03/10/2026\n');
      final id = (await actionsByName())['💧 Water']!.id;
      await ActionService(db).toggleDone(id);

      final r = await service.importCsv('Name,Datetime\n💧 Water,03/10/2026\n');
      expect(r.doneApplied, 0);
      expect((await actionsByName())['💧 Water']!.done, isTrue);
    });
  });
}

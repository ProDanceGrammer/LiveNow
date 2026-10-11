import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/core/time_codec.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/data/queries.dart';

Future<void> _insert(
  AppDatabase db,
  String id,
  String name, {
  DateTime? start,
  DateTime? end,
  bool allDay = false,
}) => db
    .into(db.actionsTable)
    .insert(
      ActionsTableCompanion.insert(
        id: id,
        name: name,
        startAt: Value(start == null ? null : dateTimeToDb(start)),
        endAt: Value(end == null ? null : dateTimeToDb(end)),
        isAllDay: Value(allDay),
        createdAt: 't',
        updatedAt: 't',
      ),
    );

void main() {
  late AppDatabase db;
  late ViewQueries q;
  final now = DateTime.utc(2026, 10, 11, 12);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    q = ViewQueries(db);
    await _insert(
      db,
      'a',
      'Помити посуд',
      start: now.add(const Duration(hours: 1)),
      end: now.add(const Duration(hours: 2)),
    );
    await _insert(
      db,
      'b',
      'Читати Біблію',
      start: now.subtract(const Duration(hours: 3)),
      end: now.subtract(const Duration(hours: 2)),
    );
    await _insert(
      db,
      'c',
      'Помити авто',
      start: now.subtract(const Duration(hours: 5)),
      end: now.subtract(const Duration(hours: 4)),
    );
    await _insert(db, 'd', 'Помити all-day', allDay: true);
  });
  tearDown(() => db.close());

  test(
    'name search is case-insensitive for Cyrillic and skips all-day',
    () async {
      expect(await q.watchNameMatchIds('помити').first, {'a', 'c'});
      expect(await q.watchNameMatchIds('БІБЛ'.toLowerCase()).first, {'b'});
      expect(await q.watchNameMatchIds('нема такого').first, isEmpty);
    },
  );

  test('the board columns and counts follow the matching ids', () async {
    final ids = {'a', 'c'};
    final notDone = await q
        .watchCurrentNotDone(limit: 50, nowUtc: now, onlyIds: ids)
        .first;
    final done = await q
        .watchCurrentDone(limit: 50, nowUtc: now, onlyIds: ids)
        .first;
    expect([for (final i in notDone) i.id], ['a']);
    expect([for (final i in done) i.id], ['c']);
    expect(
      await q.watchCurrentNotDoneCount(nowUtc: now, onlyIds: ids).first,
      1,
    );
    expect(await q.watchCurrentDoneCount(nowUtc: now, onlyIds: ids).first, 1);
    // No search at all = everything; an empty match = nothing.
    expect((await q.watchCurrentDone(limit: 50, nowUtc: now).first).length, 2);
    expect(await q.watchCurrentDoneCount(nowUtc: now, onlyIds: {}).first, 0);
  });

  test('upcoming reminders: only timed actions with a moment ahead', () async {
    // The query uses SQLite's own clock, so this one is anchored to real time.
    final real = DateTime.now().toUtc();
    await _insert(
      db,
      'e',
      'Soon',
      start: real.add(const Duration(hours: 1)),
      end: real.add(const Duration(hours: 2)),
    );
    final ids = [for (final i in await q.watchUpcoming().first) i.id];
    expect(ids, ['e']); // b, c are over; d is all-day; a is long past by now
  });
}

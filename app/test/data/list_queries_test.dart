import 'dart:async';
import 'dart:math';

import 'package:drift/drift.dart' show Value, Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/core/stream_utils.dart';
import 'package:livenow/core/time_codec.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/data/queries.dart';
import 'package:livenow/domain/done_rule.dart' as done_rule;

/// ~3 KB, like a checklist note.
final _bigNote = '{"document":${'x' * 3000}}';

Future<void> _insert(
  AppDatabase db,
  String id, {
  String? startAt,
  String? endAt,
  bool done = false,
  bool allDay = false,
  String? notes,
  String? resultNote,
  String updatedAt = 't',
}) => db
    .into(db.actionsTable)
    .insert(
      ActionsTableCompanion.insert(
        id: id,
        name: 'Action $id',
        done: Value(done),
        startAt: Value(startAt),
        endAt: Value(endAt),
        isAllDay: Value(allDay),
        notes: Value(notes),
        resultNote: Value(resultNote),
        createdAt: 't',
        updatedAt: updatedAt,
      ),
    );

/// The old algorithm: select every row, map, filter in Dart, order in SQL.
List<ActionRow> _oldCurrent(List<ActionRow> all, {required bool done}) {
  return all
      .where(
        (a) =>
            done_rule.isDoneBefore(
              startAt: dateTimeFromDb(a.startAt),
              endAt: dateTimeFromDb(a.endAt),
              isAllDay: a.isAllDay,
              done: a.done,
            ) ==
            done,
      )
      .toList();
}

void main() {
  late AppDatabase db;
  late ViewQueries queries;

  setUp(() {
    db = AppDatabase.forTesting(
      NativeDatabase.memory(
        setup: (raw) => raw.execute('PRAGMA foreign_keys = ON;'),
      ),
    );
    queries = ViewQueries(db);
  });
  tearDown(() => db.close());

  group('SQL done rule agrees with isDoneBefore', () {
    test('table of cases', () async {
      final now = DateTime.now().toUtc();
      String t(Duration d) => dateTimeToDb(now.add(d))!;
      final cases = <String, Map<String, dynamic>>{
        'unscheduled not done': {},
        'unscheduled done': {'done': true},
        'timed, end before now, flag off': {
          'start': t(const Duration(hours: -3)),
          'end': t(const Duration(hours: -2)),
        },
        'timed, end before now, flag on': {
          'start': t(const Duration(hours: -3)),
          'end': t(const Duration(hours: -2)),
          'done': true,
        },
        'timed, end after now, flag off': {
          'start': t(const Duration(hours: 1)),
          'end': t(const Duration(hours: 2)),
        },
        'timed, end after now, flag on': {
          'start': t(const Duration(hours: 1)),
          'end': t(const Duration(hours: 2)),
          'done': true,
        },
        'timed, end null, flag on': {
          'start': t(const Duration(hours: -1)),
          'done': true,
        },
        'timed, end null, flag off': {'start': t(const Duration(hours: -1))},
        'all-day, not done': {
          'start': t(const Duration(hours: -30)),
          'end': t(const Duration(hours: -6)),
          'allDay': true,
        },
        'all-day, done, end in future': {
          'start': t(const Duration(hours: 1)),
          'end': t(const Duration(hours: 25)),
          'allDay': true,
          'done': true,
        },
        'unscheduled with stray end in past': {
          'end': t(const Duration(hours: -2)),
        },
      };
      for (final e in cases.entries) {
        await _insert(
          db,
          e.key,
          startAt: e.value['start'] as String?,
          endAt: e.value['end'] as String?,
          done: e.value['done'] == true,
          allDay: e.value['allDay'] == true,
        );
      }
      final sqlDone = (await db
              .customSelect(
                'SELECT id FROM actions WHERE (${doneBeforeSql('?')})',
                variables: [Variable.withString(dateTimeToDb(now)!)],
              )
              .get())
          .map((r) => r.read<String>('id'))
          .toSet();
      for (final row in await db.select(db.actionsTable).get()) {
        final dart = done_rule.isDoneBefore(
          startAt: dateTimeFromDb(row.startAt),
          endAt: dateTimeFromDb(row.endAt),
          isAllDay: row.isAllDay,
          done: row.done,
        );
        expect(sqlDone.contains(row.id), dart, reason: row.id);
      }
      // And the default (SQLite clock) variant gives the same answer.
      final viaClock = (await queries.watchCurrentDone(limit: 100).first)
          .map((a) => a.id)
          .toSet();
      expect(viaClock, sqlDone);
    });
  });

  group('Current board queries', () {
    test('match the old Dart filtering on a few hundred mixed rows', () async {
      final rnd = Random(7);
      final now = DateTime.now().toUtc();
      var n = 0;
      for (var i = 0; i < 400; i++) {
        final scheduled = rnd.nextInt(3) != 0;
        // Distinct minute offsets so ordering is unambiguous among scheduled.
        final start = scheduled
            ? now.add(Duration(minutes: (rnd.nextInt(2000) - 1000) * 3 + 1))
            : null;
        final end = scheduled && rnd.nextInt(8) != 0
            ? start!.add(Duration(minutes: 30 + rnd.nextInt(5) * 7))
            : null;
        await _insert(
          db,
          'r${n++}',
          startAt: dateTimeToDb(start),
          endAt: dateTimeToDb(end),
          done: rnd.nextBool(),
          allDay: rnd.nextInt(6) == 0,
        );
      }
      final all = await db.select(db.actionsTable).get();

      final oldNotDone = _oldCurrent(all, done: false);
      final oldDone = _oldCurrent(all, done: true);
      // Old order: start_at IS NULL, start_at ASC  /  end_at IS NULL, end_at DESC.
      String key(String? v) => v ?? '';
      oldNotDone.sort((a, b) {
        final an = a.startAt == null, bn = b.startAt == null;
        if (an != bn) return an ? 1 : -1;
        return key(a.startAt).compareTo(key(b.startAt));
      });
      oldDone.sort((a, b) {
        final an = a.endAt == null, bn = b.endAt == null;
        if (an != bn) return an ? 1 : -1;
        return key(b.endAt).compareTo(key(a.endAt));
      });

      final notDone = await queries.watchCurrentNotDone(limit: 10000).first;
      final done = await queries.watchCurrentDone(limit: 10000).first;
      expect(notDone.map((a) => a.id).toSet(), oldNotDone.map((a) => a.id).toSet());
      expect(done.map((a) => a.id).toSet(), oldDone.map((a) => a.id).toSet());
      // Ties (equal / null keys) may come in any order, so compare the keys.
      expect(
        notDone.map((a) => dateTimeToDb(a.startAt)),
        oldNotDone.map((a) => a.startAt),
      );
      expect(
        done.map((a) => dateTimeToDb(a.endAt)),
        oldDone.map((a) => a.endAt),
      );

      // The page is a prefix of the full list; totals are the full counts.
      final page = await queries.watchCurrentNotDone(limit: 25).first;
      expect(page, notDone.take(25).toList());
      expect(await queries.watchCurrentNotDoneCount().first, oldNotDone.length);
      expect(await queries.watchCurrentDoneCount().first, oldDone.length);
    });

    test('5,000 rows: limit, totals, no notes read', () async {
      final now = DateTime.now().toUtc();
      await db.batch((b) {
        b.insertAll(db.actionsTable, [
          for (var i = 0; i < 5000; i++)
            ActionsTableCompanion.insert(
              id: 'b$i',
              name: 'Bulk $i',
              // 2500 done (past, finished), 2500 open (future).
              startAt: Value(
                dateTimeToDb(now.add(Duration(minutes: i < 2500 ? -5000 + i : 100 + i))),
              ),
              endAt: Value(
                dateTimeToDb(
                  now.add(Duration(minutes: i < 2500 ? -4990 + i : 110 + i)),
                ),
              ),
              notes: Value(i % 3 == 0 ? _bigNote : null),
              resultNote: Value(i % 5 == 0 ? 'outcome $i' : null),
              createdAt: 't',
              updatedAt: 't',
            ),
        ]);
      });
      await db.customStatement(
        "INSERT INTO metrics (id, name) VALUES ('m1', 'Dir')",
      );
      await db.customStatement(
        "INSERT INTO action_metrics (id, action_id, metric_id) "
        "SELECT 'l' || id, id, 'm1' FROM actions WHERE notes IS NOT NULL",
      );

      final notDone = await queries.watchCurrentNotDone(limit: 100).first;
      final done = await queries.watchCurrentDone(limit: 100).first;
      expect(notDone, hasLength(100));
      expect(done, hasLength(100));
      expect(notDone.every((a) => !a.isDoneBefore), isTrue);
      expect(done.every((a) => a.isDoneBefore), isTrue);
      // Open: nearest start first. Done: latest end first.
      expect(notDone.first.id, 'b2500');
      expect(done.first.id, 'b2499');
      expect(await queries.watchCurrentNotDoneCount().first, 2500);
      expect(await queries.watchCurrentDoneCount().first, 2500);

      // Nothing that backs a list carries notes.
      final all = await queries.watchAllActions().first;
      expect(all, hasLength(5000));
      final cal = await queries
          .watchCalendarWeek(
            weekStartUtc: now.subtract(const Duration(days: 1)),
            weekEndUtc: now.add(const Duration(days: 2)),
          )
          .first;
      expect(cal, isNotEmpty);
      final open = await queries.watchOpenActions().first;
      expect(open, hasLength(2500));
      expect(open.every((a) => a.notes == null && a.resultNote == null), isTrue);
      final linked = await queries.watchMetricLinkedActions().first;
      expect(linked, hasLength(1667));
      expect(
        linked.every((l) => l.$2.notes == null && l.$2.resultNote == null),
        isTrue,
      );
      // ...while the data really is there for the editor's full-row read.
      final full = await (db.select(db.actionsTable)
            ..where((t) => t.id.equals('b0')))
          .getSingle();
      expect(full.notes, _bigNote);

      final rowsOld = 5000;
      final noteBytes = _bigNote.length * linked.length;
      // ignore: avoid_print
      print(
        'MEASURE: old Current = 2 streams x $rowsOld rows ($rowsOld ActionRow + '
        '$rowsOld items each); new = ${notDone.length + done.length} items; '
        'notes bytes no longer read per list load: $noteBytes (x2 streams on '
        'Current, x1 on All/Calendar).',
      );
    });

    test('an unchanged result causes no new emission', () async {
      final now = DateTime.now().toUtc();
      await _insert(
        db,
        'a',
        startAt: dateTimeToDb(now.add(const Duration(hours: 1))),
        endAt: dateTimeToDb(now.add(const Duration(hours: 2))),
      );
      await _insert(db, 'b');
      final emissions = <List<ActionListItem>>[];
      final counts = <int>[];
      final s1 = queries.watchCurrentNotDone(limit: 100).listen(emissions.add);
      final s2 = queries.watchCurrentNotDoneCount().listen(counts.add);
      addTearDown(s1.cancel);
      addTearDown(s2.cancel);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(emissions, hasLength(1));
      expect(counts, [2]);

      // Only the notes column changes: the list result is identical.
      await db.customUpdate("UPDATE actions SET notes = 'hello' WHERE id = 'a'", updates: {db.actionsTable});
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(emissions, hasLength(1));
      expect(counts, [2]);

      // A visible change does emit, once, even for a burst of writes.
      await db.customUpdate("UPDATE actions SET name = 'x1' WHERE id = 'a'", updates: {db.actionsTable});
      await db.customUpdate("UPDATE actions SET name = 'x2' WHERE id = 'a'", updates: {db.actionsTable});
      await db.customUpdate("UPDATE actions SET name = 'x3' WHERE id = 'a'", updates: {db.actionsTable});
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(emissions.length, inInclusiveRange(2, 3));
      expect(emissions.last.firstWhere((a) => a.id == 'a').name, 'x3');
    });
  });

  group('stream helpers', () {
    test('debounced: first event now, then only the last after the quiet', () async {
      final src = StreamController<int>();
      final out = <int>[];
      final sub = debounced(src.stream, const Duration(milliseconds: 60)).listen(out.add);
      src.add(1);
      await Future<void>.delayed(Duration.zero);
      expect(out, [1]);
      src.add(2);
      src.add(3);
      src.add(4);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(out, [1]);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(out, [1, 4]);
      await sub.cancel();
      await src.close();
    });

    test('debounced: cancel drops the pending event and the timer', () async {
      final src = StreamController<int>();
      final out = <int>[];
      final sub = debounced(src.stream, const Duration(milliseconds: 30)).listen(out.add);
      src.add(1);
      src.add(2);
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(src.hasListener, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(out, [1]);
      await src.close();
    });

    test('debounced: completion flushes the pending event', () async {
      final src = StreamController<int>();
      final out = <int>[];
      final done = Completer<void>();
      debounced(src.stream, const Duration(seconds: 5)).listen(out.add, onDone: done.complete);
      src.add(1);
      src.add(2);
      await src.close();
      await done.future;
      expect(out, [1, 2]);
    });

    test('distinctList drops equal consecutive lists', () async {
      final out = await distinctList(
        Stream.fromIterable([
          [1, 2],
          [1, 2],
          [1, 2, 3],
          [1, 2, 3],
          [1, 2],
        ]),
      ).toList();
      expect(out, [
        [1, 2],
        [1, 2, 3],
        [1, 2],
      ]);
    });

    test('ActionListItem has value equality', () {
      ActionListItem make(String name) => ActionListItem(
        id: 'a',
        name: name,
        done: false,
        startAt: DateTime.utc(2024),
        isAllDay: false,
      );
      expect(make('x'), make('x'));
      expect(make('x').hashCode, make('x').hashCode);
      expect(make('x'), isNot(make('y')));
    });
  });
}

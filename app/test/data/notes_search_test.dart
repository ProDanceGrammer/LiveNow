import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/data/queries.dart';
import 'package:livenow/domain/action_service.dart';

String _doc(String text) =>
    '{"document":{"type":"page","children":[{"type":"paragraph",'
    '"data":{"delta":[{"insert":"$text"}]}}]}}';

Future<T> _first<T>(Stream<T> s) => s.first;

void main() {
  late AppDatabase db;
  late ActionService service;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    service = ActionService(db);
  });
  tearDown(() => db.close());

  Future<String?> notesText(String id) async => (await (db.select(
    db.actionsTable,
  )..where((t) => t.id.equals(id))).getSingle()).notesText;

  test(
    'create / update keep notes_text in step; absent notes leave it',
    () async {
      final id = await service.createAction(
        name: 'A',
        notes: _doc('Hello WORLD'),
      );
      expect(await notesText(id), 'hello world');

      await service.updateAction(
        actionId: id,
        name: 'A2',
        postponeFlex: 'flexible',
        isAllDay: false,
      );
      expect(await notesText(id), 'hello world', reason: 'notes untouched');

      await service.updateAction(
        actionId: id,
        name: 'A2',
        postponeFlex: 'flexible',
        isAllDay: false,
        notes: Value(_doc('Привіт')),
      );
      expect(await notesText(id), 'привіт');

      await service.updateAction(
        actionId: id,
        name: 'A2',
        postponeFlex: 'flexible',
        isAllDay: false,
        notes: const Value(null),
      );
      expect(await notesText(id), isNull);
    },
  );

  test('continue copies notes_text', () async {
    final id = await service.createAction(
      name: 'Run',
      notes: _doc('Some Notes'),
      startAt: DateTime.now().toUtc(),
      endAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
    );
    final result = await service.continueSameAction(id);
    expect(await notesText(result.newActionId), 'some notes');
  });

  test(
    'notes match query: case-folded, escapes LIKE wildcards, no notes read',
    () async {
      final a = await service.createAction(name: 'A', notes: _doc('Buy MILK'));
      final b = await service.createAction(name: 'B', notes: _doc('100% sure'));
      await service.createAction(name: 'C', notes: _doc('under_score'));
      await service.createAction(name: 'D');
      final q = ViewQueries(db);

      expect(await _first(q.watchNotesMatchIds('milk')), {a});
      expect(await _first(q.watchNotesMatchIds('0% s')), {b});
      expect((await _first(q.watchNotesMatchIds('%'))), {b});
      expect((await _first(q.watchNotesMatchIds('_'))).length, 1);
      expect(await _first(q.watchNotesMatchIds('zzz')), isEmpty);

      // The list rows never carry notes.
      final items = await _first(q.watchAllActions());
      expect(items, hasLength(4));
      expect(
        items.every((i) => i.updatedAt != null && i.createdAt != null),
        isTrue,
      );
    },
  );

  test('lean link streams', () async {
    final x = await service.createAction(name: 'X');
    final y = await service.createAction(name: 'Y');
    await db.customStatement(
      "INSERT INTO action_dependencies (id, predecessor_id, successor_id) "
      "VALUES ('d1', '$x', '$y')",
    );
    final q = ViewQueries(db);
    expect(await _first(q.watchPredecessorIds()), {
      y: {x},
    });
    expect(await _first(q.watchSuccessorIds()), {
      x: {y},
    });
    expect(await _first(q.watchActionMetricIds()), isEmpty);
  });
}

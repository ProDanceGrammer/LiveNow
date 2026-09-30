import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/action_service.dart';

/// Notes are the editor's Document JSON in `actions.notes`; the service treats
/// them as an opaque string. This is a checklist with one ticked child.
const _notes =
    '{"document":{"type":"page","children":['
    '{"type":"todo_list","data":{"checked":false,"delta":[{"insert":"Робоча пошта"}]},'
    '"children":[{"type":"todo_list","data":{"checked":true,"delta":[{"insert":"Gmail"}]}}]}'
    ']}}';

void main() {
  late AppDatabase db;
  late ActionService service;

  setUp(() {
    // Foreign keys on, like the real connection.
    db = AppDatabase.forTesting(
      NativeDatabase.memory(
        setup: (raw) => raw.execute('PRAGMA foreign_keys = ON;'),
      ),
    );
    service = ActionService(db);
  });

  tearDown(() => db.close());

  Future<ActionRow> row(String id) =>
      (db.select(db.actionsTable)..where((t) => t.id.equals(id))).getSingle();

  Future<String> create({String? notes = _notes}) =>
      service.createAction(name: '📬 Перевірити повідомлення', notes: notes);

  Future<void> update(
    String id, {
    Value<String?> notes = const Value.absent(),
  }) => service.updateAction(
    actionId: id,
    name: '📬 Перевірити повідомлення',
    postponeFlex: 'flexible',
    isAllDay: false,
    notes: notes,
  );

  test('createAction stores the notes exactly, Cyrillic included', () async {
    final id = await create();
    expect((await row(id)).notes, _notes);
  });

  test('an action created without notes has none', () async {
    final id = await create(notes: null);
    expect((await row(id)).notes, isNull);
  });

  test('updateAction without a notes argument leaves them alone', () async {
    final id = await create();
    await update(id); // e.g. a caller that only knows about the name
    expect((await row(id)).notes, _notes);
  });

  test('updateAction can replace and clear the notes', () async {
    final id = await create();
    await update(id, notes: const Value('{"document":{"type":"page"}}'));
    expect((await row(id)).notes, '{"document":{"type":"page"}}');
    await update(id, notes: const Value(null));
    expect((await row(id)).notes, isNull);
  });

  test('other quick actions do not touch the notes', () async {
    final id = await create();
    await service.start(id);
    await service.finish(id);
    expect((await row(id)).notes, _notes);
  });

  test(
    'Continue copies the notes exactly, ticks kept, source untouched',
    () async {
      final id = await create();
      final result = await service.continueSameAction(id);
      expect((await row(result.newActionId)).notes, _notes);
      expect((await row(id)).notes, _notes);
    },
  );

  test('undoing a Continue leaves the source notes intact', () async {
    final id = await create();
    final result = await service.continueSameAction(id);
    await service.undoContinue(result.undo);
    expect((await row(id)).notes, _notes);
  });

  test('snapshot / restore brings the notes back', () async {
    final id = await create();
    final snapshot = await service.snapshot(id);
    await update(id, notes: const Value('{"changed":true}'));
    await service.restore(snapshot);
    expect((await row(id)).notes, _notes);
  });

  test('delete + undoDelete restores the notes', () async {
    final id = await create();
    final undo = await service.deleteAction(id);
    await service.undoDelete(undo);
    expect((await row(id)).notes, _notes);
  });
}

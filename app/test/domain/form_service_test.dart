import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/form_service.dart';
import 'package:livenow/domain/forms.dart';

void main() {
  late AppDatabase db;
  late FormService svc;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    svc = FormService(db);
  });

  tearDown(() => db.close());

  FormDef sample(String name) => FormDef(
    name: name,
    description: 'd',
    questions: [
      FormQuestion(
        id: 'q',
        title: 'Q',
        options: [
          FormOption(id: 'o', label: 'opt', metricIds: const ['m1']),
        ],
      ),
    ],
  );

  test('save creates a form, get reads it back with its questions', () async {
    final id = await svc.save(sample('Goals'));
    final f = (await svc.get(id))!;
    expect(f.name, 'Goals');
    expect(f.def.description, 'd');
    expect(f.def.questions.single.options.single.metricIds, ['m1']);
  });

  test('saving with an id replaces that form in place (same id, new content)', () async {
    final id = await svc.save(sample('Goals'));
    final again = await svc.save(sample('Goals v2'), id: id);
    expect(again, id);
    expect((await svc.all()), hasLength(1));
    expect((await svc.get(id))!.name, 'Goals v2');
  });

  test('a blank name is refused; a name is trimmed', () async {
    expect(() => svc.save(sample('   ')), throwsArgumentError);
    final id = await svc.save(sample('  Padded  '));
    expect((await svc.get(id))!.name, 'Padded');
  });

  test('forms come back by name, ignoring emoji and case (Cyrillic too)', () async {
    await svc.save(sample('🙂 Бета'));
    await svc.save(sample('Альфа'));
    await svc.save(sample('гамма'));
    expect((await svc.all()).map((f) => f.name), ['Альфа', '🙂 Бета', 'гамма']);
    expect((await svc.watch().first).map((f) => f.name), ['Альфа', '🙂 Бета', 'гамма']);
  });

  test('duplicate makes a copy with the same questions', () async {
    final id = await svc.save(sample('Goals'));
    final copyId = (await svc.duplicate(id))!;
    expect(copyId, isNot(id));
    final copy = (await svc.get(copyId))!;
    expect(copy.name, 'Goals (copy)');
    expect(copy.def.questions.single.options.single.label, 'opt');
    expect(await svc.duplicate('missing'), isNull);
  });

  test('delete returns the row and undoDelete puts it back', () async {
    final id = await svc.save(sample('Goals'));
    final row = (await svc.delete(id))!;
    expect(await svc.get(id), isNull);
    expect(await svc.delete(id), isNull); // already gone
    await svc.undoDelete(row);
    final back = (await svc.get(id))!;
    expect(back.name, 'Goals');
    expect(back.def.questions, hasLength(1));
  });

  test('forms are stamped for sync, and a delete leaves a tombstone', () async {
    final id = await svc.save(sample('Goals'));
    Future<List<Map<String, Object?>>> versions() async => [
      for (final r in await db
          .customSelect(
            "SELECT deleted FROM sync_versions WHERE tbl = 'forms' AND row_id = '$id'",
          )
          .get())
        r.data,
    ];
    expect((await versions()).single['deleted'], 0);
    await svc.delete(id);
    expect((await versions()).single['deleted'], 1);
  });
}

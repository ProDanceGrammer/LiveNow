import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/core/text_rules.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/action_service.dart';

void main() {
  late AppDatabase db;
  late ActionService service;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    service = ActionService(db);
  });
  tearDown(() => db.close());

  Future<void> template(String id, String name, Map<String, Object?> payload) =>
      db.into(db.actionTemplatesTable).insert(
            ActionTemplatesTableCompanion.insert(
              id: id,
              name: name,
              payload: jsonEncode({'name': name, ...payload}),
            ),
          );

  test('a copy keeps the payload, is named "(copy)"; deleting it undoes', () async {
    await template('t1', 'Walk', {'isAllDay': true, 'metricIds': ['m1']});
    final copyId = await service.duplicateTemplate('t1');
    expect(copyId, isNotNull);
    final copy = await (db.select(db.actionTemplatesTable)
          ..where((t) => t.id.equals(copyId!)))
        .getSingle();
    expect(copy.name, 'Walk (copy)');
    final p = jsonDecode(copy.payload) as Map<String, dynamic>;
    expect(p['name'], 'Walk (copy)');
    expect(p['isAllDay'], isTrue);
    expect(p['metricIds'], ['m1']);

    await service.deleteTemplate(copyId!);
    final left = await db.select(db.actionTemplatesTable).get();
    expect(left.map((t) => t.id), ['t1']);
  });

  test('a missing template gives null; a long name stays within the limit', () async {
    expect(await service.duplicateTemplate('nope'), isNull);
    final long = 'x' * kMaxNameLength;
    await template('t2', long, const {});
    final copyId = await service.duplicateTemplate('t2');
    final copy = await (db.select(db.actionTemplatesTable)
          ..where((t) => t.id.equals(copyId!)))
        .getSingle();
    expect(copy.name.length, kMaxNameLength);
    expect(copy.name, endsWith(' (copy)'));
  });
}

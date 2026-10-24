import 'package:drift/drift.dart';

import '../core/ids.dart';
import '../core/text_rules.dart';
import '../core/time_codec.dart';
import '../data/database.dart';
import 'forms.dart';
import 'name_sort.dart';

/// A stored form with its row id.
class FormItem {
  const FormItem({required this.id, required this.def, required this.updatedAt});

  final String id;
  final FormDef def;
  final String updatedAt;

  String get name => def.name;
}

/// Stores the forms (`forms`, synced). The definition lives in one JSON payload
/// (see `forms.dart`); a form is a row, so two devices editing the same form
/// conflict as a whole row (the sync conflicts dialog can restore the other one).
class FormService {
  FormService(this.db);

  final AppDatabase db;

  FormItem _item(FormRow r) => FormItem(
    id: r.id,
    def: decodeFormPayload(r.name, r.payload),
    updatedAt: r.updatedAt,
  );

  /// All forms, by name (emoji ignored, Cyrillic-safe).
  Stream<List<FormItem>> watch() => db
      .select(db.formsTable)
      .watch()
      .map(
        (rows) => [for (final r in rows) _item(r)]
          ..sort((a, b) => compareIgnoringEmoji(a.name, b.name)),
      );

  Future<List<FormItem>> all() async => [
    for (final r in await db.select(db.formsTable).get()) _item(r),
  ]..sort((a, b) => compareIgnoringEmoji(a.name, b.name));

  Future<FormItem?> get(String id) async {
    final r = await (db.select(
      db.formsTable,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return r == null ? null : _item(r);
  }

  /// Creates the form (when [id] is null) or replaces the stored one; returns
  /// its id. A blank name is refused.
  Future<String> save(FormDef form, {String? id}) async {
    final name = cleanName(form.name, what: 'form name');
    if (name.isEmpty) throw ArgumentError('A form needs a name.');
    final now = dateTimeToDb(DateTime.now())!;
    final payload = encodeFormPayload(form.copyWith(name: name));
    if (id != null) {
      final changed =
          await (db.update(db.formsTable)..where((t) => t.id.equals(id)))
              .write(
                FormsTableCompanion(
                  name: Value(name),
                  payload: Value(payload),
                  updatedAt: Value(now),
                ),
              );
      if (changed > 0) return id;
    }
    final newRowId = id ?? newId();
    await db
        .into(db.formsTable)
        .insert(
          FormsTableCompanion.insert(
            id: newRowId,
            name: Value(name),
            payload: Value(payload),
            createdAt: now,
            updatedAt: now,
          ),
        );
    return newRowId;
  }

  /// A copy under a new name (new question and option ids stay: they only have
  /// to be unique inside one form).
  Future<String?> duplicate(String id) async {
    final f = await get(id);
    if (f == null) return null;
    return save(f.def.copyWith(name: '${f.def.name} (copy)'));
  }

  /// Deletes and returns the row, so Undo can put it back.
  Future<FormRow?> delete(String id) async {
    final row = await (db.select(
      db.formsTable,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null) return null;
    await (db.delete(db.formsTable)..where((t) => t.id.equals(id))).go();
    return row;
  }

  Future<void> undoDelete(FormRow row) =>
      db.into(db.formsTable).insertOnConflictUpdate(row);
}

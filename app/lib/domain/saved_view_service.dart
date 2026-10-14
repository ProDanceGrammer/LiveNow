import 'package:drift/drift.dart';

import '../core/ids.dart';
import '../core/time_codec.dart';
import '../data/database.dart';
import 'name_sort.dart';
import 'saved_views.dart';

/// Stores the saved views (`saved_views`, synced). At most one view per screen
/// is the default; names are unique per screen, ignoring case.
class SavedViewService {
  SavedViewService(this.db);

  final AppDatabase db;

  SavedViewItem _item(SavedView r) => SavedViewItem.fromRow(
    id: r.id,
    screen: r.screen,
    name: r.name,
    kind: r.kind,
    payload: r.payload,
    isDefault: r.isDefault,
    updatedAt: r.updatedAt,
  );

  /// The views of [screen], by name.
  Stream<List<SavedViewItem>> watch(String screen) =>
      (db.select(db.savedViewsTable)..where((t) => t.screen.equals(screen)))
          .watch()
          .map(
            (rows) => [for (final r in rows) _item(r)]
              ..sort((a, b) => compareIgnoringEmoji(a.name, b.name)),
          );

  Future<List<SavedViewItem>> all(String screen) async => [
    for (final r in await (db.select(
      db.savedViewsTable,
    )..where((t) => t.screen.equals(screen))).get())
      _item(r),
  ];

  /// The view of [screen] with this [name] (ignoring case), or null.
  Future<SavedViewItem?> byName(String screen, String name) async {
    final wanted = name.trim().toLowerCase();
    for (final v in await all(screen)) {
      if (v.name.trim().toLowerCase() == wanted) return v;
    }
    return null;
  }

  /// Saves a view. An existing view of the same screen and name (ignoring
  /// case) is replaced in place (its id and default flag stay); returns the id.
  Future<String> save({
    required String screen,
    required String name,
    required SavedViewKind kind,
    Map<String, Object?> sort = const {},
    Map<String, Object?> filter = const {},
  }) async {
    final clean = name.trim();
    if (clean.isEmpty) throw ArgumentError('A view needs a name.');
    final payload = encodeViewPayload(
      sort: kind.hasSort ? sort : const {},
      filter: kind.hasFilter ? filter : const {},
    );
    final now = dateTimeToDb(DateTime.now())!;
    return db.transaction(() async {
      final existing = await byName(screen, clean);
      if (existing != null) {
        await (db.update(db.savedViewsTable)
              ..where((t) => t.id.equals(existing.id)))
            .write(
              SavedViewsTableCompanion(
                name: Value(clean),
                kind: Value(kind.name),
                payload: Value(payload),
                updatedAt: Value(now),
              ),
            );
        return existing.id;
      }
      final id = newId();
      await db
          .into(db.savedViewsTable)
          .insert(
            SavedViewsTableCompanion.insert(
              id: id,
              screen: screen,
              name: clean,
              kind: Value(kind.name),
              payload: Value(payload),
              createdAt: now,
              updatedAt: now,
            ),
          );
      return id;
    });
  }

  /// Renames; false when another view of the screen already has that name.
  Future<bool> rename(String id, String name) async {
    final clean = name.trim();
    if (clean.isEmpty) return false;
    final row = await (db.select(
      db.savedViewsTable,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null) return false;
    final clash = await byName(row.screen, clean);
    if (clash != null && clash.id != id) return false;
    await (db.update(db.savedViewsTable)..where((t) => t.id.equals(id))).write(
      SavedViewsTableCompanion(
        name: Value(clean),
        updatedAt: Value(dateTimeToDb(DateTime.now())!),
      ),
    );
    return true;
  }

  /// Makes [id] the default of its screen (every other view of the screen stops
  /// being one), or clears the flag with [on] false.
  Future<void> setDefault(String id, {bool on = true}) async {
    final row = await (db.select(
      db.savedViewsTable,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null) return;
    final now = Value(dateTimeToDb(DateTime.now())!);
    await db.transaction(() async {
      if (on) {
        await (db.update(db.savedViewsTable)
              ..where((t) => t.screen.equals(row.screen) & t.id.equals(id).not() & t.isDefault.equals(true)))
            .write(SavedViewsTableCompanion(isDefault: const Value(false), updatedAt: now));
      }
      await (db.update(db.savedViewsTable)..where((t) => t.id.equals(id))).write(
        SavedViewsTableCompanion(isDefault: Value(on), updatedAt: now),
      );
    });
  }

  /// Deletes a view; the removed row lets the caller offer Undo.
  Future<SavedView?> delete(String id) async {
    final row = await (db.select(
      db.savedViewsTable,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null) return null;
    await (db.delete(db.savedViewsTable)..where((t) => t.id.equals(id))).go();
    return row;
  }

  Future<void> undoDelete(SavedView row) =>
      db.into(db.savedViewsTable).insertOnConflictUpdate(row);
}

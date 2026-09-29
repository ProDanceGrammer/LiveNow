import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/database.dart';

void main() {
  test('v1 database upgrades to v2 keeping its rows', () async {
    final db = AppDatabase.forTesting(
      NativeDatabase.memory(
        setup: (raw) {
          // The actions table exactly as schema v1 created it.
          raw.execute('''
            CREATE TABLE actions (
              id TEXT NOT NULL PRIMARY KEY,
              name TEXT NOT NULL,
              done INTEGER NOT NULL DEFAULT 0,
              priority TEXT NULL,
              postpone_flex TEXT NOT NULL DEFAULT 'flexible',
              depth_level TEXT NULL,
              start_at TEXT NULL,
              end_at TEXT NULL,
              is_all_day INTEGER NOT NULL DEFAULT 0,
              estimated_minutes INTEGER NULL,
              result_note TEXT NULL,
              completed_at TEXT NULL,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL
            )''');
          raw.execute(
            "INSERT INTO actions (id, name, created_at, updated_at) "
            "VALUES ('a1', 'Old action', 't', 't')",
          );
          raw.execute('PRAGMA user_version = 1');
        },
      ),
    );
    addTearDown(db.close);

    final rows = await db.select(db.actionsTable).get();
    expect(rows.single.name, 'Old action');
    expect(rows.single.sequenceNumber, isNull);
    expect(rows.single.countableActivityId, isNull);

    // The new table works and the new FK column accepts it.
    await db
        .into(db.countableActivitiesTable)
        .insert(
          CountableActivitiesTableCompanion.insert(
            id: 'c1',
            name: 'Reading',
            createdAt: 't',
            updatedAt: 't',
          ),
        );
    await db.customStatement(
      "UPDATE actions SET countable_activity_id = 'c1' WHERE id = 'a1'",
    );
    expect(
      (await db.select(db.actionsTable).get()).single.countableActivityId,
      'c1',
    );
  });
}

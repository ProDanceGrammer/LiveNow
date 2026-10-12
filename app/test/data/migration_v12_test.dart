import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/budget_io_service.dart';
import 'package:livenow/domain/budget_service.dart';

/// Schema v12 adds `budget_accounts.icon` (the account's picture as base64
/// text). A v11 file must upgrade without losing its accounts, and the picture
/// must travel in the JSON backup and in the sync log like any other column.
void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('livenow_v12_'));
  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('a v11 database gets the icon column, its accounts stay', () async {
    final file = File('${dir.path}/old.sqlite');

    // 1. Create a current database, then turn it back into a v11 one: drop the
    //    new column and stamp the old version.
    var db = AppDatabase.forTesting(NativeDatabase(file));
    await BudgetService(db).saveAccount(
      name: 'Euro card',
      currency: 'EUR',
      rateToBase: 1,
      openingBalance: 5,
    );
    await db.close();

    // 2. Open it again with the app's schema; the setup hook runs BEFORE drift
    //    checks the version, so the file looks like a v11 one: no icon column
    //    (the sync triggers that mention it go first), user_version 11.
    db = AppDatabase.forTesting(
      NativeDatabase(
        file,
        setup: (rawDb) {
          for (final t in rawDb.select(
            "SELECT name FROM sqlite_master WHERE type='trigger' "
            "AND tbl_name='budget_accounts'",
          )) {
            rawDb.execute('DROP TRIGGER IF EXISTS "${t['name']}"');
          }
          rawDb.execute('ALTER TABLE budget_accounts DROP COLUMN icon');
          rawDb.execute('PRAGMA user_version = 11');
        },
      ),
    );
    addTearDown(db.close);
    final account = await db.select(db.budgetAccountsTable).getSingle();
    expect(account.name, 'Euro card');
    expect(account.openingBalance, 5);
    expect(account.icon, isNull);

    // The new column is writable and read back.
    await BudgetService(db).saveAccount(
      id: account.id,
      name: 'Euro card',
      currency: 'EUR',
      rateToBase: 1,
      openingBalance: 5,
      icon: const Value('QUJD'),
    );
    expect((await db.select(db.budgetAccountsTable).getSingle()).icon, 'QUJD');
  });

  test(
    'saving an account keeps the picture unless it is changed or removed',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final b = BudgetService(db);
      final id = await b.saveAccount(
        name: 'Cash',
        currency: 'TRY',
        rateToBase: 40,
        icon: const Value('PNGDATA'),
      );
      Future<String?> icon() async =>
          (await db.select(db.budgetAccountsTable).getSingle()).icon;

      // A save that does not mention the picture leaves it alone.
      await b.saveAccount(
        id: id,
        name: 'Cash 2',
        currency: 'TRY',
        rateToBase: 40,
      );
      expect(await icon(), 'PNGDATA');
      // Value(null) removes it.
      await b.saveAccount(
        id: id,
        name: 'Cash 2',
        currency: 'TRY',
        rateToBase: 40,
        icon: const Value(null),
      );
      expect(await icon(), isNull);
    },
  );

  test('the JSON backup carries the picture; an old backup without it still imports', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await BudgetService(db).saveAccount(
      name: 'Card',
      currency: 'EUR',
      rateToBase: 1,
      icon: const Value('QUJDRA=='),
    );
    final io = BudgetIoService(db);
    final json = await io.exportJson();
    expect(json, contains('QUJDRA=='));

    // Restore into a fresh database.
    final db2 = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db2.close);
    await BudgetIoService(db2).importJson(json);
    expect(
      (await db2.select(db2.budgetAccountsTable).getSingle()).icon,
      'QUJDRA==',
    );

    // A backup written before pictures existed has no "icon" key.
    final data = jsonDecode(json) as Map<String, dynamic>;
    for (final a in data['accounts'] as List) {
      (a as Map<String, dynamic>).remove('icon');
    }
    final db3 = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db3.close);
    await BudgetIoService(db3).importJson(jsonEncode(data));
    expect(
      (await db3.select(db3.budgetAccountsTable).getSingle()).icon,
      isNull,
    );
  });
}

import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/action_service.dart';
import 'package:livenow/domain/actions_csv.dart' show localWallToUtc;
import 'package:livenow/domain/budget_io_service.dart';
import 'package:livenow/domain/budget_service.dart';
import 'package:livenow/domain/growth_import.dart' show parseCsv;
import 'package:livenow/domain/postpone_rules.dart';

import 'budget_csv_test.dart' show accountsCsv, categoriesCsv, transactionsCsv;

AppDatabase _db() => AppDatabase.forTesting(
  NativeDatabase.memory(
    setup: (raw) => raw.execute('PRAGMA foreign_keys = ON;'),
  ),
);

void main() {
  setUpAll(initPostponeTimeZoneData);

  late AppDatabase db;
  late BudgetIoService io;

  setUp(() {
    db = _db();
    io = BudgetIoService(db);
  });
  tearDown(() => db.close());

  Future<BudgetImportSummary> importSample() => io.importNotionCsvs(
    accountsCsv: accountsCsv,
    categoriesCsv: categoriesCsv,
    transactionsCsv: transactionsCsv,
  );

  group('Notion CSV import', () {
    test(
      'creates accounts, categories (with links) and transactions',
      () async {
        final s = await importSample();
        expect((s.accounts, s.categories, s.transactions), (3, 7, 3));
        expect(s.skippedNoCategory, 1);
        expect(s.skippedNoDate, 1);
        expect(s.unresolvedChildren, ['Hygiene: New page']);
        expect(s.ratesMissing, ['(₴) Monobank']);
        expect(s.hasWarnings, isTrue);

        final cats = await db.select(db.budgetCategoriesTable).get();
        final chicken = cats.firstWhere(
          (c) => c.price == null && c.name == 'Chicken',
        );
        expect(cats.where((c) => c.parentId == chicken.id), hasLength(2));
        final cushion = cats.firstWhere((c) => c.name == 'Cushion');
        final salary = cats.firstWhere((c) => c.name == 'Salary');
        expect(cushion.countPercentOfId, salary.id);
        expect(cushion.percent, 10);

        final accounts = await db.select(db.budgetAccountsTable).get();
        final tl = accounts.firstWhere((a) => a.name == 'Turkish Lira');
        expect(tl.currency, 'TRY');
        expect(tl.rateToBase, 55.9);
      },
    );

    test('transactions snapshot price, accounts and rates', () async {
      await importSample();
      final txs = await db.select(db.budgetTransactionsTable).get();
      final pay = txs.firstWhere((t) => t.name == 'Pay');
      expect(pay.isIncome, isTrue);
      expect(pay.unitPrice, 2200);
      expect(pay.rateCount, 1); // blank in the file: the Euro account's rate
      final breast = txs.firstWhere((t) => t.name == 'Chicken breast');
      expect(breast.unitPrice, 7);
      expect(breast.quantity, 2);
      expect(breast.rateCount, 55.9);
      expect(breast.occurredAt, startsWith('2026-10-08T15:37'));
    });

    test('links to an existing action with the same name and start', () async {
      final action = await ActionService(db).createAction(
        name: '🍓 Bazaar',
        startAt: localWallToUtc(2026, 10, 8, 18, 37),
      );
      final s = await importSample();
      expect(s.linkedToActions, 1);
      expect(s.actionsNotFound, 0);
      final breast = (await db.select(db.budgetTransactionsTable).get())
          .firstWhere((t) => t.name == 'Chicken breast');
      expect(breast.actionId, action);
    });

    test(
      'an action nobody has is counted, the transaction keeps its date',
      () async {
        final s = await importSample();
        expect(s.linkedToActions, 0);
        expect(s.actionsNotFound, 1);
      },
    );

    test('importing again replaces instead of duplicating', () async {
      await importSample();
      expect(await io.hasData(), isTrue);
      await importSample();
      expect(await db.select(db.budgetAccountsTable).get(), hasLength(3));
      expect(await db.select(db.budgetCategoriesTable).get(), hasLength(7));
      expect(await db.select(db.budgetTransactionsTable).get(), hasLength(3));
    });

    test('a bad file changes nothing', () async {
      await importSample();
      expect(
        () => io.importNotionCsvs(categoriesCsv: 'just,some\n1,2\n'),
        throwsFormatException,
      );
      expect(await db.select(db.budgetTransactionsTable).get(), hasLength(3));
    });
  });

  group('JSON backup', () {
    Map<String, dynamic> content(String json) {
      final m = jsonDecode(json) as Map<String, dynamic>;
      return {
        for (final k in ['settings', 'accounts', 'categories', 'transactions'])
          k: m[k],
      };
    }

    test('export then import into a fresh database is lossless', () async {
      await importSample();
      await BudgetService(db).saveSettings(
        const BudgetSettings(
          baseCurrency: 'USD',
          periodMonths: 6,
          tolerance: 25,
        ),
      );
      final json = await io.exportJson();
      expect(BudgetIoService.looksLikeBackup(json), isTrue);

      final other = _db();
      addTearDown(other.close);
      final s = await BudgetIoService(other).importJson(json);
      expect((s.accounts, s.categories, s.transactions), (3, 7, 3));
      expect(content(await BudgetIoService(other).exportJson()), content(json));
      expect((await BudgetService(other).settings()).baseCurrency, 'USD');
    });

    test(
      'a backup keeps its dates when the action ids do not exist here',
      () async {
        final actions = ActionService(db);
        final a = await actions.createAction(
          name: 'Shop',
          startAt: DateTime.utc(2026, 11, 3, 9),
        );
        final b = BudgetService(db);
        final cat = await b.saveCategory(const CategoryInput(name: 'x'));
        await b.createTransaction(categoryId: cat, actionId: a, quantity: 1);
        final json = await io.exportJson();

        final other = _db();
        addTearDown(other.close);
        await BudgetIoService(other).importJson(json);
        final tx =
            (await other.select(other.budgetTransactionsTable).get()).single;
        expect(tx.actionId, isNull);
        expect(tx.occurredAt, startsWith('2026-11-03T09:00'));
      },
    );

    test('rejects garbage, other JSON and newer versions', () async {
      expect(() => io.importJson('not json'), throwsFormatException);
      expect(() => io.importJson('{"a":1}'), throwsFormatException);
      expect(
        () => io.importJson('{"format":"livenow-budget","version":99}'),
        throwsFormatException,
      );
      expect(BudgetIoService.looksLikeBackup('nope'), isFalse);
    });
  });

  group('CSV export', () {
    test(
      'writes the Notion layout and re-imports to the same structure',
      () async {
        await importSample();
        final files = await io.exportCsvs();
        expect(files.keys, [
          'Budget - Accounts.csv',
          'Budget - Categories.csv',
          'Budget - Transactions.csv',
        ]);
        expect(files['Budget - Categories.csv'], startsWith('Category name,'));

        final other = _db();
        addTearDown(other.close);
        final again = await BudgetIoService(other).importNotionCsvs(
          accountsCsv: files['Budget - Accounts.csv'],
          categoriesCsv: files['Budget - Categories.csv'],
          transactionsCsv: files['Budget - Transactions.csv'],
        );
        expect(
          (again.accounts, again.categories, again.transactions),
          (3, 7, 3),
        );

        final accounts = await other.select(other.budgetAccountsTable).get();
        // Currency and rate survive thanks to the extra account columns.
        expect(
          accounts.firstWhere((a) => a.name == 'Turkish Lira').rateToBase,
          55.9,
        );
        final cats = await other.select(other.budgetCategoriesTable).get();
        final chicken = cats.firstWhere(
          (c) => c.name == 'Chicken' && c.price == null,
        );
        expect(cats.where((c) => c.parentId == chicken.id), hasLength(2));
        expect(
          cats.firstWhere((c) => c.name == 'Cushion').countPercentOfId,
          isNotNull,
        );
      },
    );

    test('transactions carry the calculated Total Income (Interactional '
        'Account) with comma decimals', () async {
      final b = BudgetService(db);
      final tl = await b.saveAccount(
        name: 'Lira',
        currency: 'TRY',
        rateToBase: 40,
      );
      final eur = await b.saveAccount(
        name: 'Euro',
        currency: 'EUR',
        rateToBase: 1,
      );
      final food = await b.saveCategory(
        CategoryInput(
          name: 'Food',
          price: 400,
          accountCountId: tl,
          accountUseId: eur,
        ),
      );
      final pay = await b.saveCategory(
        CategoryInput(
          name: 'Pay',
          isIncome: true,
          price: 100,
          accountCountId: eur,
          accountUseId: eur,
        ),
      );
      final misc = await b.saveCategory(
        const CategoryInput(name: 'Misc', price: 5),
      );
      final day = DateTime.utc(2026, 10, 1, 9);
      await b.createTransaction(categoryId: food, name: 'groceries', date: day);
      await b.createTransaction(
        categoryId: pay,
        name: 'salary',
        quantity: 1.5,
        date: day,
      );
      await b.createTransaction(
        categoryId: misc,
        name: 'no account',
        date: day,
      );

      final csv = (await io.exportCsvs())['Budget - Transactions.csv']!;
      final rows = parseCsv(csv);
      expect(rows.first.last, 'Total Income (Interactional Account)');
      final byName = {for (final r in rows.skip(1)) r[4]: r.last};
      // 400 TRY / 40 = 10 EUR, an expense; 1.5 x 100 EUR income.
      expect(byName['groceries'], '-10,00');
      expect(byName['salary'], '150,00');
      expect(byName['no account'], ''); // cannot be converted: left blank
      // The comma forces quoting in the raw text.
      expect(csv, contains('"-10,00"'));

      // The importer ignores the calculated column.
      final other = _db();
      addTearDown(other.close);
      final again = await BudgetIoService(other).importNotionCsvs(
        accountsCsv: (await io.exportCsvs())['Budget - Accounts.csv'],
        categoriesCsv: (await io.exportCsvs())['Budget - Categories.csv'],
        transactionsCsv: csv,
      );
      expect(again.transactions, 3);
    });

    test('quotes commas and quotes in names', () async {
      final b = BudgetService(db);
      await b.saveCategory(const CategoryInput(name: 'Fish, "fresh"'));
      final csv = (await io.exportCsvs())['Budget - Categories.csv']!;
      expect(csv, contains('"Fish, ""fresh"""'));
    });
  });
}

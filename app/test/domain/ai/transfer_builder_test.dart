import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/ai/transfer_builder.dart';
import 'package:livenow/domain/budget_service.dart';

void main() {
  late AppDatabase db;
  late BudgetService budget;
  late TransferBuilder transfers;

  setUp(() {
    db = AppDatabase.forTesting(
      NativeDatabase.memory(
        setup: (raw) => raw.execute('PRAGMA foreign_keys = ON;'),
      ),
    );
    budget = BudgetService(db);
    transfers = TransferBuilder(db, budget);
  });
  tearDown(() => db.close());

  Future<BudgetTransaction> tx(String id) => (db.select(
    db.budgetTransactionsTable,
  )..where((t) => t.id.equals(id))).getSingle();

  Future<double> accountRate(String id) async => (await (db.select(
    db.budgetAccountsTable,
  )..where((t) => t.id.equals(id))).getSingle()).rateToBase;

  test('creates a linked expense + income, keeps account rates, undoes together',
      () async {
    final fop = await budget.saveAccount(name: 'FOP', currency: 'uah', rateToBase: 40);
    final mono = await budget.saveAccount(name: 'Mono', currency: 'uah', rateToBase: 41);
    final date = DateTime.utc(2026, 10, 18, 9);
    final r = await transfers.create(
      sourceAccountId: fop,
      destAccountId: mono,
      sourceAmount: 12582.50,
      sourceRate: 48.1,
      destRate: 48.1,
      date: date,
      namespaceId: 'job-1',
    );
    final out = await tx(r.expenseId);
    final inc = await tx(r.incomeId);
    expect(out.isIncome, false);
    expect(inc.isIncome, true);
    expect(out.accountUseId, fop);
    expect(inc.accountUseId, mono);
    expect(out.quantity, 12582.50);
    expect(out.unitPrice, 1);
    expect(out.rateInteract, 48.1);
    expect(inc.rateInteract, 48.1);
    expect(await accountRate(fop), 40);
    expect(await accountRate(mono), 41);
    expect(r.createdCategoryIds, hasLength(2));

    final names = (await db.select(db.budgetCategoriesTable).get())
        .map((c) => c.name)
        .toSet();
    expect(names, {'Виведення з FOP', 'Переказ на Mono'});

    // re-run: same rows, no new categories
    final again = await transfers.create(
      sourceAccountId: fop,
      destAccountId: mono,
      sourceAmount: 12582.50,
      sourceRate: 48.1,
      destRate: 48.1,
      date: date,
      namespaceId: 'job-1',
    );
    expect(again.expenseId, r.expenseId);
    expect(again.createdCategoryIds, isEmpty);
    expect(await db.select(db.budgetTransactionsTable).get(), hasLength(2));

    await transfers.delete(r);
    expect(await db.select(db.budgetTransactionsTable).get(), isEmpty);
  });

  test('refuses a placeholder rate and the same account twice', () async {
    final a = await budget.saveAccount(name: 'A', currency: 'uah', rateToBase: 40);
    final b = await budget.saveAccount(name: 'B', currency: 'uah', rateToBase: 40);
    final date = DateTime.utc(2026, 10, 18);
    expect(
      () => transfers.create(
        sourceAccountId: a, destAccountId: b, sourceAmount: 1,
        sourceRate: 0, destRate: 40, date: date,
      ),
      throwsArgumentError,
    );
    expect(
      () => transfers.create(
        sourceAccountId: a, destAccountId: a, sourceAmount: 1,
        sourceRate: 40, destRate: 40, date: date,
      ),
      throwsArgumentError,
    );
  });
}

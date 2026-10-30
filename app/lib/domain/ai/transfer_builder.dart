import '../../core/ids.dart';
import '../../data/database.dart';
import '../budget_rules.dart';
import '../budget_service.dart';

/// What [TransferBuilder.create] wrote.
class TransferResult {
  const TransferResult({
    required this.expenseId,
    required this.incomeId,
    required this.createdCategoryIds,
  });

  final String expenseId;
  final String incomeId;

  /// Categories this call had to create (empty when both existed already).
  final List<String> createdCategoryIds;
}

/// A7: a transfer between two own accounts is TWO linked transactions, written
/// atomically: an expense on `Виведення з <source>` (use = source account) and
/// an income on `Переказ на <destination>` (use = destination account).
/// Both carry the REAL base-currency rate of their account on that date, which
/// is stored on the transaction only; the accounts' own rates are not touched.
class TransferBuilder {
  TransferBuilder(this.db, this.budget);

  final AppDatabase db;
  final BudgetService budget;

  static String expenseCategoryName(String accountName) =>
      'Виведення з $accountName';
  static String incomeCategoryName(String accountName) =>
      'Переказ на $accountName';

  /// [sourceAmount] / [destAmount] are in each account's own currency
  /// ([destAmount] defaults to [sourceAmount], same currency). [sourceRate] /
  /// [destRate] = units of that account's currency per 1 base currency on
  /// [date] (must be > 0; never a placeholder 1 for a non-base currency).
  /// [namespaceId] (the AI job id) + [index] derive the transaction ids so a
  /// re-run returns the same rows.
  Future<TransferResult> create({
    required String sourceAccountId,
    required String destAccountId,
    required double sourceAmount,
    double? destAmount,
    required double sourceRate,
    required double destRate,
    required DateTime date,
    String? actionId,
    String? namespaceId,
    int index = 0,
  }) {
    if (!(sourceRate > 0) || !(destRate > 0)) {
      throw ArgumentError('A transfer needs a real exchange rate for both sides.');
    }
    if (sourceAccountId == destAccountId) {
      throw ArgumentError('A transfer needs two different accounts.');
    }
    return db.transaction(() async {
      final source = await _account(sourceAccountId);
      final dest = await _account(destAccountId);
      final created = <String>[];
      final outCat = await _category(
        expenseCategoryName(source.name),
        source.id,
        income: false,
        created: created,
      );
      final inCat = await _category(
        incomeCategoryName(dest.name),
        dest.id,
        income: true,
        created: created,
      );
      final out = await budget.createTransaction(
        id: namespaceId == null ? null : deriveId(namespaceId, 'transfer-out', index),
        categoryId: outCat,
        name: expenseCategoryName(source.name),
        actionId: actionId,
        date: date,
        quantity: sourceAmount,
        rateInteract: sourceRate,
        updateAccountRate: false,
      );
      final inc = await budget.createTransaction(
        id: namespaceId == null ? null : deriveId(namespaceId, 'transfer-in', index),
        categoryId: inCat,
        name: incomeCategoryName(dest.name),
        actionId: actionId,
        date: date,
        quantity: destAmount ?? sourceAmount,
        rateInteract: destRate,
        updateAccountRate: false,
      );
      return TransferResult(
        expenseId: out,
        incomeId: inc,
        createdCategoryIds: created,
      );
    });
  }

  /// Undo: deletes both transactions together (categories stay).
  Future<void> delete(TransferResult result) => db.transaction(() async {
    await budget.deleteTransaction(result.expenseId);
    await budget.deleteTransaction(result.incomeId);
  });

  Future<BudgetAccount> _account(String id) => (db.select(
    db.budgetAccountsTable,
  )..where((t) => t.id.equals(id))).getSingle();

  /// The leaf category [name] on [accountId], or a new one: unit piece, price
  /// 1 (so the transaction quantity IS the amount in the account's currency).
  Future<String> _category(
    String name,
    String accountId, {
    required bool income,
    required List<String> created,
  }) async {
    final rows = await (db.select(db.budgetCategoriesTable)
          ..where((c) => c.name.equals(name))
          ..where((c) => c.accountUseId.equals(accountId)))
        .get();
    for (final c in rows) {
      final kids = await (db.select(
        db.budgetCategoriesTable,
      )..where((k) => k.parentId.equals(c.id))).get();
      if (kids.isEmpty) return c.id;
    }
    final id = await budget.saveCategory(
      CategoryInput(
        name: name,
        isIncome: income,
        unit: BudgetUnit.piece,
        price: 1,
        accountUseId: accountId,
      ),
    );
    created.add(id);
    return id;
  }
}

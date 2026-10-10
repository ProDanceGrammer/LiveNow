import 'package:drift/drift.dart' show Variable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart' show StateProvider;

import '../core/time_codec.dart';
import '../data/database.dart';
import '../domain/budget_rules.dart';
import '../domain/budget_service.dart';
import 'providers.dart';

final budgetServiceProvider = Provider<BudgetService>(
  (ref) => BudgetService(ref.watch(databaseProvider)),
);

final budgetAccountsProvider = StreamProvider.autoDispose<List<BudgetAccount>>((
  ref,
) {
  final db = ref.watch(databaseProvider);
  return db.select(db.budgetAccountsTable).watch();
});

final budgetCategoriesProvider =
    StreamProvider.autoDispose<List<BudgetCategory>>((ref) {
      final db = ref.watch(databaseProvider);
      return db.select(db.budgetCategoriesTable).watch();
    });

final budgetSettingsProvider = StreamProvider.autoDispose<BudgetSettings>((
  ref,
) {
  final db = ref.watch(databaseProvider);
  return db
      .select(db.budgetSettingsTable)
      .watch()
      .map(
        (rows) => BudgetService.settingsFromMap({
          for (final r in rows) r.key: r.value,
        }),
      );
});

/// A transaction row plus what the lists need from its action. [date] is the
/// EFFECTIVE date: the action's start while linked, else the row's own date.
class BudgetTxItem {
  const BudgetTxItem({required this.row, required this.date, this.actionName});

  final BudgetTransaction row;
  final DateTime date;
  final String? actionName;

  BudgetTx toRules() => BudgetTx(
    id: row.id,
    date: date,
    categoryId: row.categoryId,
    actionId: row.actionId,
    quantity: row.quantity,
    unitPrice: row.unitPrice,
    isIncome: row.isIncome,
    isAmount: row.isAmount,
    accountCountId: row.accountCountId,
    accountUseId: row.accountUseId,
    rateCount: row.rateCount,
    rateInteract: row.rateInteract,
  );
}

/// Every transaction with its live effective date, newest first.
final budgetTransactionsProvider =
    StreamProvider.autoDispose<List<BudgetTxItem>>((ref) {
      final db = ref.watch(databaseProvider);
      return db
          .customSelect(
            'SELECT t.*, a.start_at AS action_start, a.name AS action_name '
            'FROM budget_transactions t '
            'LEFT JOIN actions a ON a.id = t.action_id '
            'ORDER BY COALESCE(a.start_at, t.occurred_at) DESC',
            variables: const <Variable>[],
            readsFrom: {db.budgetTransactionsTable, db.actionsTable},
          )
          .watch()
          .map(
            (rows) => [
              for (final r in rows)
                BudgetTxItem(
                  row: db.budgetTransactionsTable.map(r.data),
                  date:
                      dateTimeFromDb(r.read<String?>('action_start')) ??
                      dateTimeFromDb(r.read<String>('occurred_at'))!,
                  actionName: r.read<String?>('action_name'),
                ),
            ],
          );
    });

/// The "as of" day of the period controls; null = today.
final budgetAsOfProvider = StateProvider<DateTime?>((ref) => null);

BudgetCat budgetCatFromRow(BudgetCategory c) => BudgetCat(
  id: c.id,
  name: c.name,
  isIncome: c.isIncome,
  oneTime: c.oneTime,
  unit: BudgetUnit.fromDb(c.unit),
  endDate: dateTimeFromDb(c.endDate),
  price: c.price,
  percent: c.percent,
  frequencyMonths: c.frequencyMonths,
  unitsPerMonth: c.unitsPerMonth,
  parentId: c.parentId,
  countPercentOfId: c.countPercentOfId,
  accountCountId: c.accountCountId,
  accountUseId: c.accountUseId,
);

BudgetAcct budgetAcctFromRow(BudgetAccount a) => BudgetAcct(
  id: a.id,
  currency: a.currency,
  rateToBase: a.rateToBase,
  openingBalance: a.openingBalance,
);

/// Everything the Budget screens show, computed live (and once a minute).
class BudgetView {
  const BudgetView({
    required this.settings,
    required this.period,
    required this.categories,
    required this.accounts,
    required this.transactions,
    required this.snapshot,
    required this.balances,
    required this.upcomingAction,
  });

  final BudgetSettings settings;
  final BudgetPeriod period;
  final List<BudgetCategory> categories;
  final List<BudgetAccount> accounts;
  final List<BudgetTxItem> transactions;
  final BudgetSnapshot snapshot;
  final Map<String, AccountBalance> balances;

  /// category id -> action of its nearest future transaction.
  final Map<String, String> upcomingAction;

  Map<String, BudgetCategory> get categoryById => {
    for (final c in categories) c.id: c,
  };
  Map<String, BudgetAccount> get accountById => {
    for (final a in accounts) a.id: a,
  };
}

final budgetViewProvider = Provider.autoDispose<AsyncValue<BudgetView>>((ref) {
  ref.watch(minuteTickProvider);
  final settings = ref.watch(budgetSettingsProvider);
  final cats = ref.watch(budgetCategoriesProvider);
  final accts = ref.watch(budgetAccountsProvider);
  final txs = ref.watch(budgetTransactionsProvider);
  final asOf = ref.watch(budgetAsOfProvider);

  for (final v in [settings, cats, accts, txs]) {
    if (v.hasError) return AsyncValue.error(v.error!, v.stackTrace!);
  }
  if (!settings.hasValue ||
      !cats.hasValue ||
      !accts.hasValue ||
      !txs.hasValue) {
    return const AsyncValue.loading();
  }

  final now = DateTime.now().toUtc();
  final period = BudgetPeriod(
    asOf: asOf ?? now,
    months: settings.requireValue.periodMonths,
  );
  final ruleCats = [for (final c in cats.requireValue) budgetCatFromRow(c)];
  final ruleAccts = [for (final a in accts.requireValue) budgetAcctFromRow(a)];
  final ruleTxs = [for (final t in txs.requireValue) t.toRules()];
  return AsyncValue.data(
    BudgetView(
      settings: settings.requireValue,
      period: period,
      categories: cats.requireValue,
      accounts: accts.requireValue,
      transactions: txs.requireValue,
      snapshot: computeBudget(
        categories: ruleCats,
        accounts: ruleAccts,
        transactions: ruleTxs,
        period: period,
      ),
      balances: computeBalances(
        accounts: ruleAccts,
        transactions: ruleTxs,
        now: now,
      ),
      upcomingAction: upcomingActionByCategory(
        categories: ruleCats,
        transactions: ruleTxs,
        now: now,
      ),
    ),
  );
});

/// "Urgency to Keep in Balance" per budget category: the urgency of the action
/// of its nearest future transaction (blank when none / unlinked).
final budgetCategoryUrgencyProvider = Provider.autoDispose<Map<String, double>>(
  (ref) {
    final view = ref.watch(budgetViewProvider).value;
    final urgency = ref.watch(actionUrgencyProvider);
    if (view == null) return const {};
    return {
      for (final e in view.upcomingAction.entries)
        if (urgency[e.value] != null) e.key: urgency[e.value]!,
    };
  },
);

/// The transactions linked to one action (for the action editor).
final actionBudgetTransactionsProvider = Provider.autoDispose
    .family<List<BudgetTxItem>, String>((ref, actionId) {
      final all = ref.watch(budgetTransactionsProvider).value ?? const [];
      return [
        for (final t in all)
          if (t.row.actionId == actionId) t,
      ];
    });

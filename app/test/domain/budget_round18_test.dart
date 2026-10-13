import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/budget_rules.dart';
import 'package:livenow/domain/budget_service.dart';
import 'package:livenow/domain/budget_tx_view_rules.dart';

void main() {
  // 1 EUR = 40 TRY = 1.1 USD.
  const accounts = {
    'eur': BudgetAcct(id: 'eur', currency: 'EUR', rateToBase: 1),
    'try': BudgetAcct(id: 'try', currency: 'TRY', rateToBase: 40),
    'usd': BudgetAcct(id: 'usd', currency: 'USD', rateToBase: 1.1),
  };

  BudgetTx tx({
    double qty = 2,
    double price = 100,
    bool income = false,
    String? count = 'try',
    String? use = 'usd',
    double? rateCount,
    double? rateInteract,
  }) => BudgetTx(
    id: 't',
    date: DateTime.utc(2026, 10, 1),
    quantity: qty,
    unitPrice: price,
    isIncome: income,
    accountCountId: count,
    accountUseId: use,
    rateCount: rateCount,
    rateInteract: rateInteract,
  );

  group('transaction amounts in three currencies', () {
    test('expense: counting, interactional and main', () {
      final a = transactionAmounts(tx(), accounts);
      expect(a.count, -200); // 2 x 100 TRY
      expect(a.base, -5); // 200 / 40 EUR
      expect(a.interact, -5.5); // 200 TRY -> USD via 1.1 / 40
    });

    test('the transaction\'s own snapshot rates win over the account', () {
      final a = transactionAmounts(tx(rateCount: 50, rateInteract: 2), accounts);
      expect(a.base, -4); // 200 / 50
      expect(a.interact, -8); // 200 * 2 / 50
    });

    test('income is positive; no use account = no interactional amount', () {
      final a = transactionAmounts(tx(income: true, use: null), accounts);
      expect(a.count, 200);
      expect(a.base, 5);
      expect(a.interact, isNull);
    });

    test('a missing rate leaves the main amount null, never NaN', () {
      final a = transactionAmounts(tx(count: null), accounts);
      expect(a.base, isNull);
      expect(a.count, -200);
    });
  });

  group('grouping', () {
    TxRowView row(
      String id, {
      String? action,
      String? category,
      String? account,
    }) => TxRowView(
      id: id,
      name: id,
      categoryId: category,
      categoryName: category ?? '',
      accountId: account,
      actionName: action ?? '',
      linked: action != null,
      actionId: action,
      date: DateTime.utc(2026, 10, 1),
      amount: -1,
    );

    final rows = [
      row('1', action: 'a', category: 'c1', account: 'x'),
      row('2', category: 'c2', account: 'y'),
      row('3', action: 'b', category: 'c1', account: 'x'),
      row('4', action: 'a', category: 'c2'),
    ];

    test('by action: first appearance order, "no action" last', () {
      final g = groupTransactionRows(rows, TxGroupBy.action);
      expect([for (final x in g) x.key], ['a', 'b', '']);
      expect(g.first.ids, ['1', '4']);
      expect(g.last.title, 'No action');
      expect(g.last.ids, ['2']);
    });

    test('by category and by account', () {
      final c = groupTransactionRows(rows, TxGroupBy.category);
      expect([for (final x in c) x.key], ['c1', 'c2']);
      final a = groupTransactionRows(
        rows,
        TxGroupBy.account,
        accountName: (id) => 'acc $id',
      );
      expect([for (final x in a) x.title], ['acc x', 'acc y', 'No account']);
    });

    test('none = one untitled group; nothing = no groups', () {
      final g = groupTransactionRows(rows, TxGroupBy.none);
      expect(g, hasLength(1));
      expect(g.single.ids, ['1', '2', '3', '4']);
      expect(groupTransactionRows(const [], TxGroupBy.none), isEmpty);
    });
  });

  test('totals add per currency and count what has no rate', () {
    final t = TxTotals()
      ..add(
        (count: -200.0, interact: -5.5, base: -5.0),
        countCurrency: 'TRY',
        interactCurrency: 'USD',
      )
      ..add(
        (count: -50.0, interact: null, base: null),
        countCurrency: 'XXX',
      );
    expect(t.counting, {'TRY': -200.0, 'XXX': -50.0});
    expect(t.interact, {'USD': -5.5});
    expect(t.base, -5);
    expect(t.noBase, 1);
    expect(t.count, 2);
  });

  test('the urgency switch is saved with the other Budget settings', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final service = BudgetService(db);
    expect((await service.settings()).showUrgency, isFalse); // off by default
    await service.saveSettings(const BudgetSettings(showUrgency: true));
    expect((await service.settings()).showUrgency, isTrue);
    await service.saveSettings(const BudgetSettings());
    expect((await service.settings()).showUrgency, isFalse);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/domain/budget_account_view.dart';
import 'package:livenow/domain/budget_category_view.dart';
import 'package:livenow/domain/budget_tx_view_rules.dart';

/// Round 19: account sorting + main balance, category level folding, the new
/// transaction filters (chosen actions, "all but" categories) and the totals.
void main() {
  group('accounts', () {
    test('main balance = balance / rate; no usable rate = null, never NaN', () {
      expect(accountMainBalance(400, 40), 10);
      expect(accountMainBalance(5, 0), isNull);
      expect(accountMainBalance(5, -1), isNull);
    });

    AccountSortInput a(String name, double rate, double balance, {String? type}) =>
        AccountSortInput(
          id: name,
          name: name,
          type: type,
          rate: rate,
          balance: balance,
          mainBalance: accountMainBalance(balance, rate),
        );

    test('default: biggest main balance first, unknown last', () {
      final out = sortAccounts([
        a('Lira', 40, 400), // 10
        a('Euro', 1, 80), // 80
        a('Broken', 0, 1000), // unknown
        a('Dollar', 2, 50), // 25
      ], kDefaultAccountSort);
      expect([for (final x in out) x.name], ['Euro', 'Dollar', 'Lira', 'Broken']);
    });

    test('unknown stays last even when ascending', () {
      final out = sortAccounts([
        a('Broken', 0, 1000),
        a('Lira', 40, 400),
        a('Euro', 1, 80),
      ], const [AccountSortKey(AccountSortField.mainBalance)]);
      expect([for (final x in out) x.name], ['Lira', 'Euro', 'Broken']);
    });

    test('waterfall: type, then name; no type goes last', () {
      final out = sortAccounts([
        a('B', 1, 1),
        a('A', 1, 1, type: 'cash'),
        a('C', 1, 1, type: 'card'),
        a('D', 1, 1, type: 'cash'),
      ], const [
        AccountSortKey(AccountSortField.type),
        AccountSortKey(AccountSortField.name, ascending: false),
      ]);
      expect([for (final x in out) x.name], ['C', 'D', 'A', 'B']);
    });
  });

  group('category levels', () {
    const cats = [
      CategoryInfo('a', 'A', null),
      CategoryInfo('a1', 'A1', 'a'),
      CategoryInfo('a11', 'A11', 'a1'),
      CategoryInfo('a111', 'A111', 'a11'),
      CategoryInfo('b', 'B', null),
      CategoryInfo('b1', 'B1', 'b'),
      CategoryInfo('solo', 'Solo', null),
    ];

    test('null opens everything', () {
      expect(collapsedForLevel(cats, null), isEmpty);
    });

    test('level 1 = parents only: every group folded', () {
      expect(collapsedForLevel(cats, 1), {'a', 'a1', 'a11', 'b'});
    });

    test('level 2 keeps the top groups open, folds the groups below', () {
      expect(collapsedForLevel(cats, 2), {'a1', 'a11'});
    });

    test('level 3 and 4', () {
      expect(collapsedForLevel(cats, 3), {'a11'});
      expect(collapsedForLevel(cats, 4), isEmpty);
    });

    test('a parent loop cannot hang it', () {
      const loop = [
        CategoryInfo('x', 'X', 'y'),
        CategoryInfo('y', 'Y', 'x'),
      ];
      expect(() => collapsedForLevel(loop, 1), returnsNormally);
    });

    test('the folded set really hides rows through arrangeCategoryRows', () {
      final rows = arrangeCategoryRows(
        categories: cats,
        plan: const {},
        fact: const {},
        collapsed: collapsedForLevel(cats, 1),
      );
      expect([for (final r in rows) r.id], ['a', 'b', 'solo']);
    });
  });

  group('transaction filters', () {
    TxRowView t(String id, {String? cat, String? action, double amount = -1}) =>
        TxRowView(
          id: id,
          name: id,
          categoryId: cat,
          categoryName: cat ?? '',
          accountId: null,
          actionName: action ?? '',
          linked: action != null,
          actionId: action,
          date: DateTime.utc(2026, 1, 1),
          amount: amount,
        );

    final rows = [
      t('t1', cat: 'food', action: 'a1'),
      t('t2', cat: 'food', action: 'a2'),
      t('t3', cat: 'car'),
      t('t4', cat: 'car', action: 'a1'),
    ];
    final parents = categoryWithDescendants({
      'food': null,
      'car': null,
    });

    List<String> ids(TxFilters f) => arrangeTransactionIds(
      rows: rows,
      sort: const [],
      filters: f,
      descendants: parents,
    );

    test('chosen actions keep only their transactions', () {
      expect(ids(const TxFilters(actionIds: {'a1'})), ['t1', 't4']);
    });

    test('actions combine with the linked / unlinked switch', () {
      expect(
        ids(const TxFilters(actionIds: {'a1', 'a2'}, action: TxActionLink.unlinked)),
        isEmpty,
      );
    });

    test('"all but" leaves out the chosen categories', () {
      expect(
        ids(const TxFilters(categoryIds: {'food'}, excludeCategories: true)),
        ['t3', 't4'],
      );
      expect(ids(const TxFilters(categoryIds: {'food'})), ['t1', 't2']);
    });

    test('both new filters count as active', () {
      expect(const TxFilters(actionIds: {'a'}).active, isTrue);
      expect(const TxFilters().active, isFalse);
    });
  });

  group('totals and figures', () {
    test('income and expense are split by sign in the main currency', () {
      final totals = TxTotals()
        ..add(
          (count: -10.0, interact: null, base: -10.0),
          countCurrency: 'EUR',
        )
        ..add(
          (count: 25.0, interact: null, base: 25.0),
          countCurrency: 'EUR',
        )
        ..add(
          (count: 5.0, interact: null, base: null),
          countCurrency: 'XXX',
        );
      expect(totals.income, 25);
      expect(totals.expense, -10);
      expect(totals.base, 15);
      expect(totals.noBase, 1);
    });

    test('figure categories: leaves of the transactions + leaves under a chosen group', () {
      const parentOf = {'g': null, 'l1': 'g', 'l2': 'g', 'solo': null};
      final withGroup = figureCategoryIds(
        txCategoryIds: ['l1'],
        filters: const TxFilters(categoryIds: {'g'}),
        parentOf: parentOf,
      );
      expect(withGroup, {'l1', 'l2'});
      final excluded = figureCategoryIds(
        txCategoryIds: ['solo'],
        filters: const TxFilters(categoryIds: {'g'}, excludeCategories: true),
        parentOf: parentOf,
      );
      expect(excluded, {'solo'});
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/domain/budget_tx_view_rules.dart';
import 'package:livenow/domain/date_range_filter.dart';
import 'package:livenow/domain/postpone_rules.dart';

TxRowView tx(
  String id, {
  String name = '',
  String? cat,
  String catName = 'Cat',
  String? account,
  String action = '',
  DateTime? date,
  double amount = -10,
}) => TxRowView(
  id: id,
  name: name,
  categoryId: cat,
  categoryName: catName,
  accountId: account,
  actionName: action,
  linked: action.isNotEmpty,
  date: date ?? DateTime.utc(2026, 10, 10, 12),
  amount: amount,
);

List<String> run(
  List<TxRowView> rows, {
  List<TxSortKey> sort = const [],
  TxFilters filters = const TxFilters(),
  String query = '',
  TxSearchFlags flags = const TxSearchFlags(),
  Map<String, Set<String>> descendants = const {},
}) => arrangeTransactionIds(
  rows: rows,
  sort: sort,
  filters: filters,
  query: query,
  flags: flags,
  descendants: descendants,
);

void main() {
  setUpAll(initPostponeTimeZoneData);

  test(
    'categoryWithDescendants includes the whole subtree and survives loops',
    () {
      final d = categoryWithDescendants({
        'a': null,
        'b': 'a',
        'c': 'b',
        'x': 'y',
        'y': 'x',
      });
      expect(d['a'], {'a', 'b', 'c'});
      expect(d['b'], {'b', 'c'});
      expect(d['c'], {'c'});
      expect(d['x'], containsAll(['x', 'y'])); // a loop does not hang
    },
  );

  test('category filter takes the sub-categories of a chosen group', () {
    final rows = [
      tx('1', cat: 'food'),
      tx('2', cat: 'cafe'),
      tx('3', cat: 'fuel'),
      tx('4'),
    ];
    final desc = categoryWithDescendants({
      'food': null,
      'cafe': 'food',
      'fuel': null,
    });
    expect(
      run(
        rows,
        filters: const TxFilters(categoryIds: {'food'}),
        descendants: desc,
      ),
      ['1', '2'],
    );
    // Without descendants data the chosen id still matches itself.
    expect(run(rows, filters: const TxFilters(categoryIds: {'fuel'})), ['3']);
  });

  test('account and action-link filters', () {
    final rows = [
      tx('1', account: 'eur', action: 'Shop'),
      tx('2', account: 'try'),
      tx('3', action: 'Walk'),
    ];
    expect(run(rows, filters: const TxFilters(accountIds: {'eur'})), ['1']);
    expect(run(rows, filters: const TxFilters(action: TxActionLink.linked)), [
      '1',
      '3',
    ]);
    expect(run(rows, filters: const TxFilters(action: TxActionLink.unlinked)), [
      '2',
    ]);
  });

  test('date range filters on the live date, inclusive of whole days', () {
    DateTime d(int day, int h) => DateTime.utc(2026, 10, day, h);
    final rows = [
      tx('1', date: d(9, 12)),
      tx('2', date: d(10, 12)),
      tx('3', date: d(11, 12)),
    ];
    final r = TxFilters(
      dateRange: DateRangeFilter(
        from: DateRangeFilter.dayStart(DateTime(2026, 10, 10)),
        until: DateRangeFilter.dayStart(DateTime(2026, 10, 10)),
      ),
    );
    expect(run(rows, filters: r), ['2']);
    expect(
      run(
        rows,
        filters: TxFilters(
          dateRange: DateRangeFilter(
            from: DateRangeFilter.dayStart(DateTime(2026, 10, 10)),
          ),
        ),
      ),
      ['2', '3'],
    );
  });

  test('search per flag, Cyrillic is case-insensitive', () {
    final rows = [
      tx('1', name: 'Молоко', catName: 'Їжа', action: ''),
      tx('2', name: '', catName: 'Транспорт', action: 'Поїздка'),
    ];
    expect(run(rows, query: 'МОЛОК'), ['1']);
    expect(run(rows, query: 'їжа'), ['1']);
    expect(run(rows, query: 'поїзд'), ['2']);
    expect(
      run(rows, query: 'їжа', flags: const TxSearchFlags(category: false)),
      isEmpty,
    );
  });

  test(
    'waterfall sort: first key decides, ties fall to the next, then to order',
    () {
      final rows = [
        tx('a', name: 'b', amount: 5, date: DateTime.utc(2026, 10, 1)),
        tx('b', name: 'a', amount: 5, date: DateTime.utc(2026, 10, 2)),
        tx('c', name: 'c', amount: 9, date: DateTime.utc(2026, 10, 3)),
        tx('d', name: 'c', amount: 5, date: DateTime.utc(2026, 10, 3)),
      ];
      expect(
        run(
          rows,
          sort: const [
            TxSortKey(TxSortField.amount, ascending: false),
            TxSortKey(TxSortField.name),
          ],
        ),
        ['c', 'b', 'a', 'd'],
      );
      expect(run(rows, sort: kDefaultTxSort), [
        'c',
        'd',
        'b',
        'a',
      ]); // newest first, ties keep order
      expect(run(rows, sort: const []), ['a', 'b', 'c', 'd']);
    },
  );
}

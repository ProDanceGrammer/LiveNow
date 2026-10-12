import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/queries.dart';
import 'package:livenow/domain/all_actions_view_rules.dart';
import 'package:livenow/domain/date_range_filter.dart';
import 'package:livenow/domain/postpone_rules.dart';

ActionListItem _a(
  String id,
  String name, {
  DateTime? start,
  DateTime? end,
  bool done = false,
  DateTime? updated,
  DateTime? created,
}) => ActionListItem(
  id: id,
  name: name,
  done: done,
  startAt: start,
  endAt: end,
  isAllDay: false,
  updatedAt: updated,
  createdAt: created,
);

List<String> _ids(List<ActionListItem> l) => [for (final a in l) a.id];

void main() {
  final t0 = DateTime.utc(2026, 1, 1, 10);
  DateTime h(int n) => t0.add(Duration(hours: n));

  test('default sort: last edited first, rows without it last', () {
    final items = [
      _a('a', 'a', updated: h(1)),
      _a('b', 'b', updated: h(5)),
      _a('c', 'c'),
      _a('d', 'd', updated: h(3)),
    ];
    expect(_ids(sortActions(items, kDefaultAllActionsSort)), [
      'b',
      'd',
      'a',
      'c',
    ]);
  });

  test('name sort is case-insensitive and Cyrillic-safe, desc reverses', () {
    final items = [_a('1', 'Яблуко'), _a('2', 'апельсин'), _a('3', 'Банан')];
    expect(_ids(sortActions(items, [const SortKey(SortField.name)])), [
      '2',
      '3',
      '1',
    ]);
    expect(
      _ids(
        sortActions(items, [const SortKey(SortField.name, ascending: false)]),
      ),
      ['1', '3', '2'],
    );
  });

  test('waterfall: later keys break ties, equal rows stay stable', () {
    final items = [
      _a('1', 'x', start: h(2)),
      _a('2', 'x', start: h(1)),
      _a('3', 'a', start: h(9)),
      _a('4', 'x', start: h(1)),
    ];
    final sorted = sortActions(items, [
      const SortKey(SortField.name),
      const SortKey(SortField.start),
    ]);
    // name asc, then start asc; '2' and '4' tie on both -> incoming order.
    expect(_ids(sorted), ['3', '2', '4', '1']);
  });

  test('duration, urgency and done sorting', () {
    final items = [
      _a('long', 'l', start: h(0), end: h(3)),
      _a('short', 's', start: h(0), end: h(1)),
      _a('done', 'd', done: true),
      _a('open', 'o'),
    ];
    // Unscheduled rows count as the 60-minute default: they tie with 'short'.
    expect(_ids(sortActions(items, [const SortKey(SortField.duration)])), [
      'short',
      'done',
      'open',
      'long',
    ]);
    final u = {'long': 5.0, 'short': 90.0};
    expect(
      _ids(
        sortActions(items, [
          const SortKey(SortField.urgency, ascending: false),
        ], urgency: u),
      ),
      ['short', 'long', 'done', 'open'],
    );
    expect(
      _ids(sortActions(items, [const SortKey(SortField.done)])).last,
      'done',
    );
  });

  test('filters: name, duration, urgency', () {
    final items = [
      _a('1', 'Write report', start: h(0), end: h(2)),
      _a('2', 'Walk', start: h(0), end: h(1)),
      _a('3', 'Write mail', start: h(0), end: h(1)),
    ];
    List<String> run(AllActionsFilters f, {Map<String, double> u = const {}}) =>
        _ids(
          arrangeActions(items: items, sort: const [], filters: f, urgency: u),
        );
    expect(run(const AllActionsFilters(nameText: 'WRITE')), ['1', '3']);
    expect(run(const AllActionsFilters(minMinutes: 90)), ['1']);
    expect(run(const AllActionsFilters(maxMinutes: 60)), ['2', '3']);
    expect(run(const AllActionsFilters(minUrgency: 10), u: {'1': 50, '2': 5}), [
      '1',
    ]);
  });

  test('filters: growth directions any/all and previous/next', () {
    final items = [_a('1', 'one'), _a('2', 'two'), _a('3', 'three')];
    final links = AllActionsLinkData(
      metricIdsByAction: {
        '1': {'m1'},
        '2': {'m1', 'm2'},
      },
      predecessors: {
        '2': {'1'},
        '3': {'2'},
      },
      successors: {
        '1': {'2'},
        '2': {'3'},
      },
    );
    List<String> run(AllActionsFilters f) => _ids(
      arrangeActions(items: items, sort: const [], filters: f, links: links),
    );
    expect(run(const AllActionsFilters(metricIds: {'m1', 'm2'})), ['1', '2']);
    expect(
      run(const AllActionsFilters(metricIds: {'m1', 'm2'}, allMetrics: true)),
      ['2'],
    );
    expect(
      run(const AllActionsFilters(previous: LinkFilter(mode: LinkMode.none))),
      ['1'],
    );
    expect(run(const AllActionsFilters(next: LinkFilter(mode: LinkMode.has))), [
      '1',
      '2',
    ]);
    expect(
      run(
        const AllActionsFilters(
          previous: LinkFilter(mode: LinkMode.linkedTo, actionId: '2'),
        ),
      ),
      ['3'],
    );
  });

  test('search flags: name, notes ids, direction names', () {
    final items = [_a('1', 'Молоко'), _a('2', 'Other'), _a('3', 'Third')];
    final links = AllActionsLinkData(
      metricIdsByAction: {
        '3': {'m1'},
      },
      metricNamesById: {'m1': 'здоров'},
    );
    List<String> run(String q, SearchFlags f, {Set<String>? notes}) => _ids(
      arrangeActions(
        items: items,
        sort: const [],
        query: q,
        flags: f,
        links: links,
        notesMatches: notes,
      ),
    );
    expect(run('МОЛ', const SearchFlags()), ['1']);
    expect(
      run('молоко', const SearchFlags(name: false, notes: true), notes: {'2'}),
      ['2'],
    );
    expect(run('молоко', const SearchFlags(name: false)), isEmpty);
    expect(run('ЗДОРОВ', const SearchFlags(name: false, directions: true)), [
      '3',
    ]);
    expect(
      run(
        'other',
        const SearchFlags(notes: true, directions: true),
        notes: {'3'},
      ),
      ['2', '3'],
    );
  });

  test(
    'date range filters on the START day; unscheduled actions never match',
    () {
      initPostponeTimeZoneData();
      DateTime day(int d) => DateRangeFilter.dayStart(DateTime(2026, 10, d));
      final items = [
        _a('before', 'x', start: DateTime.utc(2026, 10, 9, 12)),
        _a('inside', 'x', start: DateTime.utc(2026, 10, 10, 12)),
        _a(
          'late',
          'x',
          start: DateTime.utc(2026, 10, 10, 20, 30),
        ), // 23:30 local
        _a('after', 'x', start: DateTime.utc(2026, 10, 11, 12)),
        _a('none', 'x'),
      ];
      List<String> run(DateRangeFilter r) => _ids(
        arrangeActions(
          items: items,
          sort: const [],
          filters: AllActionsFilters(dateRange: r),
        ),
      );
      expect(run(DateRangeFilter(from: day(10), until: day(10))), [
        'inside',
        'late',
      ]);
      expect(run(DateRangeFilter(from: day(10))), ['inside', 'late', 'after']);
      expect(run(DateRangeFilter(until: day(9))), ['before']);
      expect(const AllActionsFilters().active, isFalse);
      expect(
        AllActionsFilters(dateRange: DateRangeFilter(from: day(10))).active,
        isTrue,
      );
    },
  );
}

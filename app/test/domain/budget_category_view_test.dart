import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/domain/budget_category_view.dart';

void main() {
  // Food (group) > Milk, Bread ; Rent ; Fun (group) > Cinema
  const cats = [
    CategoryInfo('food', 'Food', null),
    CategoryInfo('milk', 'Milk', 'food'),
    CategoryInfo('bread', 'Bread', 'food'),
    CategoryInfo('rent', 'Rent', null),
    CategoryInfo('fun', 'Fun', null),
    CategoryInfo('cinema', 'Cinema', 'fun'),
  ];
  // Signed base totals: expenses are negative; groups carry their children.
  const plan = {
    'milk': -30.0,
    'bread': -50.0,
    'food': -80.0,
    'rent': -500.0,
    'cinema': -20.0,
    'fun': -20.0,
  };
  const fact = {
    'milk': -45.0,
    'bread': -10.0,
    'food': -55.0,
    'rent': -500.0,
    'cinema': 0.0,
    'fun': 0.0,
  };

  List<String> ids(List<CategoryRow> rows) => [for (final r in rows) r.id];

  List<CategoryRow> arrange({
    List<CategorySortKey> sort = kDefaultCategorySort,
    String query = '',
    Set<String> collapsed = const {},
    bool flat = false,
    Map<String, double> urgency = const {},
  }) => arrangeCategoryRows(
    categories: cats,
    plan: plan,
    fact: fact,
    urgency: urgency,
    sort: sort,
    query: query,
    collapsed: collapsed,
    flat: flat,
  );

  test('tree by name: groups carry their children, indented', () {
    final rows = arrange();
    expect(ids(rows), ['food', 'bread', 'milk', 'fun', 'cinema', 'rent']);
    expect([for (final r in rows) r.depth], [0, 1, 1, 0, 1, 0]);
    expect(rows.first.hasChildren, isTrue);
    expect(rows.last.hasChildren, isFalse);
  });

  test('sort by Plan descending: biggest first, siblings inside a group', () {
    final rows = arrange(
      sort: const [CategorySortKey(CategorySortField.plan, ascending: false)],
    );
    // Top level by size: Rent 500, Food 80, Fun 20; inside Food: Bread, Milk.
    expect(ids(rows), ['rent', 'food', 'bread', 'milk', 'fun', 'cinema']);
  });

  test('sort by Fact ascending compares by size, not by sign', () {
    final rows = arrange(
      sort: const [CategorySortKey(CategorySortField.fact)],
    );
    // Fun 0 < Food 55 < Rent 500; inside Food: Bread 10 < Milk 45.
    expect(ids(rows), ['fun', 'cinema', 'food', 'bread', 'milk', 'rent']);
  });

  test('missing urgency goes last in both directions; ties fall back to name', () {
    const urgency = {'rent': 300.0, 'food': 300.0};
    final up = arrange(
      sort: const [CategorySortKey(CategorySortField.urgency)],
      urgency: urgency,
    );
    expect(ids(up).take(3), ['food', 'bread', 'milk']); // food/rent tie: name
    final down = arrange(
      sort: const [CategorySortKey(CategorySortField.urgency, ascending: false)],
      urgency: const {'rent': 300.0},
    );
    expect(ids(down).first, 'rent');
    expect(ids(down).last, 'cinema'); // no urgency anywhere else: by name
  });

  test('a folded group hides its children but keeps its own row', () {
    final rows = arrange(collapsed: {'food'});
    expect(ids(rows), ['food', 'fun', 'cinema', 'rent']);
    expect(rows.first.collapsed, isTrue);
  });

  test('search keeps the ancestors of matches and ignores folding', () {
    final rows = arrange(query: 'milk', collapsed: {'food'});
    expect(ids(rows), ['food', 'milk']);
    expect([for (final r in rows) r.depth], [0, 1]);
    expect(rows.first.collapsed, isFalse);
  });

  test('a matching group also shows its children', () {
    expect(ids(arrange(query: 'fun')), ['fun', 'cinema']);
    expect(ids(arrange(query: 'nothing here')), isEmpty);
  });

  test('flat mode lists only categories without children, by the sort keys', () {
    final rows = arrange(
      flat: true,
      sort: const [CategorySortKey(CategorySortField.plan, ascending: false)],
    );
    expect(ids(rows), ['rent', 'bread', 'milk', 'cinema']);
    expect(rows.every((r) => r.depth == 0 && !r.hasChildren), isTrue);
    expect(ids(arrange(flat: true, query: 'ci')), ['cinema']);
  });

  test('an unknown parent counts as top level; a loop cannot hang it', () {
    final rows = arrangeCategoryRows(
      categories: const [
        CategoryInfo('a', 'A', 'gone'),
        CategoryInfo('b', 'B', 'c'),
        CategoryInfo('c', 'C', 'b'),
      ],
      plan: const {},
      fact: const {},
    );
    expect(ids(rows), ['a']); // b and c only point at each other
  });

  test('empty input gives no rows', () {
    expect(
      arrangeCategoryRows(categories: const [], plan: const {}, fact: const {}),
      isEmpty,
    );
  });
}

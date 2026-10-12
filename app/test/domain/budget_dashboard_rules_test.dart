import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/domain/budget_rules.dart';
import 'package:livenow/domain/postpone_rules.dart';

BudgetCat cat(String id, String name, {String? parent, DateTime? end}) =>
    BudgetCat(id: id, name: name, parentId: parent, endDate: end);

void main() {
  setUpAll(initPostponeTimeZoneData);

  // Noon UTC = 15:00 Istanbul, the same day.
  final asOf = DateTime.utc(2026, 10, 12, 12);

  group('endedCategoryIds', () {
    test('a leaf ends the day AFTER its end date; the day itself is active', () {
      final ids = endedCategoryIds([
        cat('past', 'Past', end: DateTime.utc(2026, 9, 28, 12)),
        cat('today', 'Today', end: DateTime.utc(2026, 10, 12, 12)),
        cat('future', 'Future', end: DateTime.utc(2026, 10, 20, 12)),
        cat('open', 'Open'),
      ], asOf);
      expect(ids, {'past'});
    });

    test('a group is ended only when every leaf below it is', () {
      final past = DateTime.utc(2026, 9, 1, 12);
      final ids = endedCategoryIds([
        cat('g1', 'All gone'),
        cat('a', 'A', parent: 'g1', end: past),
        cat('b', 'B', parent: 'g1', end: past),
        cat('g2', 'Mixed'),
        cat('c', 'C', parent: 'g2', end: past),
        cat('d', 'D', parent: 'g2'),
        cat('g3', 'Deep'),
        cat('g3a', 'Deep child', parent: 'g3'),
        cat('g3x', 'Leaf', parent: 'g3a', end: past),
      ], asOf);
      expect(ids, containsAll({'g1', 'a', 'b', 'c', 'g3', 'g3a', 'g3x'}));
      expect(ids, isNot(contains('g2')));
      expect(ids, isNot(contains('d')));
    });
  });

  group('collapseSameNameLeaves', () {
    test('leaves named like their parent fold into it', () {
      final r = collapseSameNameLeaves([
        cat('p', 'Картопля'),
        cat('p1', 'Картопля', parent: 'p'),
        cat('p2', '🥔 картопля', parent: 'p'),
      ]);
      expect(r.show, {'p'});
      expect(r.hide, {'p1', 'p2'});
    });

    test('mixed names, nested groups or a differently named parent stay', () {
      final r = collapseSameNameLeaves([
        cat('v', 'Vegetables'),
        cat('v1', 'Potatoes', parent: 'v'),
        cat('v2', 'Potatoes', parent: 'v'), // parent has another name
        cat('m', 'Fruit'),
        cat('m1', 'Fruit', parent: 'm'),
        cat('m2', 'Apples', parent: 'm'), // mixed
        cat('n', 'Nested'),
        cat('n1', 'Nested', parent: 'n'),
        cat('n2', 'Other', parent: 'n1'), // n1 is a group, not a leaf
      ]);
      expect(r.show, isEmpty);
      expect(r.hide, isEmpty);
    });

    test('a single same-named leaf also folds', () {
      final r = collapseSameNameLeaves([
        cat('p', 'Bread'),
        cat('p1', 'Bread', parent: 'p'),
      ]);
      expect(r.show, {'p'});
      expect(r.hide, {'p1'});
    });
  });
}

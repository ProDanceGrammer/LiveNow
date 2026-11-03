import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/domain/ai/category_match.dart';
import 'package:livenow/domain/ai/category_resolver.dart';
import 'package:livenow/domain/budget_rules.dart';

CategoryCandidate leaf(
  String id,
  double? price, {
  String? count,
  String? use,
  List<CategoryVariant> variants = const [],
}) => CategoryCandidate(
  id: id,
  name: 'Молоко $id',
  parentId: 'g',
  parentName: 'Молоко (звичайне)',
  isAggregate: false,
  unit: BudgetUnit.kilogram,
  price: price,
  accountCountId: count,
  accountUseId: use,
  score: 0.8,
  fromAlias: false,
  variants: variants,
);

CategoryVariant variant(String id, double price, {String? use}) => CategoryVariant(
  id: id,
  name: 'Молоко',
  price: price,
  accountCountId: null,
  accountUseId: use,
);

void main() {
  group('findExistingMatch', () {
    test('same price and compatible accounts is the product', () {
      final m = findExistingMatch(
        [leaf('mis', 55), leaf('dost', 59, use: 'mono')],
        unitPrice: 59,
        useAccountId: 'mono',
      );
      expect(m, 'dost');
    });

    test('another price is not a match: the similar ones are only offered', () {
      expect(
        findExistingMatch([leaf('mis', 55), leaf('dost', 59)], unitPrice: 61.5, useAccountId: null),
        isNull,
      );
    });

    test('accounts that cannot be shared are not a match', () {
      expect(
        findExistingMatch([leaf('dost', 59, use: 'cash')], unitPrice: 59, useAccountId: 'mono'),
        isNull,
      );
      expect(
        findExistingMatch([leaf('dost', 59)], unitPrice: 59, useAccountId: 'mono'),
        'dost',
        reason: 'a category with no account of its own takes any',
      );
    });

    test('a wrapper is looked into through its variants', () {
      final wrapper = CategoryCandidate(
        id: 'w',
        name: 'Молоко Dost',
        parentId: 'g',
        parentName: 'Молоко (звичайне)',
        isAggregate: true,
        unit: BudgetUnit.kilogram,
        price: null,
        accountCountId: null,
        accountUseId: null,
        score: 0.9,
        fromAlias: false,
        variants: [variant('v55', 55), variant('v59', 59)],
      );
      expect(findExistingMatch([wrapper], unitPrice: 59, useAccountId: null), 'v59');
      expect(findExistingMatch([wrapper], unitPrice: 57, useAccountId: null), isNull);
    });

    test('a weighed line\'s derived unit price still matches the printed one', () {
      // 30.62 / 0.785 = 39.0064 for a printed 39.00
      expect(
        findExistingMatch([leaf('lemon', 39)], unitPrice: 30.62 / 0.785, useAccountId: null),
        'lemon',
      );
    });

    test('an unknown or invalid price matches nothing', () {
      expect(findExistingMatch([leaf('a', 59)], unitPrice: null, useAccountId: null), isNull);
      expect(findExistingMatch([leaf('a', 59)], unitPrice: 0, useAccountId: null), isNull);
      expect(findExistingMatch([leaf('a', null)], unitPrice: 59, useAccountId: null), isNull);
    });

    test('a group (aggregate without a price) never matches by itself', () {
      final group = CategoryCandidate(
        id: 'g',
        name: 'Продукти',
        parentId: null,
        parentName: null,
        isAggregate: true,
        unit: BudgetUnit.kilogram,
        price: 59,
        accountCountId: null,
        accountUseId: null,
        score: 0.5,
        fromAlias: false,
        variants: const [],
      );
      expect(findExistingMatch([group], unitPrice: 59, useAccountId: null), isNull);
    });
  });
}

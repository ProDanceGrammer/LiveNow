import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/ai/invariant_validator.dart';
import 'package:livenow/domain/postpone_rules.dart';

import 'ai_test_support.dart';

void main() {
  late AppDatabase db;
  late Seed seed;
  late InvariantValidator validator;

  setUpAll(initPostponeTimeZoneData);
  setUp(() {
    db = memoryDb();
    seed = Seed(db);
    validator = InvariantValidator(db);
  });
  tearDown(() => db.close());

  final when = DateTime.utc(2026, 10, 10, 12);

  PlannedTransaction tx(
    String? category, {
    String name = 'item',
    double quantity = 1,
    double amount = 10,
    double? rate = 40,
    bool isIncome = false,
    String? use,
  }) => PlannedTransaction(
    name: name,
    categoryId: category,
    quantity: quantity,
    amount: amount,
    date: when,
    rateCount: rate,
    rateInteract: rate,
    isIncome: isIncome,
    accountUseId: use,
  );

  Set<String> codes(ValidationResult r) => {for (final e in r.errors) e.code};

  test('I1 a transaction on an aggregate is refused, using the tree and planned moves', () async {
    final group = await seed.group('Фрукти');
    final leaf = await seed.leaf('Банани', price: 70, parentId: group);
    var r = await validator.validate(transactions: [tx(group), tx(leaf)]);
    expect(codes(r), {ValidationCode.aggregateTarget});
    expect(r.errors.single.index, 0);

    // The C5 wrapper in the same batch turns the old leaf into... a child.
    r = await validator.validate(
      transactions: [tx(leaf)],
      newCategories: [PlannedCategory(id: 'tmp-w', parentId: group)],
      moves: [PlannedMove('tmp-w', leaf)],
    );
    expect(codes(r), {ValidationCode.aggregateTarget});
  });

  test('I2 sum must match the total within 0.02', () async {
    final leaf = await seed.leaf('Банани', price: 70);
    final lines = [tx(leaf, amount: 99.95), tx(leaf, amount: 95.50)];
    var r = await validator.validate(transactions: lines, expectedTotal: 195.45);
    expect(r.ok, isTrue);
    r = await validator.validate(transactions: lines, expectedTotal: 195.46);
    expect(r.ok, isTrue); // 0.01 off: within tolerance
    r = await validator.validate(transactions: lines, expectedTotal: 200);
    expect(codes(r), {ValidationCode.sumMismatch});
    expect(r.errors.single.details['difference'], -4.55);
    expect(r.toJson()['ok'], isFalse);
  });

  test('I3 quantity, rates and category are required', () async {
    final leaf = await seed.leaf('Банани', price: 70);
    final r = await validator.validate(
      transactions: [
        tx(leaf, quantity: 0),
        tx(leaf, quantity: -1),
        tx(leaf, rate: null),
        tx(null),
        tx('no-such'),
        tx(leaf, quantity: -1, isIncome: true), // income may be negative
      ],
    );
    expect(r.errors.where((e) => e.index == 0).single.code, ValidationCode.badQuantity);
    expect(r.errors.where((e) => e.index == 1).single.code, ValidationCode.badQuantity);
    expect(r.errors.where((e) => e.index == 2).single.code, ValidationCode.missingRate);
    expect(r.errors.where((e) => e.index == 3).single.code, ValidationCode.missingCategory);
    expect(r.errors.where((e) => e.index == 4).single.code, ValidationCode.missingCategory);
    expect(r.errors.where((e) => e.index == 5), isEmpty);
  });

  test('I4 the category accounts must fit the payment method', () async {
    final card = await seed.account('Mono');
    final cash = await seed.account('Cash');
    final leaf = await seed.leaf('Хліб', price: 20, use: card);
    var r = await validator.validate(transactions: [tx(leaf, use: card)]);
    expect(r.ok, isTrue);
    r = await validator.validate(transactions: [tx(leaf, use: cash)]);
    expect(codes(r), {ValidationCode.accountIncompatible});
  });

  test('I6 a duplicate of an existing transaction is flagged unless skipped', () async {
    final leaf = await seed.leaf('Хліб', price: 20);
    await seed.budget.createTransaction(
      categoryId: leaf,
      name: 'item',
      date: when,
      quantity: 1,
    );
    var r = await validator.validate(transactions: [tx(leaf, amount: 20)]);
    expect(codes(r), {ValidationCode.duplicate});
    expect(r.errors.single.details['transaction_ids'], hasLength(1));
    r = await validator.validate(
      transactions: [
        PlannedTransaction(
          name: 'item',
          categoryId: leaf,
          quantity: 1,
          amount: 20,
          date: when,
          rateCount: 40,
          rateInteract: 40,
          checkDuplicate: false,
        ),
      ],
    );
    expect(r.ok, isTrue);
  });

  test('I7 any delete/overwrite needs explicit confirmation', () async {
    final r = await validator.validate(
      transactions: const [],
      destructiveOps: const [
        PlannedDestructiveOp('delete transaction X'),
        PlannedDestructiveOp('overwrite rate', confirmed: true),
      ],
    );
    expect(r.ok, isTrue);
    expect(r.canCommit, isFalse);
    expect(r.confirmations, hasLength(1));
    expect(r.confirmations.single.code, ValidationCode.needsConfirmation);
  });
}

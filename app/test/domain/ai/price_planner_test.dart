import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/ai/price_planner.dart';
import 'package:livenow/domain/budget_rules.dart';
import 'package:livenow/domain/budget_service.dart';
import 'package:livenow/domain/postpone_rules.dart';

import 'ai_test_support.dart';

void main() {
  late AppDatabase db;
  late Seed seed;
  late PricePlanner planner;
  late BudgetService budget;

  setUpAll(initPostponeTimeZoneData);
  setUp(() {
    db = memoryDb();
    seed = Seed(db);
    budget = seed.budget;
    planner = PricePlanner(db, budget);
  });
  tearDown(() => db.close());

  test('C4 same price and compatible accounts reuse the existing leaf', () async {
    final card = await seed.account('Mono');
    final leaf = await seed.leaf('🍏 Яблука', price: 99.95, use: card);
    final plan = await planner.plan(
      categoryId: leaf,
      newPrice: 99.95,
      accountUseId: card,
    );
    expect(plan.kind, PlanKind.reuseLeaf);
    expect(plan.leafId, leaf);
    expect(plan.createsCategories, isFalse);
  });

  test('C4 reuse also finds an old leaf of an existing aggregate', () async {
    final wrapper = await seed.group('🍏 Яблука');
    final old = await seed.leaf('🍏 Яблука', price: 159.95, parentId: wrapper);
    await seed.leaf('🍏 Яблука', price: 99.95, parentId: wrapper);
    final plan = await planner.plan(categoryId: wrapper, newPrice: 159.95);
    expect(plan.kind, PlanKind.reuseLeaf);
    expect(plan.leafId, old);
  });

  test('E3 Granny Smith 159.95 -> 99.95 makes a wrapper, moves the old leaf, adds the new leaf', () async {
    final fruit = await seed.group('🍎 Фрукти');
    final old = await seed.leaf(
      '🍏 Яблука Granny Smith',
      price: 159.95,
      parentId: fruit,
    );
    final plan = await planner.plan(categoryId: old, newPrice: 99.95);
    expect(plan.kind, PlanKind.wrapper);
    expect(plan.reason, PlanReason.priceChanged);
    // Planning wrote nothing.
    expect(await db.select(db.budgetCategoriesTable).get(), hasLength(2));

    final applied = await planner.apply(plan);
    final wrapperId = applied.createdIds.first;
    final wrapper = await seed.cat(wrapperId);
    expect(wrapper.name, '🍏 Яблука Granny Smith');
    expect(wrapper.price, isNull);
    expect(wrapper.parentId, fruit);
    expect((await seed.cat(old)).parentId, wrapperId);
    expect((await seed.cat(old)).price, 159.95);
    final newLeaf = await seed.cat(applied.leafId);
    expect(newLeaf.parentId, wrapperId);
    expect(newLeaf.price, 99.95);
    expect(newLeaf.unit, BudgetUnit.kilogram.db);
    expect(applied.movedIds, [old]);

    // The transaction goes on the NEW leaf, quantity 1.135.
    final tx = await budget.createTransaction(
      categoryId: applied.leafId,
      name: 'ELMA GRANNY SMITH',
      quantity: 1.135,
    );
    final row = await (db.select(
      db.budgetTransactionsTable,
    )..where((t) => t.id.equals(tx))).getSingle();
    expect(row.categoryId, applied.leafId);
    expect(row.unitPrice, 99.95);
    // And the wrapper itself is refused as a target.
    expect(
      () => budget.createTransaction(categoryId: wrapperId, quantity: 1),
      throwsA(isA<BudgetGroupException>()),
    );
  });

  test('C5 apply is idempotent: a retry finds the leaf made by the first run', () async {
    final old = await seed.leaf('🍏 Яблука', price: 159.95);
    final plan = await planner.plan(categoryId: old, newPrice: 99.95);
    final first = await planner.apply(plan);
    final second = await planner.apply(plan);
    expect(second.leafId, first.leafId);
    expect(second.createdIds, isEmpty);
    expect(await db.select(db.budgetCategoriesTable).get(), hasLength(3));
  });

  test('C6 price change on an existing aggregate just adds a leaf', () async {
    final wrapper = await seed.group('🍏 Яблука');
    await seed.leaf('🍏 Яблука', price: 159.95, parentId: wrapper);
    final plan = await planner.plan(categoryId: wrapper, newPrice: 120);
    expect(plan.kind, PlanKind.addLeaf);
    expect(plan.aggregateId, wrapper);
    final applied = await planner.apply(plan);
    expect(applied.createdIds, [applied.leafId]);
    expect((await seed.cat(applied.leafId)).parentId, wrapper);
    expect(await seed.children(wrapper), hasLength(2));
  });

  test('C6 asking via a leaf of a same-name wrapper adds under the wrapper (no extra level)', () async {
    final wrapper = await seed.group('🍏 Яблука');
    final leaf = await seed.leaf('🍏 Яблука', price: 159.95, parentId: wrapper);
    final plan = await planner.plan(categoryId: leaf, newPrice: 120);
    expect(plan.kind, PlanKind.addLeaf);
    expect(plan.aggregateId, wrapper);
  });

  test('C4 incompatible accounts: new leaf with the right accounts (simple leaf -> wrapper)', () async {
    final card = await seed.account('Mono');
    final cash = await seed.account('Cash');
    final leaf = await seed.leaf('🍞 Хліб', price: 20, use: card);
    final plan = await planner.plan(
      categoryId: leaf,
      newPrice: 20,
      accountUseId: cash,
    );
    expect(plan.kind, PlanKind.wrapper);
    expect(plan.reason, PlanReason.accountsIncompatible);
    final applied = await planner.apply(plan);
    final created = await seed.cat(applied.leafId);
    expect(created.accountUseId, cash);
    expect(created.price, 20);
    expect((await seed.cat(leaf)).accountUseId, card);
  });

  test('C4 incompatible accounts under an existing aggregate add a leaf there', () async {
    final card = await seed.account('Mono');
    final cash = await seed.account('Cash');
    final wrapper = await seed.group('🍞 Хліб');
    await seed.leaf('🍞 Хліб', price: 20, parentId: wrapper, use: card);
    final plan = await planner.plan(
      categoryId: wrapper,
      newPrice: 20,
      accountUseId: cash,
    );
    expect(plan.kind, PlanKind.addLeaf);
    expect(plan.reason, PlanReason.accountsIncompatible);
    expect(plan.newLeaf!.accountUseId, cash);
  });

  test('C7 one-off item gets its own piece leaf under the group, price = cost', () async {
    final home = await seed.group('🏠 Побутові предмети');
    final plan = await planner.planOneOff(
      name: 'Рідке мило',
      groupId: home,
      cost: 289,
    );
    expect(plan.kind, PlanKind.oneOffLeaf);
    final applied = await planner.apply(plan);
    final c = await seed.cat(applied.leafId);
    expect(c.parentId, home);
    expect(c.unit, BudgetUnit.piece.db);
    expect(c.price, 289);
    expect(c.name, '🧼 Рідке мило'); // safe icon chosen
    // Buying it again at the same price reuses it.
    final again = await planner.planOneOff(
      name: 'рідке мило',
      groupId: home,
      cost: 289,
    );
    expect(again.kind, PlanKind.reuseLeaf);
  });

  test('C8 finds the snacks category by name', () async {
    final group = await seed.group('🍬 Їжа');
    final snacks = await seed.leaf(
      '🍫 Снеки (асорті)',
      price: 1,
      unit: BudgetUnit.piece,
      parentId: group,
    );
    expect(await planner.findSnacksCategory(), snacks);
  });

  test('C9 quantity = spend / price for budget categories; price 1 = amount', () {
    expect(quantityForSpend(amount: 750, price: 1500), 0.5);
    expect(quantityForSpend(amount: 48, price: 1), 48);
    expect(quantityForSpend(amount: 48, price: null), 48);
    expect(
      quantityForSpend(
        amount: 48,
        price: 5,
        unit: BudgetUnit.percentPerMonth,
      ),
      48,
    );
  });

  test('C11 icon safe list: keeps safe, replaces unsafe, guesses from the name', () {
    expect(withSafeIcon('🍎 Яблука'), '🍎 Яблука');
    expect(withSafeIcon('🫠 Яблука'), '🍎 Яблука'); // melting face: too new
    expect(withSafeIcon('Дезодорант'), '🧴 Дезодорант');
    expect(withSafeIcon('Щось'), '🛒 Щось');
    expect(withSafeIcon('Щось', preferred: '🎁'), '🎁 Щось');
    expect(isSafeIcon('🫠'), isFalse);
  });
}

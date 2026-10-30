import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/ai/dedupe_service.dart';
import 'package:livenow/domain/postpone_rules.dart';

import 'ai_test_support.dart';

void main() {
  late AppDatabase db;
  late Seed seed;
  late DedupeService dedupe;

  setUpAll(initPostponeTimeZoneData);
  setUp(() {
    db = memoryDb();
    seed = Seed(db);
    dedupe = DedupeService(db);
  });
  tearDown(() => db.close());

  final day = DateTime.utc(2026, 10, 8, 16, 40);

  test('I6 the same receipt twice is found (same day, name, amount)', () async {
    final leaf = await seed.leaf('🍏 Яблука', price: 99.95);
    await seed.budget.createTransaction(
      categoryId: leaf,
      name: 'BIM ELMA GRANNY SMITH',
      date: day,
      quantity: 1.135,
    );
    final found = await dedupe.findDuplicates(
      date: day.add(const Duration(hours: 5)),
      amount: 113.44,
      text: 'BIM elma granny smith',
    );
    expect(found, hasLength(1));
    expect(found.single.name, 'BIM ELMA GRANNY SMITH');
  });

  test('I6 +-1 day counts, 2 days does not', () async {
    final leaf = await seed.leaf('Хліб', price: 20);
    await seed.budget.createTransaction(
      categoryId: leaf,
      name: 'ekmek',
      date: day,
      quantity: 1,
    );
    expect(
      await dedupe.findDuplicates(
        date: day.add(const Duration(hours: 23)),
        amount: 20,
        text: 'ekmek',
      ),
      hasLength(1),
    );
    expect(
      await dedupe.findDuplicates(
        date: day.add(const Duration(days: 2)),
        amount: 20,
        text: 'ekmek',
      ),
      isEmpty,
    );
  });

  test('I6 a different amount or an unrelated name is not a duplicate', () async {
    final leaf = await seed.leaf('Хліб', price: 20);
    await seed.budget.createTransaction(
      categoryId: leaf,
      name: 'ekmek',
      date: day,
      quantity: 1,
    );
    expect(
      await dedupe.findDuplicates(date: day, amount: 21, text: 'ekmek'),
      isEmpty,
    );
    expect(
      await dedupe.findDuplicates(date: day, amount: 20, text: 'sut'),
      isEmpty,
    );
    // No text: date + amount decide.
    expect(await dedupe.findDuplicates(date: day, amount: 20), hasLength(1));
  });

  test('I6 an amount category (percent) compares its quantity', () async {
    final leaf = await seed.leaf('Дохід', price: 1);
    await seed.budget.createTransaction(
      categoryId: leaf,
      name: 'x',
      date: day,
      quantity: 48,
    );
    expect(
      await dedupe.findDuplicates(date: day, amount: 48, text: 'x'),
      hasLength(1),
    );
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/ai/alias_source.dart';
import 'package:livenow/domain/ai/category_resolver.dart';
import 'package:livenow/domain/budget_rules.dart';
import 'package:livenow/domain/postpone_rules.dart';

import 'ai_test_support.dart';

void main() {
  late AppDatabase db;
  late Seed seed;

  setUpAll(initPostponeTimeZoneData);
  setUp(() {
    db = memoryDb();
    seed = Seed(db);
  });
  tearDown(() => db.close());

  test('C2 exact name (icon and case ignored) wins, with price and parent', () async {
    final fruit = await seed.group('🍎 Фрукти');
    await seed.leaf('🍌 Банани', price: 70, parentId: fruit);
    await seed.leaf('🥕 Морква', price: 30, parentId: fruit);
    final r = await CategoryResolver(db).resolve('банани');
    expect(r.best!.name, '🍌 Банани');
    expect(r.best!.score, 1.0);
    expect(r.best!.price, 70);
    expect(r.best!.parentName, '🍎 Фрукти');
    expect(r.best!.isAggregate, isFalse);
    expect(r.best!.unit, BudgetUnit.kilogram);
    expect(r.ambiguous, isFalse);
  });

  test('C2 inflected Ukrainian word matches by stem', () async {
    await seed.leaf('🍎 Яблуко', price: 100);
    final r = await CategoryResolver(db).resolve('ЯБЛУКА');
    expect(r.best!.name, '🍎 Яблуко');
  });

  test('C3 different varieties are separate candidates and the choice is ambiguous', () async {
    await seed.leaf('🍏 Яблука Granny Smith', price: 100);
    await seed.leaf('🍎 Яблука Gala', price: 80);
    final r = await CategoryResolver(db).resolve('яблука');
    expect(r.candidates.length, 2);
    expect(r.ambiguous, isTrue);
    final precise = await CategoryResolver(db).resolve('яблука gala');
    expect(precise.best!.name, '🍎 Яблука Gala');
    expect(precise.ambiguous, isFalse);
  });

  test('C3 a wrapper stands for its same-name leaves and lists them as variants', () async {
    final wrapper = await seed.group('🍏 Яблука Granny Smith');
    await seed.leaf('🍏 Яблука Granny Smith', price: 159.95, parentId: wrapper);
    await seed.leaf('🍏 Яблука Granny Smith', price: 99.95, parentId: wrapper);
    final r = await CategoryResolver(db).resolve('Яблука Granny Smith');
    expect(r.candidates.length, 1);
    expect(r.best!.isAggregate, isTrue);
    expect(r.best!.variants.map((v) => v.price), [159.95, 99.95]);
    expect(r.ambiguous, isFalse);
  });

  test('C3 same-name leaves under a plain group are variants, not a question', () async {
    final dairy = await seed.group('🥛 Молочне');
    await seed.leaf('🥛 Молоко', price: 30, parentId: dairy);
    await seed.leaf('🥛 Молоко', price: 36, parentId: dairy);
    final r = await CategoryResolver(db).resolve('молоко');
    expect(r.ambiguous, isFalse);
    expect(r.best!.variants.length, 1);
  });

  test('C2 alias memory comes first and carries its defaults', () async {
    final apple = await seed.leaf('🍎 Яблука Gala', price: 80);
    await seed.leaf('🍏 Яблука Granny Smith', price: 100);
    final aliases = InMemoryAliasSource({
      'ELMA GALA': AliasEntry(
        categoryId: apple,
        weightGramsDefault: 200,
        source: 'user',
      ),
    });
    final r = await CategoryResolver(db, aliases: aliases).resolve('Elma Gala');
    expect(r.best!.id, apple);
    expect(r.best!.fromAlias, isTrue);
    expect(r.alias!.weightGramsDefault, 200);
    expect(r.ambiguous, isFalse);
  });

  test('C13 nothing similar gives an empty, non-creating result', () async {
    await seed.leaf('🍌 Банани', price: 70);
    final r = await CategoryResolver(db).resolve('dana kıyma');
    expect(r.isEmpty, isTrue);
    expect(await db.select(db.budgetCategoriesTable).get(), hasLength(1));
  });

  test('C2 Turkish dotted/dotless i fold; numbers in the receipt text are ignored', () async {
    await seed.leaf('🧀 Beyaz peynir', price: 300);
    final r = await CategoryResolver(db).resolve('BEYAZ PEYNİR 500 G 1.135');
    expect(r.best!.name, '🧀 Beyaz peynir');
  });
}

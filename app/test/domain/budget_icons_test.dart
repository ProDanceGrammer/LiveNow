import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/budget_icons.dart';
import 'package:livenow/domain/budget_io_service.dart';
import 'package:livenow/domain/budget_service.dart';

void main() {
  group('parseCategoryIcons', () {
    test('reads the screenshot file layout (BOM, extra column)', () {
      const csv =
          '﻿row_in_screenshot,name,icon\r\n'
          '295,Взуття,👟\r\n'
          "4,Чай трав'яний,🍵\r\n";
      final icons = parseCategoryIcons(csv);
      expect(
        [for (final i in icons) '${i.icon} ${i.name}'],
        ['👟 Взуття', "🍵 Чай трав'яний"],
      );
    });

    test('skips rows without a name or an icon; the last duplicate wins', () {
      const csv =
          'name,icon\n'
          'Чай,\n'
          ',🍵\n'
          'Хліб,🍞\n'
          'хліб ,🥖\n';
      final icons = parseCategoryIcons(csv);
      expect(icons, hasLength(1));
      expect(icons.single.icon, '🥖');
    });

    test('quoted names with commas, and a file without the columns', () {
      expect(
        parseCategoryIcons('name,icon\n"Їжа, напої",🍽️\n').single.name,
        'Їжа, напої',
      );
      expect(parseCategoryIcons('a,b\n1,2\n'), isEmpty);
      expect(parseCategoryIcons(''), isEmpty);
      expect(looksLikeCategoryIcons('name,icon\n'), isTrue);
      expect(looksLikeCategoryIcons('a,b\n'), isFalse);
    });
  });

  group('stripLeadingIcon', () {
    test('removes an emoji and its space, nothing else', () {
      expect(stripLeadingIcon('👟 Взуття'), 'Взуття');
      expect(stripLeadingIcon('🍽️ Їжа'), 'Їжа');
      expect(stripLeadingIcon('Взуття'), 'Взуття');
      expect(stripLeadingIcon('# 1 Rent'), '# 1 Rent');
      expect(stripLeadingIcon('(TL) Bills'), '(TL) Bills');
    });
  });

  group('applyCategoryIcons', () {
    late AppDatabase db;
    late BudgetService budget;
    late BudgetIoService io;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      budget = BudgetService(db);
      io = BudgetIoService(db);
    });
    tearDown(() => db.close());

    Future<List<String>> names() async => [
      for (final r
          in await db
              .customSelect('SELECT name FROM budget_categories ORDER BY name')
              .get())
        r.data['name']! as String,
    ];

    test('puts emoji + space in front of the name', () async {
      await budget.saveCategory(const CategoryInput(name: 'Взуття'));
      await budget.saveCategory(const CategoryInput(name: 'Хліб'));
      final r = await io.applyCategoryIcons(
        parseCategoryIcons('name,icon\nВзуття,👟\nМолоко,🥛\n'),
      );
      expect(await names(), ['Хліб', '👟 Взуття']);
      expect(r.updated, 1);
      expect(r.unchanged, 0);
      expect(r.notFound, ['Молоко']);
    });

    test('is idempotent, and a new icon replaces the old one', () async {
      await budget.saveCategory(const CategoryInput(name: 'Взуття'));
      await io.applyCategoryIcons(parseCategoryIcons('name,icon\nВзуття,👟\n'));
      final again = await io.applyCategoryIcons(
        parseCategoryIcons('name,icon\nВзуття,👟\n'),
      );
      expect(again.updated, 0);
      expect(again.unchanged, 1);
      expect(await names(), ['👟 Взуття']);

      await io.applyCategoryIcons(parseCategoryIcons('name,icon\nВзуття,🥾\n'));
      expect(await names(), ['🥾 Взуття']); // replaced, not stacked
    });

    test('every category with that name gets it; case and apostrophes do not matter', () async {
      await budget.saveCategory(const CategoryInput(name: 'Одяг'));
      await budget.saveCategory(const CategoryInput(name: 'Одяг'));
      await budget.saveCategory(const CategoryInput(name: 'Чай трав’яний'));
      await io.applyCategoryIcons(
        parseCategoryIcons("name,icon\nодяг,👕\nЧай трав'яний,🍵\n"),
      );
      expect(await names(), ['🍵 Чай трав’яний', '👕 Одяг', '👕 Одяг']);
    });

    test('a name that starts with punctuation keeps it', () async {
      await budget.saveCategory(const CategoryInput(name: '(TL) Bills'));
      await io.applyCategoryIcons(
        parseCategoryIcons('name,icon\n(TL) Bills,🧾\n'),
      );
      expect(await names(), ['🧾 (TL) Bills']);
    });

    test(
      'the rename is a normal edit: updated_at moves, sync logs it',
      () async {
        final id = await budget.saveCategory(
          const CategoryInput(name: 'Взуття'),
        );
        final before =
            (await db
                    .customSelect(
                      "SELECT hlc FROM sync_versions WHERE row_id = '$id'",
                    )
                    .getSingle())
                .read<String>('hlc');
        await Future<void>.delayed(const Duration(milliseconds: 5));
        await io.applyCategoryIcons(
          parseCategoryIcons('name,icon\nВзуття,👟\n'),
        );
        final after =
            (await db
                    .customSelect(
                      "SELECT hlc FROM sync_versions WHERE row_id = '$id'",
                    )
                    .getSingle())
                .read<String>('hlc');
        expect(after.compareTo(before), greaterThan(0));
      },
    );
  });
}

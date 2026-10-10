import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/domain/budget_csv.dart';
import 'package:livenow/domain/budget_rules.dart';
import 'package:livenow/domain/postpone_rules.dart';

const accountsCsv = '''
Name,Type,Cattegories to interact,Cattegories to count
Euro,Cash,,
Turkish Lira,Cash,"name: Chicken price: 5,name: Chicken price: 7",
(₴) Monobank,Digital,,
''';

const categoriesCsv = '''
Category name,Unit of measure,👛 Account to use,👛 Account to count,Count percent of (text),Consists of (text),Price per Unit,Frequency,Units per Month (Plan),End Date,One-time,Income
Chicken,Kilogram,Turkish Lira,Turkish Lira,,"Chicken,Chicken",-1,,-1,,No,No
Chicken,Kilogram,Turkish Lira,Turkish Lira,,,5,,-1,,No,No
Chicken,Kilogram,Turkish Lira,Turkish Lira,,,7,,-1,,No,No
Salary,Month,Euro,Euro,,,2200,1,-1,,No,Yes
Cushion,Percent per Month,Euro,Euro,Salary,,10,,-1,,No,No
Hygiene,Month,Turkish Lira,Turkish Lira,,New page,-1,,-1,,No,No
Rent,Month,Turkish Lira,Turkish Lira,,,1000,1,0,01/12/2026,No,No
''';

const transactionsCsv = '''
Currency to interact,Currency to count,Category,Action,Transaction Name,Quantity,Price,Date,Euo Rate (Сount),Euo Rate (Interact)
Turkish Lira,Turkish Lira,Chicken,🍓 Bazaar,Chicken breast,2,7,08/10/2026 18:37 → 20:08,55.9,55.9
Turkish Lira,Turkish Lira,Chicken,,Thighs,1,5,05/10/2026 10:00,56,56
,,,Shop,No category,1,,25/09/2026 18:37 → 19:00,56.6,52.5
Euro,Euro,Salary,,Pay,1,2200,01/10/2026,,
Turkish Lira,Turkish Lira,Chicken,,Undated,1,5,,,
,,,,,,,,,
''';

void main() {
  setUpAll(initPostponeTimeZoneData);

  group('detectBudgetCsv', () {
    test('recognises each export by its header', () {
      expect(detectBudgetCsv(accountsCsv), BudgetCsvKind.accounts);
      expect(detectBudgetCsv(categoriesCsv), BudgetCsvKind.categories);
      expect(detectBudgetCsv(transactionsCsv), BudgetCsvKind.transactions);
      expect(detectBudgetCsv('a,b\n1,2'), isNull);
      expect(detectBudgetCsv(''), isNull);
    });
  });

  group('inferCurrency', () {
    test('from the account name', () {
      expect(inferCurrency('(€) Monobank ФОП'), 'EUR');
      expect(inferCurrency('Euro'), 'EUR');
      expect(inferCurrency('(₴) Monobank'), 'UAH');
      expect(inferCurrency('Turkish Lira'), 'TRY');
      expect(inferCurrency('Garanti BBVA (TL)'), 'TRY');
      expect(inferCurrency('BTC'), 'BTC');
      expect(inferCurrency('USDT'), 'USDT');
      expect(inferCurrency('Piggy bank'), isNull);
    });
  });

  group('parseBudgetCsvs', () {
    late ParsedBudgetImport parsed;
    late List<ImportedCategory> cats;
    setUpAll(() {
      parsed = parseBudgetCsvs(
        accountsCsv: accountsCsv,
        categoriesCsv: categoriesCsv,
        transactionsCsv: transactionsCsv,
      );
      cats = parsed.categories;
    });

    test('categories: Notion sentinels become null; percent keeps its %', () {
      expect(cats, hasLength(7));
      final salary = cats[3];
      expect(salary.isIncome, isTrue);
      expect(salary.price, 2200);
      expect(salary.frequencyMonths, 1);
      expect(salary.unitsPerMonth, isNull); // -1
      final cushion = cats[4];
      expect(cushion.unit, BudgetUnit.percentPerMonth);
      expect(cushion.percent, 10);
      expect(cushion.price, isNull);
      expect(cats[6].unitsPerMonth, isNull); // 0
      expect(cats[6].endDate, isNotNull);
    });

    test('a group lists its children by name; each row is claimed once', () {
      expect(cats[0].price, isNull); // the -1 of a group
      expect(cats[1].parentIndex, 0);
      expect(cats[2].parentIndex, 0);
      expect(cats[0].parentIndex, isNull); // never its own child
    });

    test('unknown children and percent sources are reported, not fatal', () {
      expect(parsed.unresolvedChildren, ['Hygiene: New page']);
      expect(cats[4].percentSourceIndex, 3);
      expect(parsed.unresolvedPercentSources, isEmpty);
    });

    test('transactions: pick the leaf by price; skip rows with no category '
        'or date', () {
      expect(parsed.transactions, hasLength(3));
      expect(parsed.skippedNoCategory, 1);
      expect(parsed.skippedNoDate, 1);
      final breast = parsed.transactions.firstWhere(
        (t) => t.name == 'Chicken breast',
      );
      expect(breast.categoryIndex, 2); // the 7 TL variant
      final thighs = parsed.transactions.firstWhere((t) => t.name == 'Thighs');
      expect(thighs.categoryIndex, 1); // the 5 TL variant
      expect(breast.actionName, '🍓 Bazaar');
    });

    test('accounts: currency inferred, rate from the latest transaction', () {
      final byName = {for (final a in parsed.accounts) a.name: a};
      expect(byName['Euro']!.currency, 'EUR');
      expect(byName['Euro']!.rateToBase, 1);
      expect(byName['Turkish Lira']!.currency, 'TRY');
      expect(byName['Turkish Lira']!.rateToBase, 55.9); // 08/10 beats 05/10
      expect(byName['(₴) Monobank']!.currency, 'UAH');
      expect(byName['(₴) Monobank']!.rateFound, isFalse);
    });

    test('transactions need categories', () {
      expect(
        () => parseBudgetCsvs(transactionsCsv: transactionsCsv),
        throwsFormatException,
      );
    });

    test('a typed rate far from the current account rate is flagged', () {
      final p = parseBudgetCsvs(
        categoriesCsv:
            'Category name,Unit of measure,Account to use,Account to count,Price per Unit\n'
            'Gift,Piece,Turkish Lira,Turkish Lira,100\n',
        transactionsCsv:
            'Currency to interact,Currency to count,Category,Action,'
            'Transaction Name,Quantity,Price,Date,Euo Rate (Count),Euo Rate (Interact)\n'
            'Turkish Lira,Turkish Lira,Gift,,late,1,100,10/10/2026,55,55\n'
            'Turkish Lira,Turkish Lira,Gift,,typo,1,100,01/08/2026,1,\n',
      );
      expect(p.suspiciousRates, hasLength(1));
      expect(p.suspiciousRates.single, contains('typo'));
      expect(p.suspiciousRates.single, contains('rate 1.0 vs 55.0'));
    });

    test('a transaction on a group category is skipped and counted', () {
      final p = parseBudgetCsvs(
        categoriesCsv:
            'Category name,Unit of measure,Consists of (text)\n'
            'Food,Month,Meat\nMeat,Month,\n',
        transactionsCsv:
            'Currency to interact,Currency to count,Category,Action,'
            'Transaction Name,Quantity,Price,Date\n'
            ',,Food,,x,1,5,01/10/2026\n',
      );
      // "Food" is a group: its only leaf row named Food does not exist.
      expect(p.transactions, isEmpty);
      expect(p.skippedGroupCategory, 1);
    });
  });

  // Runs against the author's real export when it is on disk (never required).
  final dir = Directory('../dev/data/budget');
  test('the real Notion export parses', () {
    String read(String n) => File('${dir.path}/$n').readAsStringSync();
    final p = parseBudgetCsvs(
      accountsCsv: read('Notion Export - Accounts.csv'),
      categoriesCsv: read('Notion Export - Categories.csv'),
      transactionsCsv: read('Notion Export - Transactions.csv'),
    );
    expect(p.accounts.length, greaterThanOrEqualTo(7));
    // 316 data rows, one without a name.
    expect(p.categories.length, 315);
    // ignore: avoid_print
    print(
      'REAL: accounts=${p.accounts.length} cats=${p.categories.length} '
      'withParent=${p.categories.where((c) => c.parentIndex != null).length} '
      'groups=${p.categories.where((c) => c.childNames.isNotEmpty).length} '
      'tx=${p.transactions.length} noCat=${p.skippedNoCategory} noDate=${p.skippedNoDate} '
      'group=${p.skippedGroupCategory} unresolvedChildren=${p.unresolvedChildren} '
      'unresolvedPercent=${p.unresolvedPercentSources} unknownAcc=${p.unknownAccounts} '
      'guessed=${p.accounts.where((a) => a.currencyGuessed).map((a) => a.name).toList()} '
      'noRate=${p.accounts.where((a) => !a.rateFound).map((a) => a.name).toList()} '
      'rates=${p.accounts.map((a) => "${a.currency}:${a.rateToBase}").toList()}',
    );
    expect(p.transactions, isNotEmpty);
    // Parent assignment claims each row at most once, with no loops.
    for (var i = 0; i < p.categories.length; i++) {
      var cur = p.categories[i].parentIndex;
      var hops = 0;
      while (cur != null) {
        expect(cur, isNot(i));
        cur = p.categories[cur].parentIndex;
        expect(++hops, lessThan(50));
      }
    }
  }, skip: !dir.existsSync() ? 'dev/data/budget is not on disk' : false);
}

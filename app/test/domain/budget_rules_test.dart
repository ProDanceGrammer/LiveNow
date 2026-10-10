import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/domain/budget_rules.dart';
import 'package:livenow/domain/postpone_rules.dart';

void main() {
  setUpAll(initPostponeTimeZoneData);

  DateTime utc(int y, int mo, int d, [int h = 12]) => DateTime.utc(y, mo, d, h);
  final asOf = utc(2026, 10, 10);
  final period = BudgetPeriod(asOf: asOf);

  const eur = BudgetAcct(id: 'eur', currency: 'EUR', rateToBase: 1);
  const tl = BudgetAcct(id: 'tl', currency: 'TRY', rateToBase: 40);

  BudgetSnapshot compute(
    List<BudgetCat> cats, {
    List<BudgetTx> txs = const [],
    List<BudgetAcct> accts = const [eur, tl],
    BudgetPeriod? p,
  }) => computeBudget(
    categories: cats,
    accounts: accts,
    transactions: txs,
    period: p ?? period,
  );

  group('months', () {
    test('monthsBetween: whole month = 1, none when reversed', () {
      expect(monthsBetween(utc(2026, 10, 10), utc(2026, 11, 10)), 1);
      expect(monthsBetween(utc(2026, 10, 10), utc(2027, 1, 10)), 3);
      expect(monthsBetween(utc(2026, 10, 10), utc(2026, 10, 10)), 0);
      expect(monthsBetween(utc(2026, 10, 10), utc(2026, 9, 1)), 0);
      expect(
        monthsBetween(utc(2026, 10, 10), utc(2026, 10, 25)),
        closeTo(15 / 31, 0.001),
      );
    });

    test('ends in 1 month => 1 month; starts in 1 month => 2 of 3', () {
      final planEnd = period.planEnd;
      expect(activeMonths(null, utc(2026, 11, 10), asOf, planEnd), 1);
      expect(activeMonths(utc(2026, 11, 10), null, asOf, planEnd), 2);
      expect(activeMonths(null, null, asOf, planEnd), 3);
      expect(activeMonths(utc(2027, 3, 1), null, asOf, planEnd), 0);
      expect(activeMonths(null, utc(2026, 9, 1), asOf, planEnd), 0);
    });

    test(
      'start of planning: first record, minus a month when in the future',
      () {
        expect(startOfPlanning(const [], asOf), isNull);
        expect(
          startOfPlanning([utc(2026, 8, 1), utc(2026, 9, 1)], asOf),
          utc(2026, 8, 1),
        );
        expect(startOfPlanning([utc(2026, 12, 10)], asOf), utc(2026, 11, 10));
      },
    );
  });

  group('plan cost', () {
    test('price x units / frequency, times the months of the period', () {
      final s = compute([
        const BudgetCat(
          id: 'rent',
          name: 'Rent',
          price: 500,
          unitsPerMonth: 1,
          accountCountId: 'eur',
        ),
        const BudgetCat(
          id: 'tv',
          name: 'TV savings',
          price: 600,
          frequencyMonths: 6,
          accountCountId: 'eur',
        ),
      ]);
      expect(s.byCategory['rent']!.monthlyPlan, 500);
      expect(s.byCategory['rent']!.planCost, 1500);
      expect(s.byCategory['rent']!.planBase, -1500);
      expect(s.byCategory['tv']!.monthlyPlan, 100);
      expect(s.byCategory['tv']!.planCost, 300);
    });

    test('Turkish lira category is converted by its account rate', () {
      final s = compute([
        const BudgetCat(
          id: 'm',
          name: 'Market',
          price: 400,
          unitsPerMonth: 1,
          accountCountId: 'tl',
        ),
      ]);
      expect(s.byCategory['m']!.planCost, 1200);
      expect(s.byCategory['m']!.planBase, -30);
    });

    test('ending in 1 month counts only that month; starting in 1 month 2', () {
      final s = compute(
        [
          BudgetCat(
            id: 'ends',
            name: 'Ends',
            price: 100,
            unitsPerMonth: 1,
            accountCountId: 'eur',
            endDate: utc(2026, 11, 10),
          ),
          BudgetCat(
            id: 'starts',
            name: 'Starts',
            price: 100,
            unitsPerMonth: 1,
            accountCountId: 'eur',
          ),
          BudgetCat(
            id: 'gone',
            name: 'Gone',
            price: 100,
            unitsPerMonth: 1,
            accountCountId: 'eur',
            endDate: utc(2026, 9, 1),
          ),
        ],
        txs: [
          // First (future) record 2 months... planned from 1 month before it.
          BudgetTx(id: 't', categoryId: 'starts', date: utc(2026, 12, 10)),
        ],
      );
      expect(s.byCategory['ends']!.planCost, 100);
      expect(s.byCategory['starts']!.planCost, 200);
      expect(s.byCategory['gone']!.planCost, 0);
    });

    test('one-time counts once', () {
      final s = compute([
        BudgetCat(
          id: 'tax',
          name: 'Tax',
          oneTime: true,
          price: 250,
          unitsPerMonth: 1,
          accountCountId: 'eur',
          endDate: utc(2026, 12, 1),
        ),
      ]);
      expect(s.byCategory['tax']!.planCost, 250);
    });

    test('percent of salary: 10% of 2200 is 220 a month, x3 once', () {
      final s = compute([
        const BudgetCat(
          id: 'salary',
          name: 'Salary',
          isIncome: true,
          price: 2200,
          unitsPerMonth: 1,
          accountCountId: 'eur',
        ),
        const BudgetCat(
          id: 'save',
          name: 'Cushion',
          unit: BudgetUnit.percentPerMonth,
          percent: 10,
          countPercentOfId: 'salary',
          accountCountId: 'eur',
        ),
      ]);
      expect(s.byCategory['salary']!.planCost, 6600);
      expect(s.byCategory['save']!.monthlyPlan, 220);
      expect(s.byCategory['save']!.planCost, 660);
    });

    test('percent source in another currency is converted', () {
      final s = compute([
        const BudgetCat(
          id: 'salary',
          name: 'Salary',
          isIncome: true,
          price: 2000,
          unitsPerMonth: 1,
          accountCountId: 'eur',
        ),
        const BudgetCat(
          id: 'tax',
          name: 'Tax',
          unit: BudgetUnit.percentPerMonth,
          percent: 10,
          countPercentOfId: 'salary',
          accountCountId: 'tl',
        ),
      ]);
      expect(s.byCategory['tax']!.monthlyPlan, 8000); // 200 EUR x 40
    });

    test('a percent loop yields nothing instead of recursing forever', () {
      final s = compute([
        const BudgetCat(
          id: 'a',
          name: 'a',
          unit: BudgetUnit.percentPerMonth,
          percent: 10,
          countPercentOfId: 'b',
          accountCountId: 'eur',
        ),
        const BudgetCat(
          id: 'b',
          name: 'b',
          unit: BudgetUnit.percentPerMonth,
          percent: 10,
          countPercentOfId: 'a',
          accountCountId: 'eur',
        ),
      ]);
      expect(s.byCategory['a']!.planCost, 0);
    });

    test(
      'child without own numbers: parent units / active children x price',
      () {
        final s = compute([
          const BudgetCat(id: 'chicken', name: 'Chicken', unitsPerMonth: 9),
          const BudgetCat(
            id: 'c5',
            name: 'Chicken 5',
            parentId: 'chicken',
            price: 5,
            accountCountId: 'eur',
          ),
          const BudgetCat(
            id: 'c7',
            name: 'Chicken 7',
            parentId: 'chicken',
            price: 7,
            accountCountId: 'eur',
          ),
          BudgetCat(
            id: 'c6',
            name: 'Chicken 6 (old)',
            parentId: 'chicken',
            price: 6,
            accountCountId: 'eur',
            endDate: utc(2026, 1, 1),
          ),
        ]);
        // 9 units / 2 active children = 4.5 units each a month.
        expect(s.byCategory['c5']!.monthlyPlan, 22.5);
        expect(s.byCategory['c7']!.monthlyPlan, 31.5);
        expect(s.byCategory['chicken']!.isGroup, isTrue);
        expect(
          s.byCategory['chicken']!.planBase,
          closeTo(-(22.5 + 31.5) * 3, 0.01),
        );
      },
    );

    test('no account or rate: flagged, never NaN', () {
      final s = compute([
        const BudgetCat(id: 'x', name: 'x', price: 10, unitsPerMonth: 1),
      ]);
      expect(s.byCategory['x']!.noRate, isTrue);
      expect(s.byCategory['x']!.planBase, 0);
      expect(s.noRate, isTrue);
    });
  });

  group('fact cost', () {
    test('sums price x quantity of transactions in the last period', () {
      final s = compute(
        [
          const BudgetCat(
            id: 'milk',
            name: 'Milk',
            unit: BudgetUnit.kilogram,
            accountCountId: 'eur',
          ),
        ],
        txs: [
          BudgetTx(
            id: '1',
            categoryId: 'milk',
            date: utc(2026, 10, 1),
            quantity: 2,
            unitPrice: 2,
          ),
          // A later price change must not rewrite the earlier transaction.
          BudgetTx(
            id: '2',
            categoryId: 'milk',
            date: utc(2026, 10, 5),
            quantity: 1,
            unitPrice: 3,
          ),
          // Older than the period and in the future: excluded.
          BudgetTx(
            id: '3',
            categoryId: 'milk',
            date: utc(2026, 5, 1),
            quantity: 9,
            unitPrice: 9,
          ),
          BudgetTx(
            id: '4',
            categoryId: 'milk',
            date: utc(2026, 11, 1),
            quantity: 9,
            unitPrice: 9,
          ),
        ],
      );
      expect(s.byCategory['milk']!.factCost, 7);
      expect(s.byCategory['milk']!.factUnits, 3);
      expect(s.byCategory['milk']!.factBase, -7);
    });

    test('a transaction later today still counts', () {
      final s = compute(
        [const BudgetCat(id: 'a', name: 'a', accountCountId: 'eur')],
        txs: [
          BudgetTx(
            id: '1',
            categoryId: 'a',
            date: asOf.add(const Duration(hours: 5)),
            unitPrice: 4,
          ),
        ],
      );
      expect(s.byCategory['a']!.factCost, 4);
    });

    test(
      'percent category: % of the source fact once it has a transaction',
      () {
        final cats = [
          const BudgetCat(
            id: 'salary',
            name: 'Salary',
            isIncome: true,
            accountCountId: 'eur',
          ),
          const BudgetCat(
            id: 'save',
            name: 'Cushion',
            unit: BudgetUnit.percentPerMonth,
            percent: 10,
            countPercentOfId: 'salary',
            accountCountId: 'eur',
          ),
        ];
        final salaryTx = BudgetTx(
          id: 's',
          categoryId: 'salary',
          date: utc(2026, 9, 20),
          unitPrice: 2200,
          isIncome: true,
        );
        expect(compute(cats, txs: [salaryTx]).byCategory['save']!.factCost, 0);
        final s = compute(
          cats,
          txs: [
            salaryTx,
            BudgetTx(
              id: 'p',
              categoryId: 'save',
              date: utc(2026, 9, 21),
              quantity: 220,
              isAmount: true,
            ),
          ],
        );
        expect(s.byCategory['save']!.factCost, 220);
      },
    );

    test("a transaction's own rate keeps old totals stable", () {
      final s = compute(
        [const BudgetCat(id: 'm', name: 'm', accountCountId: 'tl')],
        txs: [
          BudgetTx(
            id: '1',
            categoryId: 'm',
            date: utc(2026, 9, 20),
            unitPrice: 400,
            rateCount: 20, // the lira was stronger then
          ),
          BudgetTx(
            id: '2',
            categoryId: 'm',
            date: utc(2026, 10, 2),
            unitPrice: 400,
          ),
        ],
      );
      // 400/20 = 20 EUR, then the latest typed rate (20) also becomes current.
      expect(s.byCategory['m']!.factBase, -40);
      expect(s.byCategory['m']!.rate, 20);
    });
  });

  group('totals and board', () {
    test('summary uses top-level categories only and adds fact + plan', () {
      final s = compute(
        [
          const BudgetCat(
            id: 'salary',
            name: 'Salary',
            isIncome: true,
            price: 1000,
            unitsPerMonth: 1,
            accountCountId: 'eur',
          ),
          const BudgetCat(id: 'food', name: 'Food'),
          const BudgetCat(
            id: 'meat',
            name: 'Meat',
            parentId: 'food',
            price: 100,
            unitsPerMonth: 1,
            accountCountId: 'eur',
          ),
        ],
        txs: [
          BudgetTx(
            id: '1',
            categoryId: 'meat',
            date: utc(2026, 10, 1),
            unitPrice: 50,
          ),
        ],
      );
      expect(s.planTotal, 3000 - 300);
      expect(s.factTotal, -50);
      expect(s.position, 2650);
    });

    test('classifyPlanFact', () {
      expect(classifyPlanFact(-120, -100, 10), BoardColumn.over);
      expect(classifyPlanFact(-50, -100, 10), BoardColumn.under);
      expect(classifyPlanFact(-95, -100, 10), BoardColumn.within);
      expect(classifyPlanFact(-110, -100, 10), BoardColumn.within);
    });
  });

  group('balances', () {
    test('opening + dated-up-to-today transactions; planned ones wait', () {
      final b = computeBalances(
        accounts: const [
          BudgetAcct(
            id: 'eur',
            currency: 'EUR',
            rateToBase: 1,
            openingBalance: 100,
          ),
        ],
        transactions: [
          BudgetTx(
            id: '1',
            date: utc(2026, 10, 1),
            unitPrice: 30,
            accountCountId: 'eur',
            accountUseId: 'eur',
          ),
          BudgetTx(
            id: '2',
            date: utc(2026, 10, 2),
            unitPrice: 500,
            isIncome: true,
            accountCountId: 'eur',
            accountUseId: 'eur',
          ),
          BudgetTx(
            id: '3',
            date: utc(2026, 10, 20), // planned
            unitPrice: 999,
            accountCountId: 'eur',
            accountUseId: 'eur',
          ),
        ],
        now: asOf,
      );
      expect(b['eur']!.amount, 570);
      expect(b['eur']!.incomplete, isFalse);
    });

    test('counted in lira, paid from a euro account', () {
      final b = computeBalances(
        accounts: const [eur, tl],
        transactions: [
          BudgetTx(
            id: '1',
            date: utc(2026, 10, 1),
            unitPrice: 400,
            accountCountId: 'tl',
            accountUseId: 'eur',
          ),
        ],
        now: asOf,
      );
      expect(b['eur']!.amount, -10);
    });

    test('missing rate marks the balance incomplete', () {
      final b = computeBalances(
        accounts: const [eur],
        transactions: [
          BudgetTx(
            id: '1',
            date: utc(2026, 10, 1),
            unitPrice: 400,
            accountCountId: 'gone',
            accountUseId: 'eur',
          ),
        ],
        now: asOf,
      );
      expect(b['eur']!.amount, 0);
      expect(b['eur']!.incomplete, isTrue);
    });
  });

  group('upcoming action + cycles', () {
    test(
      'nearest future transaction with an action, groups use descendants',
      () {
        final r = upcomingActionByCategory(
          categories: const [
            BudgetCat(id: 'g', name: 'g'),
            BudgetCat(id: 'a', name: 'a', parentId: 'g'),
            BudgetCat(id: 'b', name: 'b', parentId: 'g'),
          ],
          transactions: [
            BudgetTx(
              id: '1',
              categoryId: 'a',
              date: utc(2026, 12, 1),
              actionId: 'x',
            ),
            BudgetTx(
              id: '2',
              categoryId: 'a',
              date: utc(2026, 11, 1),
              actionId: 'y',
            ),
            BudgetTx(
              id: '3',
              categoryId: 'b',
              date: utc(2026, 10, 20),
              actionId: 'z',
            ),
            BudgetTx(id: '4', categoryId: 'b', date: utc(2026, 10, 15)),
            BudgetTx(
              id: '5',
              categoryId: 'b',
              date: utc(2026, 9, 1),
              actionId: 'old',
            ),
          ],
          now: asOf,
        );
        expect(r['a'], 'y');
        expect(r['b'], 'z');
        expect(r['g'], 'z');
      },
    );

    test('cycle checks', () {
      final parentOf = <String, String?>{'a': null, 'b': 'a', 'c': 'b'};
      expect(wouldCreateParentCycle(parentOf, 'a', 'c'), isTrue);
      expect(wouldCreateParentCycle(parentOf, 'a', 'a'), isTrue);
      expect(wouldCreateParentCycle(parentOf, 'c', 'a'), isFalse);
      expect(wouldCreateParentCycle(parentOf, 'a', null), isFalse);
      expect(wouldCreatePercentCycle({'x': 'y'}, 'y', 'x'), isTrue);
    });
  });
}

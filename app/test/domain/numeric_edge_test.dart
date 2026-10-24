import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/core/number_rules.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/action_service.dart';
import 'package:livenow/domain/budget_rules.dart';
import 'package:livenow/domain/budget_service.dart';
import 'package:livenow/domain/duration_rules.dart';
import 'package:livenow/domain/growth_rules.dart';
import 'package:livenow/domain/metric_service.dart';
import 'package:livenow/domain/plan_rules.dart';
import 'package:livenow/domain/postpone_rules.dart';
import 'package:livenow/domain/sequence_naming.dart';
import 'package:livenow/domain/sync/change_validation.dart';
import 'package:livenow/domain/sync/sync_models.dart';
import 'package:livenow/domain/treemap_layout.dart';
import 'package:livenow/ui/widgets/budget_format.dart';

// Quantities and extreme numbers. Clock-independent: fixed dates only.

AppDatabase _db() => AppDatabase.forTesting(
  NativeDatabase.memory(
    setup: (raw) => raw.execute('PRAGMA foreign_keys = ON;'),
  ),
);

bool _bad(double v) => v.isNaN || v.isInfinite;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  setUpAll(initPostponeTimeZoneData);

  group('parseBudgetNumber', () {
    test('plain, comma and grouped numbers', () {
      expect(parseBudgetNumber('12'), 12);
      expect(parseBudgetNumber(' 12.5 '), 12.5);
      expect(parseBudgetNumber('1,5'), 1.5);
      expect(parseBudgetNumber('1 000,50'), 1000.5);
      expect(parseBudgetNumber('1 000,50'), 1000.5);
      expect(parseBudgetNumber('1,000.50'), 1000.5);
      expect(parseBudgetNumber('1.000,50'), 1000.5);
      expect(parseBudgetNumber('-3,25'), -3.25);
      expect(parseBudgetNumber('1e3'), 1000);
      expect(parseBudgetNumber('.5'), 0.5);
    });

    test('empty, garbage, NaN, Infinity and overflow are all null', () {
      for (final s in [
        '',
        '  ',
        'abc',
        '1e400',
        '-1e400',
        'NaN',
        'nan',
        'Infinity',
        '-Infinity',
        '1e13',
        '0x10',
        '1,2,3',
        '1_000',
        '١٢٣',
        '5 apples',
        '--5',
        '1e',
      ]) {
        expect(parseBudgetNumber(s), isNull, reason: '"$s"');
      }
    });

    test('-0 reads as a plain zero', () {
      final v = parseBudgetNumber('-0')!;
      expect(v, 0);
      expect(v.isNegative, isFalse);
    });
  });

  group('rounding and totals', () {
    test('round2 survives NaN, infinity, huge values and many decimals', () {
      expect(round2(1.005 * 3), closeTo(3.01, 0.0101));
      expect(round2(0.1 + 0.2), 0.3);
      expect(round2(-0.004), 0.0);
      expect(round2(123456789.123456789), 123456789.12);
      expect(round2(1e15), 1e15);
      expect(round2(1e22), 1e22);
      expect(round2(1e300), 1e300);
      expect(round2(-1e300), -1e300);
      expect(round2(double.infinity), double.infinity);
      expect(round2(double.nan).isNaN, isFalse);
      expect(round2(5e-324), 0);
      expect(round2(0.1234567890123456789), 0.12);
    });

    test('a million small sums round to the cent without drift', () {
      var sum = 0.0;
      for (var i = 0; i < 1000000; i++) {
        sum += 0.01;
      }
      expect(round2(sum), 10000.0);
    });

    BudgetSnapshot compute(List<BudgetTx> txs, {List<BudgetCat>? cats}) {
      return computeBudget(
        categories:
            cats ??
            const [
              BudgetCat(id: 'c', name: 'C', price: 10, accountUseId: 'a'),
            ],
        accounts: const [
          BudgetAcct(id: 'a', currency: 'EUR', rateToBase: 1),
        ],
        transactions: txs,
        period: BudgetPeriod(asOf: DateTime.utc(2026, 6, 15, 12), months: 3),
      );
    }

    BudgetTx tx(double qty, double price, {double rate = 1}) => BudgetTx(
      id: 't${qty}_$price',
      date: DateTime.utc(2026, 6, 1),
      categoryId: 'c',
      quantity: qty,
      unitPrice: price,
      accountUseId: 'a',
      rateInteract: rate,
      accountCountId: 'a',
      rateCount: rate,
    );

    test('zero, negative, -0 and fractional amounts total correctly', () {
      final s = compute([
        tx(0, 10),
        tx(-1, 10),
        tx(2, -0.0),
        tx(3, 0.333333333333),
      ]);
      expect(_bad(s.factTotal), isFalse);
      expect(compute([tx(0, 10)]).factTotal, 0);
    });

    test('1e308 price and quantity never throw and never give NaN', () {
      for (final t in [
        tx(1, 1e308),
        tx(1e308, 1e308),
        tx(1e308, -1e308),
        tx(1e-300, 1e-300),
        tx(1, double.maxFinite),
      ]) {
        final s = compute([t, tx(2, 3)]);
        expect(s.factTotal.isNaN, isFalse, reason: '${t.quantity} x ${t.unitPrice}');
        expect(s.planTotal.isNaN, isFalse);
        expect(() => s.position, returnsNormally);
      }
    });

    test('NaN and Infinity that slipped into stored rows do not crash the totals', () {
      for (final t in [
        tx(double.nan, 1),
        tx(1, double.nan),
        tx(double.infinity, 1),
        tx(1, double.negativeInfinity),
        tx(1, 1, rate: double.nan),
        tx(1, 1, rate: double.infinity),
      ]) {
        late BudgetSnapshot s;
        expect(() => s = compute([t]), returnsNormally, reason: t.id);
        expect(s.factTotal.isNaN, isFalse, reason: t.id);
      }
    });

    test('rate zero, negative and missing flag noRate instead of dividing', () {
      for (final r in [0.0, -1.0, 5e-324]) {
        final s = computeBudget(
          categories: const [
            BudgetCat(id: 'c', name: 'C', price: 10, accountUseId: 'a'),
          ],
          accounts: [BudgetAcct(id: 'a', currency: 'X', rateToBase: r)],
          transactions: [tx(1, 5, rate: r)],
          period: BudgetPeriod(asOf: DateTime.utc(2026, 6, 15, 12)),
        );
        expect(_bad(s.factTotal), isFalse, reason: 'rate $r');
        expect(_bad(s.planTotal), isFalse, reason: 'rate $r');
      }
    });

    test('a category with a 1e308 price, 0 months and 99999 frequency stays finite or flagged', () {
      final s = compute(
        const [],
        cats: const [
          BudgetCat(
            id: 'c',
            name: 'C',
            price: 1e308,
            frequencyMonths: 99999,
            unitsPerMonth: 1e308,
            accountUseId: 'a',
          ),
          BudgetCat(
            id: 'd',
            name: 'D',
            price: 1,
            frequencyMonths: 0,
            unitsPerMonth: 0,
            accountUseId: 'a',
          ),
        ],
      );
      expect(s.planTotal.isNaN, isFalse);
      expect(s.factTotal.isNaN, isFalse);
    });
  });

  group('budget service refuses unusable numbers', () {
    late AppDatabase db;
    late BudgetService budget;
    late String cat;
    late String acct;

    setUp(() async {
      db = _db();
      budget = BudgetService(db);
      acct = await budget.saveAccount(
        name: 'Euro',
        currency: 'EUR',
        rateToBase: 1,
      );
      cat = await budget.saveCategory(
        CategoryInput(name: 'Food', price: 10, accountUseId: acct),
      );
    });
    tearDown(() => db.close());

    Future<int> txCount() async =>
        (await db.select(db.budgetTransactionsTable).get()).length;

    test('quantity 0, NaN, infinite and absurd are refused; nothing stored', () async {
      for (final q in [0.0, -0.0, double.nan, double.infinity, 1e308, -1e308]) {
        await expectLater(
          () => budget.createTransaction(categoryId: cat, quantity: q),
          throwsA(isA<InvalidNumberException>()),
          reason: 'quantity $q',
        );
      }
      expect(await txCount(), 0);
    });

    test('a negative quantity stays allowed (a refund) and is kept as typed', () async {
      final id = await budget.createTransaction(categoryId: cat, quantity: -2);
      final row = await (db.select(db.budgetTransactionsTable)
            ..where((t) => t.id.equals(id)))
          .getSingle();
      expect(row.quantity, -2);
    });

    test('price NaN / infinite / absurd is refused, 0 and negative are kept', () async {
      for (final p in [double.nan, double.infinity, -double.infinity, 1e308]) {
        await expectLater(
          () => budget.createTransaction(categoryId: cat, unitPrice: p),
          throwsA(isA<InvalidNumberException>()),
          reason: 'price $p',
        );
      }
      final zero = await budget.createTransaction(categoryId: cat, unitPrice: 0);
      final neg = await budget.createTransaction(categoryId: cat, unitPrice: -5);
      final rows = await db.select(db.budgetTransactionsTable).get();
      expect({for (final r in rows) r.id: r.unitPrice}, {zero: 0, neg: -5});
    });

    test('-0 is stored as 0', () async {
      final id = await budget.createTransaction(
        categoryId: cat,
        unitPrice: -0.0,
        quantity: 1,
      );
      final row = await (db.select(db.budgetTransactionsTable)
            ..where((t) => t.id.equals(id)))
          .getSingle();
      expect(row.unitPrice.isNegative, isFalse);
    });

    test('typed rates NaN / infinite are refused; 0 and negative are ignored as before', () async {
      for (final r in [double.nan, double.infinity, 1e308]) {
        await expectLater(
          () => budget.createTransaction(categoryId: cat, rateInteract: r),
          throwsA(isA<InvalidNumberException>()),
          reason: 'rate $r',
        );
      }
      await budget.createTransaction(categoryId: cat, rateInteract: 0);
      await budget.createTransaction(categoryId: cat, rateInteract: -3);
      expect((await db.select(db.budgetAccountsTable).get()).single.rateToBase, 1);
    });

    test('update refuses the same values and leaves the row alone', () async {
      final id = await budget.createTransaction(
        categoryId: cat,
        quantity: 2,
        unitPrice: 4,
      );
      for (final q in [0.0, double.nan, double.infinity]) {
        await expectLater(
          () => budget.updateTransaction(id, quantity: q),
          throwsA(isA<InvalidNumberException>()),
        );
      }
      await expectLater(
        () => budget.updateTransaction(id, unitPrice: double.nan),
        throwsA(isA<InvalidNumberException>()),
      );
      final row = await (db.select(db.budgetTransactionsTable)
            ..where((t) => t.id.equals(id)))
          .getSingle();
      expect((row.quantity, row.unitPrice), (2, 4));
    });

    test('account rate <= 0, NaN, infinite and absurd are refused (still ArgumentError)', () async {
      for (final r in [0.0, -1.0, double.nan, double.infinity, 1e308]) {
        await expectLater(
          () => budget.saveAccount(name: 'X', currency: 'USD', rateToBase: r),
          throwsArgumentError,
          reason: 'rate $r',
        );
      }
      await expectLater(
        () => budget.saveAccount(
          name: 'X',
          currency: 'USD',
          rateToBase: 1,
          openingBalance: double.nan,
        ),
        throwsA(isA<InvalidNumberException>()),
      );
      expect(await db.select(db.budgetAccountsTable).get(), hasLength(1));
    });

    test('category numbers NaN / infinite are refused, zero and negative prices kept', () async {
      for (final bad in [double.nan, double.infinity, 1e308]) {
        await expectLater(
          () => budget.saveCategory(CategoryInput(name: 'B', price: bad)),
          throwsA(isA<InvalidNumberException>()),
        );
        await expectLater(
          () => budget.saveCategory(CategoryInput(name: 'B', frequencyMonths: bad)),
          throwsA(isA<InvalidNumberException>()),
        );
        await expectLater(
          () => budget.saveCategory(CategoryInput(name: 'B', unitsPerMonth: bad)),
          throwsA(isA<InvalidNumberException>()),
        );
        await expectLater(
          () => budget.saveCategory(CategoryInput(name: 'B', percent: bad)),
          throwsA(isA<InvalidNumberException>()),
        );
      }
      await budget.saveCategory(const CategoryInput(name: 'Zero', price: 0));
      await budget.saveCategory(const CategoryInput(name: 'Neg', price: -4));
      expect(await db.select(db.budgetCategoriesTable).get(), hasLength(3));
    });

    test('a template with quantity NaN / infinite is refused, <= 0 falls back to 1', () async {
      await expectLater(
        () => budget.saveTxTemplate(name: 'T', categoryId: cat, quantity: double.infinity),
        throwsA(isA<InvalidNumberException>()),
      );
      await expectLater(
        () => budget.saveTxTemplate(
          name: 'T',
          categoryId: cat,
          unitPrice: double.nan,
        ),
        throwsA(isA<InvalidNumberException>()),
      );
      final id = await budget.saveTxTemplate(
        name: 'T',
        categoryId: cat,
        quantity: 0,
      );
      expect((await budget.txTemplates()).single.id, id);
      expect((await budget.txTemplates()).single.quantity, 1);
    });
  });

  group('growth directions', () {
    late AppDatabase db;
    late MetricService metrics;
    setUp(() {
      db = _db();
      metrics = MetricService(db);
    });
    tearDown(() => db.close());

    test('target 0, negative, NaN, infinite and absurd are refused for count/hours', () async {
      for (final t in [0.0, -1.0, double.nan, double.infinity, 1e300]) {
        await expectLater(
          () => metrics.saveMetric(
            name: 'Run',
            kind: MetricKind.count,
            window: MetricWindow.week,
            target: t,
          ),
          throwsA(isA<InvalidNumberException>()),
          reason: 'target $t',
        );
      }
      expect(await db.select(db.metricsTable).get(), isEmpty);
    });

    test('a huge but sane target and the boolean fixed target work', () async {
      final id = await metrics.saveMetric(
        name: 'Big',
        kind: MetricKind.hours,
        window: MetricWindow.year,
        target: 1e9,
      );
      expect((await db.select(db.metricsTable).get()).single.target, 1e9);
      expect(id, isNotEmpty);
      // A boolean ignores whatever target it is given.
      await metrics.saveMetric(
        name: 'Flag',
        kind: MetricKind.boolean,
        target: double.nan,
      );
      final flag = (await db.select(db.metricsTable).get())
          .firstWhere((m) => m.name == 'Flag');
      expect(flag.target, 1);
    });

    test('progress and urgency rules are total over odd inputs', () {
      expect(progressPercent(5, 0), 0);
      expect(progressPercent(5, -3), 0);
      expect(progressPercent(5, double.nan), 0);
      expect(progressPercent(double.nan, 5), 0);
      expect(progressPercent(5, double.infinity), 0);
      expect(progressPercent(double.infinity, 5).isNaN, isFalse);
      expect(progressPercent(1e300, 1e-300).isNaN, isFalse);
      expect(progressPercent(-5, 10), -50);
      expect(progressPercent(0, 10), 0);
      expect(progressPercent(7, 7), 100);
      expect(progressPercent(1e30, 1), closeTo(1e32, 1e18));
      for (final w in [0.0, 1e-300, 1000, 1e300]) {
        for (final p in [-1e300, -5, 0, 89.9, 90, 90.5, 100, 1e300]) {
          final u = urgencyOf(w.toDouble(), p.toDouble());
          expect(u.isNaN, isFalse, reason: 'w=$w p=$p');
        }
      }
    });
  });

  group('durations and actions', () {
    late AppDatabase db;
    late ActionService actions;
    setUp(() {
      db = _db();
      actions = ActionService(db);
    });
    tearDown(() => db.close());

    test('legacy minutes: negative and overflow fall back / clamp, never throw', () {
      final start = DateTime.utc(2026, 1, 1);
      expect(
        computeActionDuration(startAt: null, endAt: null, legacyEstimatedMinutes: -30),
        defaultActionDuration,
      );
      expect(
        computeActionDuration(startAt: null, endAt: null, legacyEstimatedMinutes: 0),
        defaultActionDuration,
      );
      final huge = computeActionDuration(
        startAt: null,
        endAt: null,
        legacyEstimatedMinutes: 1 << 62,
      );
      expect(huge.isNegative, isFalse);
      expect(huge, lessThanOrEqualTo(const Duration(minutes: kMaxEstimatedMinutes)));
      expect(() => start.add(huge), returnsNormally);
    });

    test('a manual estimate that is negative or beyond 10 years is refused', () async {
      for (final m in [-1, -999999, kMaxEstimatedMinutes + 1, 1 << 62]) {
        await expectLater(
          () => actions.createAction(name: 'x', estimatedMinutes: m),
          throwsA(isA<InvalidNumberException>()),
          reason: '$m',
        );
      }
      final id = await actions.createAction(name: 'ok', estimatedMinutes: 90);
      expect(id, isNotEmpty);
      expect(await db.select(db.actionsTable).get(), hasLength(1));
    });

    test('end before start is stored but start / finish / continue still work', () async {
      final id = await actions.createAction(
        name: 'Backwards',
        startAt: DateTime.utc(2026, 1, 1, 10),
        endAt: DateTime.utc(2026, 1, 1, 9),
      );
      await actions.start(id);
      await actions.finish(id);
      final row = await (db.select(db.actionsTable)..where((t) => t.id.equals(id)))
          .getSingle();
      expect(DateTime.parse(row.endAt!).isBefore(DateTime.parse(row.startAt!)), isFalse);
      final c = await actions.continueSameAction(id);
      expect(c.newActionId, isNotEmpty);
    });

    test('a 10-year action starts, finishes and has its length', () async {
      final start = DateTime.utc(2020, 1, 1);
      final id = await actions.createAction(
        name: 'Decade',
        startAt: start,
        endAt: DateTime.utc(2030, 1, 1),
      );
      final row = await (db.select(db.actionsTable)..where((t) => t.id.equals(id)))
          .getSingle();
      expect(
        computeActionDuration(
          startAt: DateTime.parse(row.startAt!),
          endAt: DateTime.parse(row.endAt!),
        ).inDays,
        3653,
      );
      await actions.start(id);
      await actions.finish(id);
    });

    test('sequence numbers stop at 9 digits and stay parseable', () async {
      final id = await actions.createAction(name: '[#999999999] Daily run');
      final c = await actions.continueSameAction(id);
      final created = await (db.select(db.actionsTable)
            ..where((t) => t.id.equals(c.newActionId)))
          .getSingle();
      final (n, base) = parseSequencePrefix(created.name);
      expect(n, isNotNull, reason: created.name);
      expect(n, lessThanOrEqualTo(999999999));
      expect(base, 'Daily run');
      // And the chain can go on.
      final again = await actions.continueSameAction(c.newActionId);
      expect(again.newActionId, isNotEmpty);
    });

    test('a 10-digit prefix is just text, not a counter', () {
      expect(parseSequencePrefix('[#1234567890] x').$1, isNull);
      expect(parseSequencePrefix('[#0000000001] x').$1, isNull);
      expect(parseSequencePrefix('[#000000001] x').$1, 1);
    });
  });

  group('plan numbers', () {
    PlanItemData monthly(MonthlyRule r, {DateTime? start}) => PlanItemData(
      id: 'p',
      name: 'P',
      kind: PlanKind.monthly,
      startDate: start ?? planDate(2026, 1, 1),
      forever: true,
      monthly: r,
    );

    test('every N months with N = 0 or negative behaves as 1; 99999 gives only the first', () {
      List<String> keys(int every) => [
        for (final o in occurrencesInRange(
          monthly(MonthlyRule(everyMonths: every, day: 5)),
          planDate(2026, 1, 1),
          planDate(2026, 6, 30),
        ))
          o.key,
      ];
      expect(keys(0), keys(1));
      expect(keys(-3), keys(1));
      expect(keys(1), hasLength(6));
      expect(keys(99999), ['2026-01-05#0']);
    });

    test('a range of 99999 months from the start does not hang or throw', () {
      final sw = Stopwatch()..start();
      final all = occurrencesInRange(
        monthly(const MonthlyRule(everyMonths: 1, day: 1)),
        planDate(2026, 1, 1),
        planDate(2026, 12, 31),
      );
      expect(all, hasLength(12));
      expect(sw.elapsedMilliseconds, lessThan(2000));
    });

    test('rule JSON is clamped: cycle days, every N, minutes', () {
      final c = CycleRule.fromJson({'cycleDays': 0, 'occurrences': <Object>[]});
      expect(c.cycleDays, 1);
      expect(CycleRule.fromJson({'cycleDays': -9}).cycleDays, 1);
      expect(CycleRule.fromJson({'cycleDays': 99999999}).cycleDays, 3650);
      expect(MonthlyRule.fromJson({'everyMonths': 0}).everyMonths, 1);
      expect(MonthlyRule.fromJson({'everyMonths': -4}).everyMonths, 1);
      expect(MonthlyRule.fromJson({'everyMonths': 10000000}).everyMonths, 99999);
      expect(MonthlyRule.fromJson({'day': 99}).day, 31);
      expect(MonthlyRule.fromJson({'day': -2}).day, 1);
    });

    test('absurd start minutes and durations in a stored rule do not throw', () {
      for (final startMin in [-1, 100000, 1 << 40, -(1 << 40), 1 << 62]) {
        final item = PlanItemData(
          id: 'p',
          name: 'P',
          kind: PlanKind.cycle,
          startDate: planDate(2026, 1, 1),
          forever: true,
          cycle: CycleRule.fromJson({
            'cycleDays': 1,
            'occurrences': [
              {'day': 0, 'startMin': startMin, 'durationMin': 1 << 40},
            ],
          }),
        );
        late List<PlanOccurrence> out;
        expect(
          () => out = occurrencesInRange(
            item,
            planDate(2026, 1, 1),
            planDate(2026, 1, 3),
          ),
          returnsNormally,
          reason: 'startMin $startMin',
        );
        for (final o in out) {
          expect(o.durationMin, lessThanOrEqualTo(24 * 60 * 7));
          expect(o.endUtc.isBefore(o.startUtc), isFalse);
        }
      }
    });

    test('a huge cycle occurrence day does not throw', () {
      final item = PlanItemData(
        id: 'p',
        name: 'P',
        kind: PlanKind.cycle,
        startDate: planDate(2026, 1, 1),
        forever: true,
        cycle: CycleRule.fromJson({
          'cycleDays': 7,
          'occurrences': [
            {'day': 1 << 60, 'startMin': 60},
            {'day': -5, 'startMin': 60},
          ],
        }),
      );
      expect(
        () => occurrencesInRange(item, planDate(2026, 1, 1), planDate(2026, 1, 31)),
        returnsNormally,
      );
    });

    test('plan companions clamp minutes and gaps', () {
      final c = PlanCompanion.fromJson({'minutes': 1 << 50, 'gapMinutes': -(1 << 50)});
      expect(c.minutes, 24 * 60);
      expect(c.gapMinutes, 0);
    });
  });

  group('treemap with huge areas', () {
    test('squarify copes with 1e300, 0 and negative weights', () {
      for (final values in [
        [1e300, 1e300, 0.0, -5.0, 1.0, 1e-300],
        [double.maxFinite, double.maxFinite, 1.0],
        [double.nan, double.infinity, 2.0],
      ]) {
        final rects = squarify(
          [for (var i = 0; i < values.length; i++) TreemapItem('i$i', values[i])],
          width: 400,
          height: 300,
        );
        for (final r in rects) {
          expect(
            r.w.isNaN || r.h.isNaN || r.x.isNaN || r.y.isNaN,
            isFalse,
            reason: '$values',
          );
        }
      }
    });
  });

  group('validateChange values', () {
    final now = DateTime.utc(2026, 10, 17, 12);
    SyncChange change(Map<String, Object?> extra) => SyncChange(
      table: 'actions',
      rowId: 'r1',
      hlc: '2026-10-10T12:00:00.123Z-0001-devA',
      origin: 'devA',
      deleted: false,
      data: {'id': 'r1', 'name': 'x', ...extra},
      seq: 1,
    );

    test('Infinity (from JSON 1e999), NaN and -Infinity values are refused', () {
      final decoded = jsonDecode('{"v": 1e999, "w": -1e999}') as Map;
      expect(decoded['v'], double.infinity);
      expect(
        validateChange(change({'estimated_minutes': decoded['v']}), now: now),
        'value',
      );
      expect(
        validateChange(change({'estimated_minutes': decoded['w']}), now: now),
        'value',
      );
      expect(
        validateChange(change({'estimated_minutes': double.nan}), now: now),
        'value',
      );
    });

    test('huge ints and doubles beyond the safe range are refused, normal numbers pass', () {
      expect(validateChange(change({'n': 1}), now: now), isNull);
      expect(validateChange(change({'n': -1}), now: now), isNull);
      expect(validateChange(change({'n': 0.5}), now: now), isNull);
      expect(validateChange(change({'n': 9007199254740991}), now: now), isNull);
      expect(validateChange(change({'n': 1e300}), now: now), 'value');
      expect(validateChange(change({'n': 9223372036854775807}), now: now), 'value');
    });

    test('a 5 MB text field is refused, a 3 MB one (large notes) passes', () {
      expect(
        validateChange(change({'notes': 'n' * (5 * 1024 * 1024)}), now: now),
        'value too long',
      );
      expect(
        validateChange(change({'notes': 'n' * (3 * 1024 * 1024)}), now: now),
        isNull,
      );
    });

    test('a tombstone with no data is still fine, a row with 10k columns is refused', () {
      expect(
        validateChange(
          SyncChange(
            table: 'actions',
            rowId: 'r1',
            hlc: '2026-10-10T12:00:00.123Z-0001-devA',
            origin: 'devA',
            deleted: true,
          ),
          now: now,
        ),
        isNull,
      );
      expect(
        validateChange(
          change({for (var i = 0; i < 10000; i++) 'c$i': i}),
          now: now,
        ),
        isNotNull,
      );
    });
  });
}

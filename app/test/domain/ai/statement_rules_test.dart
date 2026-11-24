import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/domain/ai/statement/mcc_hints.dart';
import 'package:livenow/domain/ai/statement/statement_period.dart';
import 'package:livenow/domain/ai/statement/statement_rows.dart';
import 'package:livenow/domain/ai/statement/statement_rules.dart';

int _n = 0;

StatementRow _row(
  String details,
  double card, {
  DateTime? at,
  int? mcc,
  double? op,
  String? opCur,
  double? rate,
  double? fee,
  String? category,
}) =>
    StatementRow(
      index: _n++,
      at: at ?? DateTime(2026, 11, 20, 12),
      details: details,
      mcc: mcc,
      cardAmount: card,
      cardCurrency: 'UAH',
      opAmount: op,
      opCurrency: opCur,
      rate: rate,
      fee: fee,
      bankCategory: category,
    );

const _accounts = [
  StatementAccountRef(id: 'mono', name: 'Моно UAH', currency: 'UAH'),
  StatementAccountRef(id: 'fop', name: 'ФОП Тест', currency: 'UAH'),
  StatementAccountRef(id: 'lira', name: 'Ліра', currency: 'TRY'),
  StatementAccountRef(id: 'bank', name: 'Банка мрії', currency: 'UAH'),
];

List<StatementItem> _run(
  List<StatementRow> rows, {
  Map<String, String> memory = const {},
  String? Function(String)? cards,
}) =>
    classifyStatement(
      rows,
      statementAccountId: 'mono',
      accounts: _accounts,
      partyMemory: memory,
      cardAccount: cards,
    );

void main() {
  test('top-up from an own account is a transfer in', () {
    final i = _run([_row('З гривневого рахунку ФОП', 9000, mcc: 4829)]).single;
    expect(i.kind, StatementKind.transferIn);
    expect(i.counterAccountId, 'fop');
    expect(i.amount, 9000);
  });

  test('jar named like an account is a transfer out; unknown jar needs a decision', () {
    final a = _run([_row('Поповнення «Банка мрії»', -500, mcc: 4829)]).single;
    expect(a.kind, StatementKind.transferOut);
    expect(a.counterAccountId, 'bank');
    final b = _run([_row('Поповнення «Подарунки тест»', -300, mcc: 4829)]).single;
    expect(b.kind, StatementKind.person);
    expect(b.jarName, 'Подарунки тест');
    expect(b.counterAccountId, isNull);
  });

  test('reversal pair is cancelled on both sides, only within 10 minutes', () {
    final t = DateTime(2026, 11, 10, 8, 50);
    final items = _run([
      _row('Скасування. Тест Банк', 250, at: t.add(const Duration(seconds: 1))),
      _row('Тест Банк', -250, at: t),
      _row('Скасування. Інший', 40, at: t),
      _row('Інший', -40, at: t.subtract(const Duration(minutes: 30))),
    ]);
    expect(items[0].kind, StatementKind.cancelled);
    expect(items[1].kind, StatementKind.cancelled);
    expect(items[0].pairIndex, items[1].row.index);
    expect(items[2].kind, isNot(StatementKind.cancelled));
    expect(items[3].kind, StatementKind.purchase);
  });

  test('reversal pair of masked card numbers', () {
    final items = _run([
      _row('Скасування. 123456******4321', 100, mcc: 4829),
      _row('123456******4321', -100, mcc: 4829),
    ]);
    expect(items.map((e) => e.kind), [StatementKind.cancelled, StatementKind.cancelled]);
  });

  test('masked card: own card by last4, otherwise a person-like decision', () {
    final own = _run([_row('123456******4321', -80, mcc: 4829)], cards: (l) => l == '4321' ? 'lira' : null).single;
    expect(own.kind, StatementKind.transferOut);
    expect(own.counterAccountId, 'lira');
    final other = _run([_row('123456******9999', -80, mcc: 4829)]).single;
    expect(other.kind, StatementKind.person);
    expect(other.partyKey, 'card 9999');
  });

  test('foreign purchase keeps the rate pair, hint from MCC', () {
    final i = _run([_row('Test Bazaar', -100, mcc: 5411, op: -110.5, opCur: 'TRY', rate: 0.905)]).single;
    expect(i.kind, StatementKind.purchase);
    expect(i.currency, 'TRY');
    expect(i.amount, 110.5);
    expect(i.rateCount, 110.5);
    expect(i.rateInteract, 100);
    expect(i.hint, 'Продукти');
    final e = _run([_row('Test EUR Shop', -517.6, op: -10, opCur: 'EUR', rate: 51.76)]).single;
    expect(e.currency, 'EUR');
    expect(e.rateCount, 10);
    expect(e.rateInteract, 517.6);
  });

  test('home-currency purchase stays in UAH; the bank category beats the MCC', () {
    final i = _run([_row('Test Cafe', -50, mcc: 5814, op: -50, opCur: 'UAH', category: 'Кав’ярні')]).single;
    expect(i.currency, 'UAH');
    expect(i.rateCount, isNull);
    expect(i.hint, 'Кав’ярні');
  });

  test('person: initial form and "Від:" form share one key; memory is offered', () {
    final items = _run([
      _row('Іван Т.', -3000, mcc: 4829),
      _row('Від: Іван Тестовий', 1000, mcc: 4829),
    ], memory: {'іван т': 'category:abc'});
    expect(items[0].kind, StatementKind.person);
    expect(items[0].partyKey, 'іван т');
    expect(items[1].kind, StatementKind.person);
    expect(items[1].partyKey, 'іван т');
    expect(items[0].remembered, 'category:abc');
    final none = _run([_row('Іван Т.', -3000, mcc: 4829)]).single;
    expect(none.remembered, isNull);
  });

  test('MCC 4829 without shop words is a person; with a shop word it is not', () {
    expect(_run([_row('Марія Тестова', -10, mcc: 4829)]).single.kind, StatementKind.person);
    expect(_run([_row('ТОВ Тест', -10, mcc: 4829)]).single.kind, StatementKind.purchase);
  });

  test('cashback payout, income and a fee item', () {
    final items = _run([
      _row('Виведення кешбеку 11.42₴', 11.42, mcc: 4829),
      _row('Test Employer Pay', 1000, mcc: 6012, category: 'Дохід'),
      _row('Test Market', -100, mcc: 5411, fee: 2.5),
    ]);
    expect(items[0].kind, StatementKind.cashbackIncome);
    expect(items[1].kind, StatementKind.income);
    expect(items[2].kind, StatementKind.purchase);
    expect(items[3].kind, StatementKind.fee);
    expect(items[3].amount, 2.5);
    expect(items, hasLength(4));
  });

  test('mccHint', () {
    expect(mccHint(5411), 'Продукти');
    expect(mccHint(5814), 'Кафе і ресторани');
    expect(mccHint(4131), 'Проїзд');
    expect(mccHint(4722), 'Подорожі');
    expect(mccHint(5912), "Здоров'я");
    expect(mccHint(5651), 'Одяг');
    expect(mccHint(5977), 'Косметика');
    expect(mccHint(4812), "Зв'язок");
    expect(mccHint(5311), 'Покупки');
    expect(mccHint(7999), 'Розваги');
    expect(mccHint(5719), 'Дім');
    expect(mccHint(1), isNull);
  });

  group('periodFromMessage', () {
    final now = DateTime(2026, 11, 24);
    test('month names', () {
      final p = periodFromMessage('виписка за листопад', now)!;
      expect(p.from, DateTime(2026, 11, 1));
      expect(p.to, DateTime(2026, 12, 1));
      final q = periodFromMessage('за грудень', now)!;
      expect(q.from, DateTime(2025, 12, 1));
      expect(periodFromMessage('November 2025', now)!.from, DateTime(2025, 11, 1));
      expect(periodFromMessage('за октябрь', now)!.to, DateTime(2026, 11, 1));
    });
    test('ranges and open ends', () {
      final a = periodFromMessage('від 01.11 до 15.11', now)!;
      expect(a.from, DateTime(2026, 11, 1));
      expect(a.to, DateTime(2026, 11, 16));
      expect(a.contains(DateTime(2026, 11, 15, 23)), isTrue);
      expect(a.contains(DateTime(2026, 11, 16)), isFalse);
      final b = periodFromMessage('з 15.11', now)!;
      expect(b.from, DateTime(2026, 11, 15));
      expect(b.to, isNull);
      final c = periodFromMessage('after 01.11', now)!;
      expect(c.from, DateTime(2026, 11, 2));
      final d = periodFromMessage('01.11 - 10.11', now)!;
      expect(d.from, DateTime(2026, 11, 1));
      expect(d.to, DateTime(2026, 11, 11));
    });
    test('nothing named', () {
      expect(periodFromMessage(null, now), isNull);
      expect(periodFromMessage('це моно картка', now), isNull);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/domain/actions_csv.dart';
import 'package:livenow/domain/postpone_rules.dart';

// Fixtures are rows copied from the Notion export (dev/data/actions).
const header =
    'Name,Datetime,Next actions and time,Previous actions and time,Growth Direction';

void main() {
  setUpAll(initPostponeTimeZoneData);

  test('date only is all-day at Istanbul midnight (UTC+3)', () {
    final p = parseActionsCsv(
      '$header\n💧 Випити літр води,03/10/2026,,,Я випив достатньо води за тиждень\n',
    );
    final a = p.actions.single;
    expect(a.name, '💧 Випити літр води');
    expect(a.isAllDay, isTrue);
    expect(a.start, DateTime.utc(2026, 10, 2, 21));
    expect(a.end, isNull);
    expect(a.directionsCell, 'Я випив достатньо води за тиждень');
  });

  test('timed range, day-first, wall clock to UTC', () {
    final a = parseActionsCsv('$header\n🚿 Душ,03/10/2026 9:00 → 9:20,,,\n')
        .actions
        .single;
    expect(a.isAllDay, isFalse);
    expect(a.start, DateTime.utc(2026, 10, 3, 6, 0));
    expect(a.end, DateTime.utc(2026, 10, 3, 6, 20));
  });

  test('missing end and unreadable date', () {
    final p = parseActionsCsv('$header\nA,03/10/2026 9:00,,,\nB,garbage,,,\n');
    expect(p.actions[0].end, isNull);
    expect(p.actions[0].start, DateTime.utc(2026, 10, 3, 6));
    expect(p.actions[1].start, isNull);
    expect(p.badDates, ['B']);
  });

  test('refs: English months, 12-hour, commas and cross-day end', () {
    final refs = parseRefs(
      'На трансфері в Аланію July 5, 2026 11:45 PM → July 6, 2026 3:45 AM,'
      '[#1] Запитати про ціни (співвіднести, з очікуваннями) August 15, 2026 10:25 AM → 10:29 AM,'
      '🤑 Отримати оплату July 29, 2026 12:02 AM',
    );
    expect(refs.map((r) => r.name), [
      'На трансфері в Аланію',
      '[#1] Запитати про ціни (співвіднести, з очікуваннями)',
      '🤑 Отримати оплату',
    ]);
    expect(refs[0].start, DateTime.utc(2026, 7, 5, 20, 45));
    expect(refs[0].end, DateTime.utc(2026, 7, 6, 0, 45));
    expect(refs[1].start, DateTime.utc(2026, 8, 15, 7, 25));
    expect(refs[1].end, DateTime.utc(2026, 8, 15, 7, 29));
    expect(refs[2].start, DateTime.utc(2026, 7, 28, 21, 2)); // 12:02 AM
    expect(refs[2].end, isNull);
  });

  test('a ref without a stamp is a name-only reference', () {
    final refs = parseRefs('Just a name');
    expect(refs.single.name, 'Just a name');
    expect(refs.single.start, isNull);
  });

  test('direction names: greedy match for names with commas, ’ vs \'', () {
    final known = {
      'Я регулярно їм',
      "Я регулярно перевіряю канали зв'язку зі мною",
      'Я виконую задачі, що призводять до отримання грошей',
    };
    expect(
      splitDirectionNames(
        'Я регулярно перевіряю канали зв’язку зі мною,'
        'Я виконую задачі, що призводять до отримання грошей,Я регулярно їм,Невідомо',
        known,
      ),
      [
        'Я регулярно перевіряю канали зв’язку зі мною',
        'Я виконую задачі, що призводять до отримання грошей',
        'Я регулярно їм',
        'Невідомо',
      ],
    );
    expect(splitDirectionNames('  ', known), isEmpty);
  });

  test('quoted cells and blank rows', () {
    final p = parseActionsCsv(
      '$header\n"Name, with comma",03/10/2026,,,"X,Y"\n,,,,\n ,03/10/2026,,,\n',
    );
    expect(p.actions.single.name, 'Name, with comma');
    expect(p.skippedBlank, 1);
  });

  test('missing Name column throws', () {
    expect(() => parseActionsCsv('Foo\nbar\n'), throwsFormatException);
  });
}

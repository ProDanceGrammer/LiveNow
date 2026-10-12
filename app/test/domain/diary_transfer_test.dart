import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;

import 'package:livenow/core/settings.dart';
import 'package:livenow/domain/diary_transfer.dart';
import 'package:livenow/domain/postpone_rules.dart';

DiaryAction _a(String id, String name, int hour) =>
    DiaryAction(id: id, name: name, startAt: DateTime.utc(2026, 10, 9, hour));

void main() {
  setUpAll(initPostponeTimeZoneData);

  group('pastTense', () {
    test('regular, e, consonant+y, doubling', () {
      expect(pastTense('Implement'), 'Implemented');
      expect(pastTense('Fix'), 'Fixed');
      expect(pastTense('Create'), 'Created');
      expect(pastTense('Study'), 'Studied');
      expect(pastTense('Play'), 'Played');
      expect(pastTense('Stop'), 'Stopped');
      expect(pastTense('Plan'), 'Planned');
      expect(pastTense('Add'), 'Added');
      expect(pastTense('Test'), 'Tested');
    });

    test('irregular keeps the capital letter', () {
      expect(pastTense('Make'), 'Made');
      expect(pastTense('write'), 'wrote');
    });

    test('already past, acronyms and non-Latin words stay', () {
      expect(pastTense('Fixed'), 'Fixed');
      expect(pastTense('API'), 'API');
      expect(pastTense('Розробка'), 'Розробка');
      expect(pastTense('2fa'), '2fa');
    });
  });

  group('buildDiary', () {
    test('the example: groups by first tag, dedupes [#n], past tense', () {
      final result = buildDiary([
        _a('1', '[Target:Jeremy] [JBT:DK-2004] Implement feature', 13),
        _a('2', '[Target:Donald] [JBT:DK-8492] Implement feature', 12),
        _a('3', '[#1] [Target:Jeremy] [JBT:DK-9358] Implement feature', 10),
        _a('4', '[#2] [Target:Jeremy] [JBT:DK-9358] Implement feature', 11),
      ], const []);

      expect([for (final g in result.groups) g.tag], [
        '[Target:Jeremy]',
        '[Target:Donald]',
      ]);
      expect([for (final i in result.groups[0].items) i.text], [
        '[JBT:DK-9358] Implemented feature.',
        '[JBT:DK-2004] Implemented feature.',
      ]);
      expect([for (final i in result.groups[1].items) i.text], [
        '[JBT:DK-8492] Implemented feature.',
      ]);
      // Every variant becomes a Previous action, duplicates included.
      expect(result.matchedIds.toSet(), {'1', '2', '3', '4'});
    });

    test('untagged actions are left out; codes restrict by key or exact tag', () {
      final actions = [
        _a('a', 'Breakfast', 8),
        _a('b', '[KBT:CS-1] Review pull request', 9),
        _a('c', '[Home] Clean kitchen', 10),
      ];
      expect(buildDiary(actions, const []).matchedIds, ['b', 'c']);
      expect(buildDiary(actions, ['kbt']).matchedIds, ['b']);
      expect(buildDiary(actions, ['kbt:cs-1']).matchedIds, ['b']);
      expect(buildDiary(actions, ['kbt:cs-2']).matchedIds, isEmpty);
      expect(buildDiary(actions, ['home']).groups.single.items.single.text,
          'Cleaned kitchen.');
    });

    test('a trailing period is not doubled; nothing matched = empty', () {
      final r = buildDiary([_a('x', '[A] Fix bug.', 9)], const []);
      expect(r.groups.single.items.single.text, 'Fixed bug.');
      expect(buildDiary(const [], const []).isEmpty, isTrue);
    });
  });

  test('parseBlockCodes splits on commas and spaces', () {
    expect(parseBlockCodes(' KBT, Target:Jeremy ;home '), [
      'kbt',
      'target:jeremy',
      'home',
    ]);
    expect(parseBlockCodes(null), isEmpty);
  });

  group('previousWorkingDay', () {
    late final tz.Location loc;
    setUpAll(() => loc = tz.getLocation(AppSettings.timeZoneName));
    const monFri = {1, 2, 3, 4, 5};

    test('Monday goes back to Friday (Istanbul day)', () {
      final monday = DateTime.utc(2026, 10, 12, 7); // 10:00 Istanbul
      final r = previousWorkingDay(monday, monFri, loc)!;
      expect(r.startUtc, DateTime.utc(2026, 10, 8, 21));
      expect(r.endUtc, DateTime.utc(2026, 10, 9, 21));
    });

    test('Wednesday goes back to Tuesday; custom days are honoured', () {
      final wed = DateTime.utc(2026, 10, 14, 7);
      expect(previousWorkingDay(wed, monFri, loc)!.startUtc,
          DateTime.utc(2026, 10, 12, 21));
      // Only Saturday works: from Wednesday the latest Saturday is the 10th.
      expect(previousWorkingDay(wed, const {6}, loc)!.startUtc,
          DateTime.utc(2026, 10, 9, 21));
    });

    test('no working day at all gives null', () {
      expect(previousWorkingDay(DateTime.utc(2026, 10, 12), const {}, loc),
          isNull);
    });
  });
}

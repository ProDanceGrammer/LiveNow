import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/domain/name_sort.dart';

void main() {
  test(
    'leading emoji, ZWJ sequences, skin tones, arrows and quotes are skipped',
    () {
      expect(
        sortKeyIgnoringEmoji('↗️ Занесення в Notion'),
        'занесення в notion',
      );
      expect(
        sortKeyIgnoringEmoji('👨🏻‍👩🏻‍👦🏻‍👦🏻 Поговорити з рідними 38'),
        'поговорити з рідними 38',
      );
      expect(
        sortKeyIgnoringEmoji('👐🏻 🫂 🫦Тактильність+Поцілунки+Обійми'),
        'тактильність+поцілунки+обійми',
      );
      expect(sortKeyIgnoringEmoji('✍🏻 Купити…'), 'купити…');
      expect(sortKeyIgnoringEmoji('"Quoted" word'), 'quoted" word');
      expect(sortKeyIgnoringEmoji('Plain'), 'plain');
      expect(sortKeyIgnoringEmoji(''), '');
      expect(sortKeyIgnoringEmoji('🙂🙂'), '');
    },
  );

  test('a leading digit is kept; only the leading run is stripped', () {
    expect(sortKeyIgnoringEmoji('7 days 🙂'), '7 days 🙂');
  });

  test('sorts Latin and Cyrillic names by letters, ignoring emoji', () {
    final names = [
      '✍🏻 Купити…',
      'banana',
      '↗️ Занесення в Notion',
      '👨🏻‍👩🏻‍👦🏻‍👦🏻 Поговорити з рідними 38',
      'Apple',
      '👐🏻 🫂 🫦Тактильність+Поцілунки+Обійми',
      '🍎 apple',
    ]..sort(compareIgnoringEmoji);
    expect(names, [
      'Apple', // ties with '🍎 apple' on the key: full-name order ('A' < '🍎')
      '🍎 apple',
      'banana',
      '↗️ Занесення в Notion',
      '✍🏻 Купити…',
      '👨🏻‍👩🏻‍👦🏻‍👦🏻 Поговорити з рідними 38',
      '👐🏻 🫂 🫦Тактильність+Поцілунки+Обійми',
    ]);
  });

  test('Dart code-unit order: Ukrainian і sorts after я', () {
    expect(compareIgnoringEmoji('Іван', 'Яблуко') > 0, isTrue);
  });
}

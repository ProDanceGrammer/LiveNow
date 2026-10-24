import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/domain/search_match.dart';

void main() {
  List<String> rank(List<String> items, String q) =>
      rankMatches(items, q, (s) => [s]);

  test('the owner example: whole words first, then the rest, in list order', () {
    expect(
      rank([
        'commit files',
        'IT infrastructure',
        'do it',
        'iterations construction',
      ], 'it'),
      ['IT infrastructure', 'do it', 'commit files', 'iterations construction'],
    );
  });

  test('non-matching items are dropped', () {
    expect(rank(['alpha', 'beta', 'it'], 'it'), ['it']);
  });

  test('Cyrillic is case-insensitive and whole words are found', () {
    expect(
      rank(['Це мій план', 'Прицеп', 'Цеглина', 'ЦЕ добре'], 'це'),
      ['Це мій план', 'ЦЕ добре', 'Прицеп', 'Цеглина'],
    );
  });

  test('punctuation, apostrophes and emoji are word boundaries', () {
    expect(matchTier('do-it now', 'it'), 0);
    expect(matchTier('(it)', 'it'), 0);
    expect(matchTier('🚀 it', 'it'), 0);
    expect(matchTier('don’t stop', "don't"), 0);
    expect(matchTier("it's", 'it'), 0); // "it" then an apostrophe
    expect(matchTier('digit', 'it'), 1);
    expect(matchTier('it2', 'it'), 1); // a digit continues the word
  });

  test('a phrase is a whole match only when its edges are word edges', () {
    expect(matchTier('please do it now', 'do it'), 0);
    expect(matchTier('redo it', 'do it'), 1);
    expect(matchTier('do items', 'do it'), 1);
  });

  test('extra spaces and case do not matter', () {
    expect(matchTier('  Do   IT  ', 'do it'), 0);
    expect(foldSearch('  A   B '), 'a b');
  });

  test('an item found by its primary text beats one found only by a second text', () {
    final items = [
      (name: 'Plan week', note: 'check it'),
      (name: 'Do it', note: ''),
    ];
    final out = rankMatches(items, 'it', (i) => [i.name, i.note]);
    expect(out.map((i) => i.name), ['Do it', 'Plan week']);
  });

  test('an empty query changes nothing', () {
    expect(rank(['b', 'a'], '  '), ['b', 'a']);
  });

  test('the order inside a tier is the order the items came in', () {
    expect(
      rank(['x it 3', 'x it 1', 'x it 2'], 'it'),
      ['x it 3', 'x it 1', 'x it 2'],
    );
  });

  test('orderByMatch keeps unmatched items, last', () {
    final out = orderByMatch(
      ['commit files', 'found in notes', 'do it'],
      'it',
      (s) => [s],
    );
    expect(out, ['do it', 'commit files', 'found in notes']);
  });
}

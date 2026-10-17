import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/domain/plan_item_search.dart';

void main() {
  bool m(
    String q, {
    String name = 'Gym',
    String description = 'Every day 09:00 · 30 min',
    List<String> collections = const [],
  }) => planItemMatchesSearch(
    q,
    name: name,
    description: description,
    collectionNames: collections,
  );

  test('an empty or blank query matches everything', () {
    expect(m(''), isTrue);
    expect(m('   '), isTrue);
  });

  test('matches the name in any case, Cyrillic too', () {
    expect(m('gYm'), isTrue);
    expect(m('БІГ', name: 'Бігати вранці'), isTrue);
    expect(m('вран', name: 'Бігати вранці'), isTrue);
    expect(m('swim'), isFalse);
  });

  test('matches the description and the collection names', () {
    expect(m('09:00'), isTrue);
    expect(m('every day'), isTrue);
    expect(m('summer', collections: ['Summer', 'Sport']), isTrue);
    expect(m('winter', collections: ['Summer']), isFalse);
  });

  test('every word must match, in any order', () {
    expect(m('gym sport', collections: ['Sport']), isTrue);
    expect(m('sport gym', collections: ['Sport']), isTrue);
    expect(m('gym swim', collections: ['Sport']), isFalse);
  });
}

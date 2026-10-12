import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/domain/direction_search.dart';
import 'package:livenow/domain/growth_rules.dart';

GrowthMetric m(String id, String name, {String? icon}) =>
    GrowthMetric(id: id, name: name, kind: MetricKind.count, icon: icon);

void main() {
  final all = [
    m('1', 'Я регулярно їм', icon: '🍽'),
    m('2', 'Я практикую програмування'),
    m('3', 'Я роблю багато, щоб мої очікування'),
    m('4', 'Достатньо сплю', icon: '🛏'),
    m('5', 'Moms’ time'),
    m('6', 'Програма дня'),
  ];

  List<String> ids(String q, {int limit = 8}) => [
    for (final x in searchDirections(all, q, limit: limit)) x.id,
  ];

  test('matches ignoring case, Cyrillic included', () {
    expect(ids('ПРОГРАМ'), ['6', '2']);
    expect(ids('ЇМ'), ['1']);
  });

  test('prefix matches come first', () {
    expect(ids('про'), ['6', '2']);
    expect(ids('до'), ['4']);
  });

  test('an emoji finds the icon, apostrophes are interchangeable', () {
    expect(ids('🛏'), ['4']);
    expect(ids("moms' t"), ['5']);
  });

  test('empty query and no match give nothing; the limit applies', () {
    expect(ids('  '), isEmpty);
    expect(ids('zzz'), isEmpty);
    expect(ids('я', limit: 2).length, 2);
  });
}

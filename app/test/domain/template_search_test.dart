import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/domain/template_search.dart';

void main() {
  final names = {'m1': 'я регулярно їм', 'm2': 'сон'};
  String payload(List<String> ids) =>
      jsonEncode({'name': 'x', 'metricIds': ids});

  bool match(String name, List<String> ids, String q) => templateMatches(
    name: name,
    payloadJson: payload(ids),
    query: q,
    directionNames: names,
  );

  test('matches the template name or any linked direction name', () {
    expect(match('Обід', ['m1'], 'обід'), isTrue);
    expect(match('Обід', ['m1'], 'регуляр'), isTrue); // by direction
    expect(match('Обід', ['m2'], 'регуляр'), isFalse);
    expect(match('Обід', [], 'сон'), isFalse);
  });

  test(
    'empty query matches all; deleted directions and bad payloads are ignored',
    () {
      expect(match('a', [], ''), isTrue);
      expect(match('a', ['gone'], 'x'), isFalse);
      expect(
        templateMatches(
          name: 'a',
          payloadJson: 'not json',
          query: 'я',
          directionNames: names,
        ),
        isFalse,
      );
      expect(templateMetricIds('{"metricIds":["a",1,"b"]}'), ['a', 'b']);
      expect(templateMetricIds('{}'), isEmpty);
    },
  );
}

import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/domain/template_sort.dart';

TemplateSortInfo _i(
  String name, {
  String? dir,
  double? u,
  int? avg,
  int? manual,
}) => TemplateSortInfo(
  name: name,
  direction: dir,
  urgency: u,
  averageMinutes: avg,
  manualMinutes: manual,
);

void main() {
  final items = {
    'b': _i('b', dir: 'Zeta', u: 10, avg: 30, manual: 60),
    'a': _i('a', dir: 'Alpha', u: 300, avg: 10),
    'c': _i('c'),
    'd': _i('d', dir: 'Alpha', u: 5, manual: 15),
  };
  List<String> run(List<TemplateSortKey> s) => sortTemplates(
    items.keys.toList(),
    s,
    (k) => items[k]!,
  );

  test('name and the default tie-break', () {
    expect(run(const [TemplateSortKey(TemplateSortField.name)]), [
      'a', 'b', 'c', 'd', //
    ]);
    expect(
      run(const [TemplateSortKey(TemplateSortField.name, ascending: false)]),
      ['d', 'c', 'b', 'a'],
    );
    expect(run(const []), ['a', 'b', 'c', 'd']);
  });

  test('missing values go last in both directions', () {
    expect(run(const [TemplateSortKey(TemplateSortField.urgency)]), [
      'd', 'b', 'a', 'c', //
    ]);
    expect(
      run(const [TemplateSortKey(TemplateSortField.urgency, ascending: false)]),
      ['a', 'b', 'd', 'c'],
    );
    expect(run(const [TemplateSortKey(TemplateSortField.manual)]), [
      'd', 'b', 'a', 'c', //
    ]);
    expect(
      run(const [TemplateSortKey(TemplateSortField.average, ascending: false)]),
      ['b', 'a', 'c', 'd'], // c and d have no average: name order
    );
  });

  test('waterfall: direction, then urgency descending', () {
    expect(
      run(const [
        TemplateSortKey(TemplateSortField.direction),
        TemplateSortKey(TemplateSortField.urgency, ascending: false),
      ]),
      ['a', 'd', 'b', 'c'],
    );
  });

  test('firstDirectionName ignores a leading emoji', () {
    expect(firstDirectionName(['🏃 Zeta', '💧 Alpha']), '💧 Alpha');
    expect(firstDirectionName(const []), isNull);
  });
}

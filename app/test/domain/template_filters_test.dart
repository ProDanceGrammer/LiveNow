import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/domain/template_filters.dart';

void main() {
  bool m(
    TemplateFilters f, {
    String name = 'Walk',
    int? avg,
    Set<String> ids = const {},
  }) => f.matches(name: name, averageMinutes: avg, metricIds: ids);

  test('no filters match everything and are not active', () {
    const f = TemplateFilters();
    expect(f.active, isFalse);
    expect(m(f), isTrue);
    expect(m(f, avg: 5, ids: {'a'}), isTrue);
  });

  test('name is a case-insensitive contains, Cyrillic included', () {
    const f = TemplateFilters(nameText: 'спорт');
    expect(f.active, isTrue);
    expect(m(f, name: 'Заняття СПОРТОМ'), isTrue);
    expect(m(f, name: 'Walk'), isFalse);
  });

  test('average range is inclusive; no average is hidden only with a bound', () {
    const f = TemplateFilters(minAverage: 10, maxAverage: 20);
    expect(m(f, avg: 10), isTrue);
    expect(m(f, avg: 20), isTrue);
    expect(m(f, avg: 9), isFalse);
    expect(m(f, avg: 21), isFalse);
    expect(m(f), isFalse); // never run
    expect(m(const TemplateFilters(minAverage: 10), avg: 500), isTrue);
    expect(m(const TemplateFilters(maxAverage: 10), avg: 5), isTrue);
    expect(m(const TemplateFilters(nameText: 'w')), isTrue); // no bound
  });

  test('include: any vs all', () {
    const any = TemplateFilters(includeIds: {'a', 'b'});
    const all = TemplateFilters(includeIds: {'a', 'b'}, allIncluded: true);
    expect(m(any, ids: {'a'}), isTrue);
    expect(m(any, ids: {'c'}), isFalse);
    expect(m(any), isFalse);
    expect(m(all, ids: {'a'}), isFalse);
    expect(m(all, ids: {'a', 'b', 'c'}), isTrue);
  });

  test('exclude hides templates linked to any excluded direction', () {
    const f = TemplateFilters(excludeIds: {'x'});
    expect(m(f, ids: {'x', 'a'}), isFalse);
    expect(m(f, ids: {'a'}), isTrue);
    expect(m(f), isTrue);
  });

  test('include and exclude together', () {
    const f = TemplateFilters(includeIds: {'a'}, excludeIds: {'x'});
    expect(m(f, ids: {'a'}), isTrue);
    expect(m(f, ids: {'a', 'x'}), isFalse);
    expect(m(f, ids: {'x'}), isFalse);
  });

  test('copyWith can clear the bounds', () {
    final f = const TemplateFilters(minAverage: 1, maxAverage: 2)
        .copyWith(clearMinAverage: true);
    expect(f.minAverage, isNull);
    expect(f.maxAverage, 2);
    expect(f.copyWith(clearMaxAverage: true).active, isFalse);
  });
}

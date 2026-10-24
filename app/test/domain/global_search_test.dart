import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/core/ids.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/data/global_search_index.dart';
import 'package:livenow/domain/action_service.dart';
import 'package:livenow/domain/global_search.dart';
import 'package:livenow/domain/metric_service.dart';
import 'package:livenow/domain/growth_rules.dart' show MetricKind;
import 'package:livenow/domain/postpone_rules.dart';

SearchHit hit(
  String id,
  String title, {
  SearchSection section = SearchSection.actions,
  String subtitle = '',
  DateTime? changed,
}) => SearchHit(
  section: section,
  id: id,
  title: title,
  subtitle: subtitle,
  changedAt: changed,
);

void main() {
  setUpAll(initPostponeTimeZoneData);

  final now = DateTime.utc(2026, 10, 24, 12);
  DateTime ago(int days) => now.subtract(Duration(days: days));
  List<String> ids(List<SearchHit> l) => [for (final h in l) h.id];

  group('searchHits', () {
    final all = [
      hit('commit', 'commit files', changed: ago(1)),
      hit('infra', 'IT infrastructure', changed: ago(20)),
      hit('iter', 'iterations construction', changed: ago(2)),
      hit('doit', 'do it', changed: ago(10)),
    ];

    test('whole words first (newest first inside), then the rest newest first', () {
      expect(
        ids(searchHits(all, query: 'it', nowUtc: now)),
        ['doit', 'infra', 'commit', 'iter'],
      );
    });

    test('an empty query lists the most recently changed things', () {
      expect(
        ids(searchHits(all, nowUtc: now)),
        ['commit', 'iter', 'doit', 'infra'],
      );
    });

    test('a hit only in the subtitle counts after the title hits of its tier', () {
      final rows = [
        hit('a', 'Lunch', section: SearchSection.transactions, subtitle: 'Food it', changed: ago(1)),
        hit('b', 'It costs', section: SearchSection.transactions, changed: ago(5)),
      ];
      expect(ids(searchHits(rows, query: 'it', nowUtc: now)), ['b', 'a']);
    });

    test('sections narrow the list (empty = all)', () {
      final rows = [
        hit('a', 'it one'),
        hit('d', 'it two', section: SearchSection.directions),
      ];
      expect(
        ids(searchHits(rows, query: 'it', nowUtc: now, sections: {SearchSection.directions})),
        ['d'],
      );
      expect(ids(searchHits(rows, query: 'it', nowUtc: now)).length, 2);
    });

    test('the updated menu keeps only what changed within the period', () {
      expect(
        ids(searchHits(all, nowUtc: now, updated: UpdatedWithin.week)),
        ['commit', 'iter'],
      );
      expect(
        ids(searchHits(all, nowUtc: now, updated: UpdatedWithin.month)).length,
        4,
      );
      // Unknown change times are only in "Any time".
      final withUnknown = [...all, hit('u', 'unknown')];
      expect(
        ids(searchHits(withUnknown, nowUtc: now, updated: UpdatedWithin.year)),
        isNot(contains('u')),
      );
      expect(ids(searchHits(withUnknown, nowUtc: now)), contains('u'));
    });

    test('Today means since the start of the day', () {
      final rows = [
        hit('new', 'new', changed: now.subtract(const Duration(minutes: 5))),
        hit('old', 'old', changed: ago(2)),
      ];
      expect(
        ids(searchHits(rows, nowUtc: now, updated: UpdatedWithin.today)),
        ['new'],
      );
    });

    test('the lists are cut at their limits', () {
      final many = [
        for (var i = 0; i < 300; i++) hit('$i', 'item $i', changed: ago(i % 50)),
      ];
      expect(searchHits(many, nowUtc: now).length, kSearchRecentCount);
      expect(
        searchHits(many, query: 'item', nowUtc: now).length,
        kSearchResultLimit,
      );
    });
  });

  group('loadSearchHits', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('reads every section with a change time (also for rows with no updated_at)', () async {
      final actions = ActionService(db);
      await actions.createAction(name: 'IT infrastructure');
      await MetricService(db).saveMetric(
        name: 'Я веду графік',
        kind: MetricKind.boolean,
      );
      await db
          .into(db.actionTemplatesTable)
          .insert(
            ActionTemplatesTableCompanion.insert(
              id: newId(),
              name: 'Shower',
              payload: '{}',
            ),
          );
      final hits = await loadSearchHits(db);
      final by = {for (final h in hits) h.title: h};
      expect(by['IT infrastructure']!.section, SearchSection.actions);
      expect(by['Я веду графік']!.section, SearchSection.directions);
      expect(by['Shower']!.section, SearchSection.templates);
      // The sync triggers stamped them just now, templates and directions too.
      for (final t in ['IT infrastructure', 'Я веду графік', 'Shower']) {
        expect(by[t]!.changedAt, isNotNull, reason: t);
        expect(
          DateTime.now().toUtc().difference(by[t]!.changedAt!).inMinutes.abs(),
          lessThan(5),
          reason: t,
        );
      }
    });
  });
}

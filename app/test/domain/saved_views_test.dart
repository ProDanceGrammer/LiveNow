import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/all_actions_view_rules.dart';
import 'package:livenow/domain/budget_tx_view_rules.dart';
import 'package:livenow/domain/date_range_filter.dart';
import 'package:livenow/domain/postpone_rules.dart';
import 'package:livenow/domain/saved_view_service.dart';
import 'package:livenow/domain/saved_views.dart';

void main() {
  setUpAll(initPostponeTimeZoneData);

  late AppDatabase db;
  late SavedViewService service;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    service = SavedViewService(db);
  });
  tearDown(() => db.close());

  const screen = ViewScreens.budgetTransactions;

  group('service', () {
    test('saves a view and reads it back with its parts', () async {
      final id = await service.save(
        screen: screen,
        name: 'Big ones',
        kind: SavedViewKind.both,
        sort: {'keys': []},
        filter: {'categories': ['c1']},
      );
      final v = (await service.all(screen)).single;
      expect((v.id, v.name, v.kind), (id, 'Big ones', SavedViewKind.both));
      expect(v.sort, {'keys': []});
      expect(v.filter['categories'], ['c1']);
      expect(v.isDefault, isFalse);
    });

    test('a sort-only view stores no filter, and the other way round', () async {
      await service.save(
        screen: screen,
        name: 'S',
        kind: SavedViewKind.sort,
        sort: {'a': 1},
        filter: {'b': 2},
      );
      await service.save(
        screen: screen,
        name: 'F',
        kind: SavedViewKind.filter,
        sort: {'a': 1},
        filter: {'b': 2},
      );
      final byName = {for (final v in await service.all(screen)) v.name: v};
      expect(byName['S']!.filter, isEmpty);
      expect(byName['S']!.sort, {'a': 1});
      expect(byName['F']!.sort, isEmpty);
      expect(byName['F']!.filter, {'b': 2});
    });

    test('the same name (any case) replaces in place and keeps the default flag', () async {
      final id = await service.save(
        screen: screen,
        name: 'Mine',
        kind: SavedViewKind.sort,
        sort: {'v': 1},
      );
      await service.setDefault(id);
      final again = await service.save(
        screen: screen,
        name: 'mine',
        kind: SavedViewKind.both,
        sort: {'v': 2},
      );
      expect(again, id);
      final all = await service.all(screen);
      expect(all, hasLength(1));
      expect(all.single.sort, {'v': 2});
      expect(all.single.kind, SavedViewKind.both);
      expect(all.single.isDefault, isTrue);
    });

    test('the same name on another screen is a different view', () async {
      await service.save(screen: screen, name: 'X', kind: SavedViewKind.sort);
      await service.save(
        screen: ViewScreens.actionsAll,
        name: 'X',
        kind: SavedViewKind.sort,
      );
      expect(await service.all(screen), hasLength(1));
      expect(await service.all(ViewScreens.actionsAll), hasLength(1));
    });

    test('only one default per screen; other screens keep theirs', () async {
      final a = await service.save(screen: screen, name: 'A', kind: SavedViewKind.sort);
      final b = await service.save(screen: screen, name: 'B', kind: SavedViewKind.sort);
      final other = await service.save(
        screen: ViewScreens.actionsAll,
        name: 'O',
        kind: SavedViewKind.sort,
      );
      await service.setDefault(other);
      await service.setDefault(a);
      await service.setDefault(b);
      final defaults = {
        for (final v in await service.all(screen)) v.name: v.isDefault,
      };
      expect(defaults, {'A': false, 'B': true});
      expect(
        (await service.all(ViewScreens.actionsAll)).single.isDefault,
        isTrue,
      );
      await service.setDefault(b, on: false);
      expect(defaultViewOf(await service.all(screen)), isNull);
    });

    test('rename refuses a name another view has', () async {
      final a = await service.save(screen: screen, name: 'A', kind: SavedViewKind.sort);
      await service.save(screen: screen, name: 'B', kind: SavedViewKind.sort);
      expect(await service.rename(a, 'b'), isFalse);
      expect(await service.rename(a, 'C'), isTrue);
      expect(await service.rename(a, '   '), isFalse);
      expect({for (final v in await service.all(screen)) v.name}, {'B', 'C'});
    });

    test('delete returns the row and undo puts it back', () async {
      final id = await service.save(
        screen: screen,
        name: 'Gone',
        kind: SavedViewKind.sort,
        sort: {'k': 1},
      );
      final row = await service.delete(id);
      expect(await service.all(screen), isEmpty);
      await service.undoDelete(row!);
      expect((await service.all(screen)).single.sort, {'k': 1});
    });

    test('views are stamped for sync like every other row', () async {
      final id = await service.save(screen: screen, name: 'S', kind: SavedViewKind.sort);
      final rows = await db
          .customSelect(
            "SELECT row_id FROM sync_versions WHERE tbl = 'saved_views' AND deleted = 0",
          )
          .get();
      expect([for (final r in rows) r.read<String>('row_id')], [id]);
      await service.delete(id);
      final dead = await db
          .customSelect(
            "SELECT deleted FROM sync_versions WHERE tbl = 'saved_views'",
          )
          .get();
      expect(dead.single.read<int>('deleted'), 1);
    });

    test('a nameless view is refused', () async {
      expect(
        () => service.save(screen: screen, name: '  ', kind: SavedViewKind.sort),
        throwsArgumentError,
      );
    });
  });

  group('defaultViewOf', () {
    SavedViewItem v(String id, bool def, String at) => SavedViewItem(
      id: id,
      screen: screen,
      name: id,
      kind: SavedViewKind.sort,
      isDefault: def,
      updatedAt: at,
    );

    test('two devices each marked one: the newest edit wins', () {
      expect(
        defaultViewOf([v('a', true, '2026-01-01'), v('b', true, '2026-02-01')])!.id,
        'b',
      );
    });

    test('none marked: null', () {
      expect(defaultViewOf([v('a', false, '2026-01-01')]), isNull);
    });
  });

  group('codecs', () {
    test('transactions: sort + group round trip; unknown fields are skipped', () {
      final j = txSortToJson(
        const [
          TxSortKey(TxSortField.amount, ascending: false),
          TxSortKey(TxSortField.name),
        ],
        TxGroupBy.category,
      );
      final back = txSortFromJson(j);
      expect(back.sort, const [
        TxSortKey(TxSortField.amount, ascending: false),
        TxSortKey(TxSortField.name),
      ]);
      expect(back.group, TxGroupBy.category);
      final newer = txSortFromJson({
        'keys': [
          {'f': 'fromTheFuture', 'asc': true},
          {'f': 'date', 'asc': false},
        ],
      });
      expect(newer.sort, const [TxSortKey(TxSortField.date, ascending: false)]);
      expect(newer.group, TxGroupBy.action);
    });

    test('transactions: filters round trip and drop deleted categories / accounts', () {
      final filters = TxFilters(
        categoryIds: const {'c1', 'gone'},
        excludeCategories: true,
        accountIds: const {'a1', 'a-gone'},
        action: TxActionLink.linked,
        actionIds: const {'x'},
        dateRange: DateRangeFilter(
          from: DateTime.utc(2026, 1, 1),
          until: DateTime.utc(2026, 2, 1),
        ),
      );
      final j = txFilterToJson(filters, const TxSearchFlags(category: false));
      final back = txFilterFromJson(
        j,
        knownCategoryIds: {'c1'},
        knownAccountIds: {'a1'},
      );
      expect(back.filters.categoryIds, {'c1'});
      expect(back.filters.accountIds, {'a1'});
      expect(back.filters.excludeCategories, isTrue);
      expect(back.filters.action, TxActionLink.linked);
      expect(back.filters.actionIds, {'x'});
      expect(back.filters.dateRange, filters.dateRange);
      expect(back.flags.category, isFalse);
      expect(back.flags.name, isTrue);
      // Without a known set every id stays.
      expect(txFilterFromJson(j).filters.categoryIds, {'c1', 'gone'});
    });

    test('a damaged or empty payload loads as the defaults', () {
      expect(decodeViewPayload('not json').sort, isEmpty);
      expect(txFilterFromJson(const {}).filters.active, isFalse);
      expect(txSortFromJson(const {}).sort, isEmpty);
    });

    test('actions All: sort and filters round trip', () {
      final f = AllActionsFilters(
        nameText: 'run',
        metricIds: const {'m1'},
        allMetrics: true,
        directionsMode: LinkMode.has,
        previous: const LinkFilter(mode: LinkMode.linkedTo, actionId: 'p'),
        minMinutes: 10,
        maxUrgency: 99.5,
        dateRange: DateRangeFilter(from: DateTime.utc(2026, 3, 1)),
      );
      final j = allFilterToJson(f, const SearchFlags(notes: true));
      final back = allFilterFromJson(j);
      expect(back.filters.nameText, 'run');
      expect(back.filters.metricIds, {'m1'});
      expect(back.filters.allMetrics, isTrue);
      expect(back.filters.directionsMode, LinkMode.has);
      expect(back.filters.previous, f.previous);
      expect((back.filters.minMinutes, back.filters.maxUrgency), (10, 99.5));
      expect(back.filters.dateRange, f.dateRange);
      expect(back.flags.notes, isTrue);

      final sort = allSortFromJson(
        allSortToJson(const [SortKey(SortField.start, ascending: false)]),
      );
      expect(sort, const [SortKey(SortField.start, ascending: false)]);
    });

    group('quick date choices are saved as a choice, not as dates', () {
      test('transactions: a choice is stored by name, without any date', () {
        const f = TxFilters(dateRange: DateRangeFilter(preset: DatePreset.lastWeek));
        final j = txFilterToJson(f, const TxSearchFlags());
        expect(j['range'], {'preset': 'lastWeek'});
        final back = txFilterFromJson(j);
        expect(back.filters.dateRange.preset, DatePreset.lastWeek);
        expect(back.filters.dateRange.from, isNull);
        expect(back.filters.dateRange.until, isNull);
        expect(back.filters.dateRange, f.dateRange);
      });

      test('actions All: the same', () {
        const f = AllActionsFilters(
          dateRange: DateRangeFilter(preset: DatePreset.monthRest),
        );
        final j = allFilterToJson(f, const SearchFlags());
        expect(j['range'], {'preset': 'monthRest'});
        expect(allFilterFromJson(j).filters.dateRange.preset, DatePreset.monthRest);
      });

      test('every choice survives the round trip', () {
        for (final p in DatePreset.values) {
          final f = TxFilters(dateRange: DateRangeFilter(preset: p));
          final back = txFilterFromJson(txFilterToJson(f, const TxSearchFlags()));
          expect(back.filters.dateRange.preset, p, reason: p.name);
        }
      });

      test('reopened a week later it means the NEW week', () {
        const f = TxFilters(dateRange: DateRangeFilter(preset: DatePreset.lastWeek));
        final saved = txFilterToJson(f, const TxSearchFlags());
        final monday = DateTime.utc(2026, 10, 19, 9); // Mon 19 Oct, 12:00 Istanbul
        final reopened = txFilterFromJson(saved).filters.dateRange;

        final thisWeek = reopened.resolved(monday);
        final later = reopened.resolved(monday.add(const Duration(days: 7)));
        expect(DateRangeFilter.dayOf(thisWeek.from!), DateTime(2026, 10, 12));
        expect(DateRangeFilter.dayOf(thisWeek.until!), DateTime(2026, 10, 18));
        expect(DateRangeFilter.dayOf(later.from!), DateTime(2026, 10, 19));
        expect(DateRangeFilter.dayOf(later.until!), DateTime(2026, 10, 25));
      });

      test('a custom range keeps its two days; old saved views (dates only) still load', () {
        final f = TxFilters(
          dateRange: DateRangeFilter(
            from: DateTime.utc(2026, 1, 1),
            until: DateTime.utc(2026, 2, 1),
          ),
        );
        final j = txFilterToJson(f, const TxSearchFlags());
        expect((j['range']! as Map).containsKey('preset'), isFalse);
        expect(txFilterFromJson(j).filters.dateRange, f.dateRange);

        final old = txFilterFromJson({
          'range': {
            'from': '2026-03-01T00:00:00.000Z',
            'until': '2026-03-31T00:00:00.000Z',
          },
        });
        expect(old.filters.dateRange.preset, isNull);
        expect(old.filters.dateRange.from, DateTime.utc(2026, 3, 1));
        expect(old.filters.dateRange.until, DateTime.utc(2026, 3, 31));
      });

      test('an unknown choice (a view from another build) means no date range', () {
        final back = txFilterFromJson({
          'range': {'preset': 'fromTheFuture'},
        });
        expect(back.filters.dateRange.active, isFalse);
        final all = allFilterFromJson({
          'range': {'preset': 'fromTheFuture', 'from': '2026-03-01T00:00:00.000Z'},
        });
        expect(all.filters.dateRange.active, isFalse);
      });
    });
  });
}

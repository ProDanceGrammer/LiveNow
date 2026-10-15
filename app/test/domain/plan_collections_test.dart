import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/action_service.dart';
import 'package:livenow/domain/plan_rules.dart';
import 'package:livenow/domain/plan_service.dart';
import 'package:livenow/domain/postpone_rules.dart';

/// Plan collections: which items are visible, the service (create, rename,
/// show/hide, delete with Undo, membership) and that hiding only hides ghosts.
void main() {
  setUpAll(initPostponeTimeZoneData);

  PlanItemData item(String id, [List<String> collections = const []]) =>
      PlanItemData(
        id: id,
        name: id,
        kind: PlanKind.cycle,
        startDate: planDate(2026, 10, 19),
        collectionIds: collections,
      );

  group('visiblePlanItemIds', () {
    test('an item in no collection is always visible', () {
      final v = visiblePlanItemIds([item('a')], {'c1': false});
      expect(v, {'a'});
    });

    test('hidden collection hides its items; visible one shows them', () {
      final items = [item('a', ['c1']), item('b', ['c2']), item('c')];
      expect(
        visiblePlanItemIds(items, {'c1': false, 'c2': true}),
        {'b', 'c'},
      );
    });

    test('an item in several collections shows while ANY is visible', () {
      final items = [item('a', ['c1', 'c2'])];
      expect(visiblePlanItemIds(items, {'c1': false, 'c2': true}), {'a'});
      expect(visiblePlanItemIds(items, {'c1': false, 'c2': false}), isEmpty);
    });

    test('ids of deleted collections do not count', () {
      // Only a dead id: as good as no collection.
      expect(visiblePlanItemIds([item('a', ['gone'])], {}), {'a'});
      // A dead id next to a hidden collection: the hidden one decides.
      expect(
        visiblePlanItemIds([item('a', ['gone', 'c1'])], {'c1': false}),
        isEmpty,
      );
    });

    test('decodeCollectionIds tolerates damage', () {
      expect(decodeCollectionIds(null), isEmpty);
      expect(decodeCollectionIds('not json'), isEmpty);
      expect(decodeCollectionIds('{"a":1}'), isEmpty);
      expect(decodeCollectionIds('["x",3,"y"]'), ['x', 'y']);
    });
  });

  group('PlanService collections', () {
    late AppDatabase db;
    late PlanService plans;

    setUp(() {
      db = AppDatabase.forTesting(
        NativeDatabase.memory(
          setup: (raw) => raw.execute('PRAGMA foreign_keys = ON;'),
        ),
      );
      plans = PlanService(db, ActionService(db));
    });
    tearDown(() => db.close());

    Future<String> daily(String name, {List<String> collections = const []}) =>
        plans.saveItem(
          PlanItemInput(
            name: name,
            kind: PlanKind.cycle,
            startDate: planDate(2026, 10, 19),
            collectionIds: collections,
            cycle: const CycleRule(
              cycleDays: 1,
              occurrences: [CycleOccurrence(day: 0, startMin: 9 * 60)],
            ),
          ),
        );

    test('create, rename and show / hide', () async {
      final id = await plans.saveCollection(name: '  Sport ');
      expect((await plans.collections()).single.name, 'Sport');
      expect((await plans.collections()).single.visible, isTrue);
      await plans.saveCollection(id: id, name: 'Gym');
      expect((await plans.collections()).single.name, 'Gym');
      await plans.setCollectionVisible(id, false);
      expect((await plans.collections()).single.visible, isFalse);
      await plans.setAllCollectionsVisible(true);
      expect((await plans.collections()).single.visible, isTrue);
      expect(
        () => plans.saveCollection(name: '  '),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('membership is stored with the item and survives a rule change', () async {
      final a = await plans.saveCollection(name: 'A');
      final b = await plans.saveCollection(name: 'B');
      final id = await daily('Breakfast', collections: [a, b]);
      var row = (await plans.items()).single;
      expect(plans.decode(row).collectionIds, [a, b]);
      await plans.setItemCollections(id, [b]);
      row = (await plans.items()).single;
      expect(plans.decode(row).collectionIds, [b]);
      await plans.setItemCollections(id, []);
      expect((await plans.items()).single.collections, isNull);
    });

    test('deleting a collection keeps its items and Undo restores it all', () async {
      final a = await plans.saveCollection(name: 'A');
      final b = await plans.saveCollection(name: 'B');
      final i1 = await daily('One', collections: [a, b]);
      final i2 = await daily('Two', collections: [a]);
      final i3 = await daily('Three');

      final undo = await plans.deleteCollection(a);
      expect(undo, isNotNull);
      expect((await plans.collections()).map((c) => c.id), [b]);
      final byId = {for (final r in await plans.items()) r.id: plans.decode(r)};
      expect(byId.length, 3);
      expect(byId[i1]!.collectionIds, [b]);
      expect(byId[i2]!.collectionIds, isEmpty);
      expect(byId[i3]!.collectionIds, isEmpty);

      await plans.undoDeleteCollection(undo!);
      expect((await plans.collections()).length, 2);
      final back = {for (final r in await plans.items()) r.id: plans.decode(r)};
      expect(back[i1]!.collectionIds, [a, b]);
      expect(back[i2]!.collectionIds, [a]);
      expect(await plans.deleteCollection('nope'), isNull);
    });

    test('hiding a collection changes nothing about confirming', () async {
      final c = await plans.saveCollection(name: 'Sport');
      await daily('Run', collections: [c]);
      await plans.setCollectionVisible(c, false);
      final r = await plans.confirm(
        from: planDate(2026, 10, 20),
        to: planDate(2026, 10, 21),
        nowUtc: DateTime.utc(2026, 10, 19, 5),
      );
      expect(r.createdIds, hasLength(2));
    });
  });
}

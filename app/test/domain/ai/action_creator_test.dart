import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/core/ids.dart';
import 'package:livenow/core/time_codec.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/action_service.dart';
import 'package:livenow/domain/ai/action_creator.dart';
import 'package:livenow/domain/postpone_rules.dart';

void main() {
  late AppDatabase db;
  late ActionService actions;
  late ActionCreator creator;

  setUpAll(initPostponeTimeZoneData);
  setUp(() {
    db = AppDatabase.forTesting(
      NativeDatabase.memory(
        setup: (raw) => raw.execute('PRAGMA foreign_keys = ON;'),
      ),
    );
    actions = ActionService(db);
    creator = ActionCreator(db, actions);
  });
  tearDown(() => db.close());

  const shop = '\u{1F6D2} У магазин';
  const bazaar = '\u{1F353} Базар';

  Future<String> metric(String name) async {
    final id = newId();
    await db
        .into(db.metricsTable)
        .insert(MetricsTableCompanion.insert(id: id, name: name));
    return id;
  }

  Future<List<String>> links(String actionId) async {
    final rows = await (db.select(
      db.actionMetricsTable,
    )..where((t) => t.actionId.equals(actionId))).get();
    return rows.map((r) => r.metricId).toList()..sort();
  }

  test('copies links from the NEWEST same-name action, window +/- minutes', () async {
    final m1 = await metric('A');
    final m2 = await metric('B');
    final ca = await actions.createCountableActivity('Shops');
    await actions.createAction(
      name: shop,
      startAt: DateTime.utc(2026, 10, 1, 9),
      endAt: DateTime.utc(2026, 10, 1, 10),
      metricIds: [m1],
    );
    await actions.createAction(
      name: shop,
      startAt: DateTime.utc(2026, 10, 10, 9),
      endAt: DateTime.utc(2026, 10, 10, 10),
      metricIds: [m1, m2],
      countableActivityId: ca,
    );
    final at = DateTime.utc(2026, 10, 18, 12);
    final id = await creator.create(name: shop, receiptUtc: at);
    final row = await (db.select(
      db.actionsTable,
    )..where((t) => t.id.equals(id))).getSingle();
    expect(dateTimeFromDb(row.startAt), at.subtract(const Duration(minutes: 20)));
    expect(dateTimeFromDb(row.endAt), at.add(const Duration(minutes: 20)));
    expect(row.countableActivityId, ca);
    expect(await links(id), ([m1, m2]..sort()));
  });

  test('no earlier action: plain action; id makes it idempotent', () async {
    final at = DateTime.utc(2026, 10, 18, 12);
    final id = deriveId('job', 'action');
    final a = await creator.create(
      name: bazaar,
      receiptUtc: at,
      minutes: 30,
      id: id,
    );
    final b = await creator.create(name: bazaar, receiptUtc: at, id: id);
    expect(a, id);
    expect(b, id);
    final rows = await db.select(db.actionsTable).get();
    expect(rows, hasLength(1));
    expect(await links(a), isEmpty);
    expect(dateTimeFromDb(rows.single.endAt), at.add(const Duration(minutes: 30)));
  });
}

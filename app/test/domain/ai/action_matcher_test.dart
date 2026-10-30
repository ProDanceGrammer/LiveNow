import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/action_service.dart';
import 'package:livenow/domain/ai/action_matcher.dart';
import 'package:livenow/domain/postpone_rules.dart';

void main() {
  late AppDatabase db;
  late ActionService actions;
  late ActionMatcher matcher;

  setUpAll(initPostponeTimeZoneData);
  setUp(() {
    db = AppDatabase.forTesting(
      NativeDatabase.memory(
        setup: (raw) => raw.execute('PRAGMA foreign_keys = ON;'),
      ),
    );
    actions = ActionService(db);
    matcher = ActionMatcher(db);
  });
  tearDown(() => db.close());

  // Europe/Istanbul is UTC+3: local 12:00 = 09:00Z.
  DateTime z(int h, [int m = 0]) => DateTime.utc(2026, 10, 18, h, m);
  Future<String> timed(String name, DateTime s, DateTime e) =>
      actions.createAction(name: name, startAt: s, endAt: e);

  test('receiptLocalToUtc converts local wall time', () {
    expect(receiptLocalToUtc('2026-10-18T12:00'), z(9));
    expect(
      receiptLocalToUtc('2026-10-18 12:00:30'),
      z(9).add(const Duration(seconds: 30)),
    );
    expect(receiptLocalToUtc('2026-10-18T12:00:00Z'), z(12));
  });

  test('inside, at start: contained; at end: nearest', () async {
    final a = await timed('Work', z(9), z(10));
    var m = await matcher.match(z(9, 30));
    expect((m!.actionId, m.kind), (a, ActionMatchKind.contained));
    m = await matcher.match(z(9));
    expect(m!.kind, ActionMatchKind.contained);
    m = await matcher.match(z(10));
    expect((m!.actionId, m.kind), (a, ActionMatchKind.nearest));
  });

  test('2 h edge is in, beyond is out', () async {
    final a = await timed('Work', z(9), z(10));
    expect((await matcher.match(z(12)))?.actionId, a);
    expect(await matcher.match(z(12, 1)), isNull);
    expect((await matcher.match(z(7)))?.actionId, a);
    expect(await matcher.match(z(6, 59)), isNull);
  });

  test('contained beats nearer; nearest otherwise', () async {
    final long = await timed('Long', z(8), z(11));
    await timed('Short', z(11), z(11, 5));
    expect((await matcher.match(z(10, 59)))!.actionId, long);
    await timed('Later', z(14), z(15));
    final near = await timed('Near', z(12, 30), z(13));
    expect((await matcher.match(z(12)))!.actionId, near);
  });

  test('hint wins among plausible actions, not beyond 2 h', () async {
    await timed('Work', z(9), z(10));
    final shop = await timed('\u{1F6D2} У магазин', z(10, 30), z(11));
    var m = await matcher.match(z(9, 30), hint: 'магазин');
    expect((m!.actionId, m.kind), (shop, ActionMatchKind.hint));
    m = await matcher.match(z(16), hint: 'магазин');
    expect(m, isNull);
  });

  test('bazaar marker links the local day action even when another is nearer',
      () async {
    final bazaar = await timed('\u{1F353} Базар', z(5), z(6));
    await timed('Work', z(9), z(10));
    final m = await matcher.match(z(9, 30), bazaarMarker: 'базар');
    expect((m!.actionId, m.kind), (bazaar, ActionMatchKind.bazaar));
    final other = await matcher.match(
      DateTime.utc(2026, 10, 20, 9, 30),
      bazaarMarker: 'базар',
    );
    expect(other, isNull);
  });

  test('all-day only when nothing timed; deleted action is absent', () async {
    final day = await actions.createAction(
      name: 'Day',
      isAllDay: true,
      startAt: DateTime.utc(2026, 10, 17, 21), // local midnight Oct 18
    );
    var m = await matcher.match(z(9));
    expect((m!.actionId, m.kind), (day, ActionMatchKind.allDay));
    final t = await timed('Work', z(9), z(10));
    expect((await matcher.match(z(9, 30)))!.actionId, t);
    await actions.deleteAction(t);
    m = await matcher.match(z(9, 30));
    expect(m!.actionId, day);
  });
}

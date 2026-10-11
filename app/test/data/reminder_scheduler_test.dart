import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/queries.dart' show ActionListItem;
import 'package:livenow/data/reminders/reminder_scheduler.dart';
import 'package:livenow/domain/reminder_plan.dart';

class _FakeSink implements ReminderSink {
  final calls = <List<ReminderMoment>>[];
  @override
  Future<void> replaceAll(List<ReminderMoment> moments) async =>
      calls.add(moments);
}

ActionListItem item(String id, DateTime s, DateTime e) => ActionListItem(
  id: id,
  name: id,
  done: false,
  startAt: s,
  endAt: e,
  isAllDay: false,
);

void main() {
  final now = DateTime.utc(2026, 10, 11, 12);
  late StreamController<List<ActionListItem>> source;
  late _FakeSink sink;
  late ReminderScheduler scheduler;

  setUp(() {
    source = StreamController<List<ActionListItem>>();
    sink = _FakeSink();
    scheduler = ReminderScheduler(
      source: source.stream,
      sink: sink,
      clock: () => now,
      settle: Duration.zero,
    )..start();
  });

  tearDown(() async {
    scheduler.dispose();
    await source.close();
  });

  Future<void> emit(List<ActionListItem> items) async {
    source.add(items);
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }

  test(
    'plans on the first emission and again only when the plan changes',
    () async {
      final a = item(
        'a',
        now.add(const Duration(hours: 1)),
        now.add(const Duration(hours: 2)),
      );
      await emit([a]);
      expect(sink.calls.length, 1);
      expect(sink.calls.single.length, 2); // start + end

      await emit([a]); // same data, nothing to resend
      expect(sink.calls.length, 1);

      await emit([
        a,
        item(
          'b',
          now.add(const Duration(hours: 3)),
          now.add(const Duration(hours: 4)),
        ),
      ]);
      expect(sink.calls.length, 2);
      expect(sink.calls.last.length, 4);
    },
  );

  test('switching off clears, switching on plans again', () async {
    await emit([
      item(
        'a',
        now.add(const Duration(hours: 1)),
        now.add(const Duration(hours: 2)),
      ),
    ]);
    scheduler.setEnabled(false);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(sink.calls.last, isEmpty);
    scheduler.setEnabled(true);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(sink.calls.last.length, 2);
  });
}

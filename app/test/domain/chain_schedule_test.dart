import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/domain/chain_schedule.dart';

DateTime t(int h, [int m = 0, int s = 0]) => DateTime.utc(2026, 10, 10, h, m, s);
ChainNeighbor n(DateTime s, [DateTime? e, bool allDay = false]) =>
    ChainNeighbor(startAt: s, endAt: e, isAllDay: allDay);

void main() {
  test('after: starts at the latest previous end, keeps the length', () {
    final r = scheduleAfterPrevious(
      [n(t(12), t(13)), n(t(9), t(14))],
      currentStart: t(10),
      currentEnd: t(11),
    )!;
    expect(r.start, t(14));
    expect(r.end, t(15));
  });

  test('before: ends at the earliest next start, keeps the length', () {
    final r = scheduleBeforeNext(
      [n(t(12), t(13)), n(t(9), t(10))],
      currentStart: t(10),
      currentEnd: t(11),
    )!;
    expect(r.start, t(8));
    expect(r.end, t(9));
  });

  test('length keeps the seconds; no times = one hour', () {
    final r = scheduleAfterPrevious(
      [n(t(9), t(10))],
      currentStart: t(1),
      currentEnd: t(1, 3, 19),
    )!;
    expect(r.end.difference(r.start), const Duration(minutes: 3, seconds: 19));
    final d = scheduleBeforeNext(
      [n(t(9))],
      currentStart: null,
      currentEnd: null,
    )!;
    expect(d.end.difference(d.start), const Duration(hours: 1));
  });

  test('neighbours without time or all-day are ignored; none = null', () {
    expect(
      scheduleAfterPrevious(
        [
          const ChainNeighbor(startAt: null, endAt: null),
          n(t(20), t(21), true),
        ],
        currentStart: t(1),
        currentEnd: t(2),
      ),
      isNull,
    );
    expect(
      scheduleBeforeNext(const [], currentStart: t(1), currentEnd: t(2)),
      isNull,
    );
  });

  test('a previous action without an end counts as one hour long', () {
    final r = scheduleAfterPrevious(
      [n(t(9))],
      currentStart: t(1),
      currentEnd: t(2),
    )!;
    expect(r.start, t(10));
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/domain/postpone_rules.dart';
import 'package:livenow/ui/views/calendar_layout.dart';

// Europe/Istanbul is UTC+3 all year: local 10:00 == 07:00Z.
DateTime u(int d, int h, [int m = 0]) => DateTime.utc(2026, 9, d, h, m);

typedef E = (String, DateTime, DateTime);

void main() {
  setUpAll(initPostponeTimeZoneData);

  group('stepZoomHours', () {
    test('zooming in walks 24 -> 3 and stops', () {
      var h = 24;
      final seen = <int>[];
      for (var i = 0; i < 7; i++) {
        h = stepZoomHours(h, 1);
        seen.add(h);
      }
      expect(seen, [16, 12, 9, 6, 3, 3, 3]);
    });
    test('zooming out walks 3 -> 24 and stops', () {
      var h = 3;
      final seen = <int>[];
      for (var i = 0; i < 7; i++) {
        h = stepZoomHours(h, -1);
        seen.add(h);
      }
      expect(seen, [6, 9, 12, 16, 24, 24, 24]);
    });
    test('a value that is not a level snaps to the nearest first', () {
      expect(stepZoomHours(15, 1), 12); // 15 -> 16 (nearest), then in -> 12
      expect(stepZoomHours(10, -1), 12); // 10 -> 9 (nearest), then out -> 12
    });
  });

  group('snapMinutes', () {
    test('rounds to nearest 10 min (8 px each)', () {
      expect(snapMinutes(0), 0);
      expect(snapMinutes(3), 0); // 3.75 min
      expect(snapMinutes(5), 10); // 6.25 min
      expect(snapMinutes(8), 10);
      expect(snapMinutes(20), 30); // 25 min
      expect(snapMinutes(48), 60);
    });
    test('exact half step rounds away from zero, negatives symmetric', () {
      expect(snapMinutes(4), 10); // exactly 5 min
      expect(snapMinutes(-4), -10);
      expect(snapMinutes(-3), 0);
      expect(snapMinutes(-8), -10);
      expect(snapMinutes(-48), -60);
    });
    test('px <-> minutes', () {
      expect(minutesToPx(60), kHourHeight);
      expect(minutesToPx(10), 8);
      expect(pxToMinutes(8), 10);
    });
  });

  group('movedSchedule', () {
    test('shifts minutes and preserves duration', () {
      final r = movedSchedule(
        startAt: u(29, 7),
        endAt: u(29, 8, 30),
        dayDelta: 0,
        minuteDelta: 20,
      );
      expect(r.startAt, u(29, 7, 20));
      expect(r.endAt, u(29, 8, 50));
    });
    test('crosses days, both directions and across midnight', () {
      var r = movedSchedule(
        startAt: u(29, 7),
        endAt: u(29, 8),
        dayDelta: 2,
        minuteDelta: -30,
      );
      expect(r.startAt, DateTime.utc(2026, 10, 1, 6, 30));
      expect(r.endAt, r.startAt.add(const Duration(hours: 1)));

      r = movedSchedule(
        startAt: u(29, 21, 30), // local 00:30 on the 30th
        endAt: u(29, 22, 30),
        dayDelta: -1,
        minuteDelta: -60,
      );
      expect(r.startAt, u(28, 20, 30)); // local 23:30 on the 28th
      expect(r.endAt.difference(r.startAt), const Duration(hours: 1));
    });
    test('start-only action gets the computed default duration', () {
      final r = movedSchedule(startAt: u(29, 7), dayDelta: 1, minuteDelta: 0);
      expect(r.startAt, u(30, 7));
      expect(r.endAt, u(30, 8));
    });
  });

  group('resizedSchedule', () {
    test('bottom edge grows/shrinks in steps', () {
      final r = resizedSchedule(
        startAt: u(29, 7),
        endAt: u(29, 8),
        fromTop: false,
        minuteDelta: 30,
      );
      expect(r.startAt, u(29, 7));
      expect(r.endAt, u(29, 8, 30));
    });
    test('top edge moves start, end stays', () {
      final r = resizedSchedule(
        startAt: u(29, 7),
        endAt: u(29, 8),
        fromTop: true,
        minuteDelta: -20,
      );
      expect(r.startAt, u(29, 6, 40));
      expect(r.endAt, u(29, 8));
    });
    test('clamps to a 10 minute minimum', () {
      var r = resizedSchedule(
        startAt: u(29, 7),
        endAt: u(29, 8),
        fromTop: false,
        minuteDelta: -120,
      );
      expect(r.endAt, u(29, 7, 10));
      r = resizedSchedule(
        startAt: u(29, 7),
        endAt: u(29, 8),
        fromTop: true,
        minuteDelta: 300,
      );
      expect(r.startAt, u(29, 7, 50));
      expect(r.endAt, u(29, 8));
    });
    test('start-only action derives its end first', () {
      final bottom = resizedSchedule(
        startAt: u(29, 7),
        fromTop: false,
        minuteDelta: 30,
      );
      expect(bottom.endAt, u(29, 8, 30)); // 60 min default + 30
      final top = resizedSchedule(
        startAt: u(29, 7),
        fromTop: true,
        minuteDelta: -10,
      );
      expect(top.startAt, u(29, 6, 50));
      expect(top.endAt, u(29, 8));
    });
  });

  group('resizedSchedule across days', () {
    test('bottom edge can move into the next day', () {
      final r = resizedSchedule(
        startAt: u(29, 7),
        endAt: u(29, 8),
        fromTop: false,
        dayDelta: 1,
        minuteDelta: 30,
      );
      expect(r.startAt, u(29, 7));
      expect(r.endAt, u(30, 8, 30));
    });
    test('top edge can move into the previous day', () {
      final r = resizedSchedule(
        startAt: u(29, 7),
        endAt: u(29, 8),
        fromTop: true,
        dayDelta: -1,
        minuteDelta: -60,
      );
      expect(r.startAt, u(28, 6));
      expect(r.endAt, u(29, 8));
    });
    test('crossing the other edge still leaves the 10 minute minimum', () {
      final r = resizedSchedule(
        startAt: u(29, 7),
        endAt: u(29, 8),
        fromTop: false,
        dayDelta: -2,
        minuteDelta: 0,
      );
      expect(r.endAt, u(29, 7, 10));
      final t = resizedSchedule(
        startAt: u(29, 7),
        endAt: u(29, 8),
        fromTop: true,
        dayDelta: 3,
        minuteDelta: 0,
      );
      expect(t.startAt, u(29, 7, 50));
    });
  });

  group('packLanes', () {
    List<LaneAssignment<E>> pack(List<E> es) =>
        packLanes<E>(es, startOf: (e) => e.$2, endOf: (e) => e.$3);
    Map<String, (int, int)> byName(List<LaneAssignment<E>> r) => {
      for (final a in r) a.event.$1: (a.lane, a.laneCount),
    };

    test('non-overlapping events are full width', () {
      final r = byName(
        pack([
          ('a', u(29, 7), u(29, 8)),
          ('b', u(29, 8), u(29, 9)), // touching, not overlapping
        ]),
      );
      expect(r['a'], (0, 1));
      expect(r['b'], (0, 1));
    });
    test('overlapping events get side-by-side lanes', () {
      final r = byName(
        pack([
          ('a', u(29, 7), u(29, 9)),
          ('b', u(29, 8), u(29, 10)),
          ('c', u(29, 9), u(29, 10)), // fits lane 0 again, same cluster
        ]),
      );
      expect(r['a'], (0, 2));
      expect(r['b'], (1, 2));
      expect(r['c'], (0, 2));
    });
    test('separate clusters lay out independently', () {
      final r = byName(
        pack([
          ('a', u(29, 7), u(29, 8)),
          ('b', u(29, 7, 30), u(29, 8, 30)),
          ('c', u(29, 12), u(29, 13)),
        ]),
      );
      expect(r['a']!.$2, 2);
      expect(r['b']!.$2, 2);
      expect(r['c'], (0, 1));
    });
    test(
      'an event expands over lanes that are free for its whole duration',
      () {
        final r = pack([
          ('A', u(29, 5), u(29, 19)), // 08:00-22:00 local
          ('B', u(29, 5, 30), u(29, 6, 10)), // 08:30-09:10
          ('C', u(29, 6), u(29, 7)), // 09:00-10:00
          ('D', u(29, 7, 10), u(29, 8)), // 10:10-11:00
        ]);
        final byId = {for (final a in r) a.event.$1: a};
        for (final a in r) {
          expect(a.laneCount, 3);
        }
        expect((byId['A']!.lane, byId['A']!.span), (0, 1));
        expect((byId['B']!.lane, byId['B']!.span), (1, 1)); // C blocks lane 2
        expect((byId['C']!.lane, byId['C']!.span), (2, 1));
        // D reuses lane 1 and grows over the free lane 2: 2/3 of the width.
        expect((byId['D']!.lane, byId['D']!.span), (1, 2));
      },
    );
    test('span stops at a lane that is busy during the event', () {
      final r = pack([
        ('a', u(29, 7), u(29, 9)),
        ('b', u(29, 8), u(29, 10)),
        ('c', u(29, 8, 30), u(29, 9)),
      ]);
      final byId = {for (final a in r) a.event.$1: a};
      expect(byId['a']!.span, 1); // b sits in lane 1 while a runs
      expect(byId['b']!.span, 1);
      expect(byId['c']!.span, 1);
    });
    test('zero-length events count as the minimum length', () {
      final r = byName(
        pack([('a', u(29, 7), u(29, 7)), ('b', u(29, 7, 5), u(29, 7, 5))]),
      );
      expect(r['a'], (0, 2));
      expect(r['b'], (1, 2));
    });
  });

  group('range anchoring', () {
    // Sun 2026-09-27 (Istanbul), Mon 2026-09-28, Wed 2026-09-30.
    final sunday = DateTime.utc(2026, 9, 27, 12);
    final monday = DateTime.utc(2026, 9, 28, 12);
    final wednesday = DateTime.utc(2026, 9, 30, 12);
    final mondayMidnight = DateTime.utc(2026, 9, 27, 21); // 28th 00:00 local

    test('7 days -> Monday of the current week', () {
      expect(calendarAnchorStart(monday, 7), mondayMidnight);
      expect(calendarAnchorStart(wednesday, 7), mondayMidnight);
      // Sunday belongs to the week that started the previous Monday.
      expect(calendarAnchorStart(sunday, 7), DateTime.utc(2026, 9, 20, 21));
    });
    test('2..6 days -> today', () {
      for (final n in [2, 3, 4, 5, 6]) {
        expect(calendarAnchorStart(sunday, n), DateTime.utc(2026, 9, 26, 21));
        expect(calendarAnchorStart(monday, n), mondayMidnight);
        expect(
          calendarAnchorStart(wednesday, n),
          DateTime.utc(2026, 9, 29, 21),
        );
      }
    });
    test('late-evening UTC is already tomorrow in Istanbul', () {
      // 22:00Z Sunday == 01:00 Monday local.
      expect(
        calendarAnchorStart(DateTime.utc(2026, 9, 27, 22), 7),
        mondayMidnight,
      );
    });
    test('calendarAddDays / dayIndexOf / minutesOfDay', () {
      expect(calendarAddDays(mondayMidnight, 7), DateTime.utc(2026, 10, 4, 21));
      expect(
        calendarAddDays(mondayMidnight, -1),
        DateTime.utc(2026, 9, 26, 21),
      );
      expect(dayIndexOf(DateTime.utc(2026, 9, 28, 20, 59), mondayMidnight), 0);
      expect(dayIndexOf(DateTime.utc(2026, 9, 28, 21), mondayMidnight), 1);
      expect(dayIndexOf(DateTime.utc(2026, 9, 27, 20), mondayMidnight), -1);
      expect(minutesOfDay(DateTime.utc(2026, 9, 28, 7, 15)), 10 * 60 + 15);
      expect(localDayStart(DateTime.utc(2026, 9, 28, 7)), mondayMidnight);
    });
  });

  group('resizing across midnight is not clamped', () {
    test('the bottom edge of a block ending 23:59 can go to 00:30 next day', () {
      final r = resizedSchedule(
        startAt: u(10, 17), // 20:00 local
        endAt: u(10, 20, 59), // 23:59 local
        fromTop: false,
        dayDelta: 0,
        minuteDelta: 31,
        legacyEstimatedMinutes: null,
      );
      expect(r.endAt, u(10, 21, 30)); // 00:30 local the next day
      expect(r.startAt, u(10, 17));
    });

    test('the top edge of a block that starts yesterday can move earlier', () {
      final r = resizedSchedule(
        startAt: u(9, 20), // yesterday 23:00 local
        endAt: u(10, 4),
        fromTop: true,
        dayDelta: 0,
        minuteDelta: -41,
        legacyEstimatedMinutes: null,
      );
      expect(r.startAt, u(9, 20).subtract(const Duration(minutes: 41)));
    });
  });

  group('snapToNeighbours (the magnet)', () {
    CalendarSchedule sched(DateTime s, DateTime e) => (startAt: s, endAt: e);
    final edges = [u(10, 7), u(10, 8), u(10, 9, 30)]; // 10:00, 11:00, 12:30 local

    test('a move locks the start onto a neighbour end and keeps the length', () {
      // 11:03 -> 12:03 local: the start is 3 min from the edge at 11:00.
      final r = snapToNeighbours(
        schedule: sched(u(10, 8, 3), u(10, 9, 3)),
        moveWhole: true,
        neighbourEdges: edges,
        pxPerMinute: 2,
      );
      expect(r.snappedTo, u(10, 8));
      expect(r.schedule.startAt, u(10, 8));
      expect(r.schedule.endAt, u(10, 9));
    });

    test('a move locks the END onto the next event start (the closer edge wins)', () {
      // ends 12:27 local, 3 min before the edge at 12:30.
      final r = snapToNeighbours(
        schedule: sched(u(10, 8, 27), u(10, 9, 27)),
        moveWhole: true,
        neighbourEdges: edges,
        pxPerMinute: 2,
      );
      expect(r.snappedTo, u(10, 9, 30));
      expect(r.schedule.endAt, u(10, 9, 30));
      expect(r.schedule.startAt, u(10, 8, 30));
    });

    test('nothing within the threshold: no change', () {
      final s = sched(u(10, 8, 20), u(10, 8, 50));
      final r = snapToNeighbours(
        schedule: s,
        moveWhole: true,
        neighbourEdges: edges,
        pxPerMinute: 2,
      );
      expect(r.snappedTo, isNull);
      expect(r.schedule, s);
    });

    test('the threshold is constant on screen: wider in minutes when zoomed out', () {
      // 8 px at 0.5 px/min = 16 min but capped at the 10 min grid step.
      final far = snapToNeighbours(
        schedule: sched(u(10, 8, 12), u(10, 8, 40)),
        moveWhole: true,
        neighbourEdges: edges,
        pxPerMinute: 0.5,
      );
      expect(far.snappedTo, isNull, reason: '12 min away: beyond the 10 min cap');
      final near = snapToNeighbours(
        schedule: sched(u(10, 8, 9), u(10, 8, 40)),
        moveWhole: true,
        neighbourEdges: edges,
        pxPerMinute: 0.5,
      );
      expect(near.snappedTo, u(10, 8));
      // Zoomed in (4 px/min): only 2 minutes count.
      final tight = snapToNeighbours(
        schedule: sched(u(10, 8, 3), u(10, 8, 40)),
        moveWhole: true,
        neighbourEdges: edges,
        pxPerMinute: 4,
      );
      expect(tight.snappedTo, isNull);
    });

    test('resize bottom snaps only the end edge', () {
      final r = snapToNeighbours(
        schedule: sched(u(10, 5), u(10, 8, 4)),
        moveWhole: false,
        movedEdgeIsStart: false,
        neighbourEdges: edges,
        pxPerMinute: 2,
      );
      expect(r.schedule.startAt, u(10, 5));
      expect(r.schedule.endAt, u(10, 8));
    });

    test('resize top snaps only the start edge, and never below the minimum length', () {
      final ok = snapToNeighbours(
        schedule: sched(u(10, 7, 4), u(10, 9)),
        moveWhole: false,
        movedEdgeIsStart: true,
        neighbourEdges: edges,
        pxPerMinute: 2,
      );
      expect(ok.schedule.startAt, u(10, 7));
      // The edge at 11:00 would leave 3 minutes: refused.
      final tooShort = snapToNeighbours(
        schedule: sched(u(10, 8, 3), u(10, 8, 13)),
        moveWhole: false,
        movedEdgeIsStart: true,
        neighbourEdges: [u(10, 8, 11)],
        pxPerMinute: 2,
      );
      expect(tooShort.snappedTo, isNull);
    });

    test('off-grid neighbour times (23:59) are reachable', () {
      final r = snapToNeighbours(
        schedule: sched(u(10, 20, 58), u(10, 21, 58)),
        moveWhole: true,
        neighbourEdges: [u(10, 20, 59)],
        pxPerMinute: 2,
      );
      expect(r.schedule.startAt, u(10, 20, 59));
    });
  });
}

import 'package:drift/drift.dart' show Variable;
import 'package:timezone/timezone.dart' as tz;

import '../../core/local_time.dart';
import '../../core/settings.dart';
import '../../core/time_codec.dart';
import '../../data/database.dart';
import '../sequence_naming.dart';

/// How a receipt was tied to an action.
enum ActionMatchKind { contained, nearest, hint, bazaar, allDay }

class ActionMatch {
  const ActionMatch(this.actionId, this.kind);
  final String actionId;
  final ActionMatchKind kind;
}

const kActionMatchWindow = Duration(hours: 2);

/// A receipt's local wall-clock time ("2026-10-18T14:05[:ss]", no offset) as a
/// UTC instant in [AppSettings.timeZoneName] (the tz database must be
/// initialised). Text with `Z` or an offset is taken as the instant it names.
DateTime receiptLocalToUtc(String isoLocal) {
  final text = isoLocal.trim().replaceFirst(' ', 'T');
  if (RegExp(r'(Z|[+-]\d\d:?\d\d)$').hasMatch(text)) {
    return DateTime.parse(text).toUtc();
  }
  final p = DateTime.parse(text);
  return tz
      .TZDateTime(
        tz.getLocation(AppSettings.timeZoneName),
        p.year,
        p.month,
        p.day,
        p.hour,
        p.minute,
        p.second,
      )
      .toUtc();
}

/// Ties a receipt instant to an action (rules T1-T3, T5). Instants are compared
/// as numbers, never as text.
class ActionMatcher {
  ActionMatcher(this.db);

  final AppDatabase db;

  /// 1. a timed action whose `[start, end)` contains [atUtc] (end EXCLUSIVE:
  ///    a receipt exactly at an end counts as "nearest", not contained);
  /// 2. else the nearest timed action within [kActionMatchWindow];
  /// 3. else an all-day action of that local day; else null.
  /// [hint] (a name fragment, compared with [normalizeForMatch]) wins among the
  /// plausible (contained or within 2 h) timed actions. [bazaarMarker] (T5)
  /// wins over everything: that local day's action whose name contains it,
  /// timed or all-day, the closest one to [atUtc].
  Future<ActionMatch?> match(
    DateTime atUtc, {
    String? hint,
    String? bazaarMarker,
  }) async {
    final at = atUtc.toUtc();
    final dayStart = localDayStart(at);
    final dayEnd = calendarAddDays(dayStart, 1);

    final marker = _key(bazaarMarker);
    if (marker.isNotEmpty) {
      final rows = await _query(
        'a.start_at IS NOT NULL AND a.start_at >= ? AND a.start_at < ?',
        [dayStart, dayEnd],
      );
      final hits = rows.where((r) => _key(r.name).contains(marker)).toList();
      if (hits.isNotEmpty) {
        hits.sort(_byProximity(at));
        return ActionMatch(hits.first.id, ActionMatchKind.bazaar);
      }
    }

    final timed = (await _query(
      'a.is_all_day = 0 AND a.start_at IS NOT NULL AND a.end_at IS NOT NULL '
      'AND a.end_at >= ? AND a.start_at <= ?',
      [at.subtract(kActionMatchWindow), at.add(kActionMatchWindow)],
    )).where((r) => r.distance(at) <= kActionMatchWindow).toList()
      ..sort(_byProximity(at));

    final h = _key(hint);
    if (h.isNotEmpty) {
      final named = timed.where((r) => _key(r.name).contains(h));
      if (named.isNotEmpty) {
        return ActionMatch(named.first.id, ActionMatchKind.hint);
      }
    }
    if (timed.isNotEmpty) {
      final best = timed.first;
      return ActionMatch(
        best.id,
        best.contains(at) ? ActionMatchKind.contained : ActionMatchKind.nearest,
      );
    }

    final allDay = await _query(
      'a.is_all_day = 1 AND a.start_at IS NOT NULL AND a.start_at >= ? '
      'AND a.start_at < ?',
      [dayStart, dayEnd],
    );
    if (allDay.isEmpty) return null;
    if (h.isNotEmpty) {
      final named = allDay.where((r) => _key(r.name).contains(h));
      if (named.isNotEmpty) {
        return ActionMatch(named.first.id, ActionMatchKind.allDay);
      }
    }
    return ActionMatch(allDay.first.id, ActionMatchKind.allDay);
  }

  static String _key(String? s) => s == null ? '' : normalizeForMatch(s);

  /// Contained first (latest start wins, as in suggestedActionId), then by
  /// distance, then the later start.
  static int Function(_Row, _Row) _byProximity(DateTime at) => (a, b) {
    final ca = a.contains(at), cb = b.contains(at);
    if (ca != cb) return ca ? -1 : 1;
    final d = a.distance(at).compareTo(b.distance(at));
    if (d != 0) return d;
    return b.start.compareTo(a.start);
  };

  Future<List<_Row>> _query(String where, List<DateTime> args) async {
    final rows = await db
        .customSelect(
          'SELECT a.id AS id, a.name AS name, a.start_at AS s, a.end_at AS e '
          'FROM actions a WHERE $where',
          variables: [for (final d in args) Variable.withString(dateTimeToDb(d)!)],
        )
        .get();
    return [
      for (final r in rows)
        _Row(
          r.read<String>('id'),
          r.read<String>('name'),
          dateTimeFromDb(r.read<String?>('s'))!,
          dateTimeFromDb(r.read<String?>('e')),
        ),
    ];
  }
}

class _Row {
  _Row(this.id, this.name, this.start, this.end);
  final String id;
  final String name;
  final DateTime start;
  final DateTime? end;

  bool contains(DateTime at) =>
      end != null && !at.isBefore(start) && at.isBefore(end!);

  Duration distance(DateTime at) {
    if (at.isBefore(start)) return start.difference(at);
    final e = end ?? start;
    if (!at.isBefore(e)) return at.difference(e);
    return Duration.zero;
  }
}

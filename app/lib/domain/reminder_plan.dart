/// Which moments of the user's timed actions deserve a notification, as a
/// pure function (no clock, no platform): the scheduler feeds it the upcoming
/// actions and hands the result to the operating system.
library;

enum ReminderKind { start, end }

/// What the planner reads of an action.
class ReminderSource {
  final String id;
  final String name;
  final DateTime? startAt;
  final DateTime? endAt;
  final bool isAllDay;

  const ReminderSource({
    required this.id,
    required this.name,
    required this.startAt,
    required this.endAt,
    required this.isAllDay,
  });
}

/// One notification to fire at [at].
class ReminderMoment {
  final String actionId;
  final ReminderKind kind;
  final DateTime at;
  final String title;

  const ReminderMoment({
    required this.actionId,
    required this.kind,
    required this.at,
    required this.title,
  });

  /// A stable 31-bit id (iOS wants a 32-bit int): the same moment of the same
  /// action always maps to the same notification, so re-planning replaces
  /// instead of duplicating.
  int get notificationId => _fnv31('$actionId/${kind.name}');

  @override
  bool operator ==(Object other) =>
      other is ReminderMoment &&
      other.actionId == actionId &&
      other.kind == kind &&
      other.at == at &&
      other.title == title;

  @override
  int get hashCode => Object.hash(actionId, kind, at, title);
}

int _fnv31(String s) {
  var h = 0x811C9DC5;
  for (final c in s.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xFFFFFFFF;
  }
  return h & 0x7FFFFFFF;
}

/// The soonest [limit] reminders after [now]: a "starts" moment at each timed
/// action's start and an "ends" moment at its end (all-day actions and
/// actions without a time get none; an end equal to the start adds nothing
/// beyond the start). iOS keeps at most 64 pending notifications, so the
/// caller passes a [limit] below that.
List<ReminderMoment> planReminders(
  Iterable<ReminderSource> actions,
  DateTime now, {
  int limit = 20,
}) {
  final out = <ReminderMoment>[];
  for (final a in actions) {
    if (a.isAllDay) continue;
    final s = a.startAt, e = a.endAt;
    if (s != null && s.isAfter(now)) {
      out.add(
        ReminderMoment(
          actionId: a.id,
          kind: ReminderKind.start,
          at: s,
          title: a.name,
        ),
      );
    }
    if (e != null && e.isAfter(now) && (s == null || e.isAfter(s))) {
      out.add(
        ReminderMoment(
          actionId: a.id,
          kind: ReminderKind.end,
          at: e,
          title: a.name,
        ),
      );
    }
  }
  out.sort((x, y) {
    final c = x.at.compareTo(y.at);
    return c != 0 ? c : x.actionId.compareTo(y.actionId);
  });
  return out.length <= limit ? out : out.sublist(0, limit);
}

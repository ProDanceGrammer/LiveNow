// ignore_for_file: prefer_initializing_formals (private fields, named parameters)
import 'dart:async';

import '../../domain/reminder_plan.dart';
import '../queries.dart' show ActionListItem;

/// Where planned reminders go (the operating system's notification centre;
/// a fake in tests). [replaceAll] must make the system hold EXACTLY [moments].
abstract class ReminderSink {
  Future<void> replaceAll(List<ReminderMoment> moments);
}

/// Keeps a [ReminderSink] in step with the upcoming actions.
///
/// Built to cost nothing while idle: no polling and no periodic timer. It only
/// reacts when the source stream emits (an action's times changed, a postpone,
/// a sync) or when the app tells it it came back to the foreground, waits for
/// edits to settle ([settle]), plans, and calls the sink only when the plan
/// really differs from the last one it sent.
class ReminderScheduler {
  ReminderScheduler({
    required Stream<List<ActionListItem>> source,
    required ReminderSink sink,
    DateTime Function()? clock,
    this.settle = const Duration(seconds: 2),
    this.limit = 20,
    bool enabled = true,
  }) : _source = source,
       _sink = sink,
       _clock = clock ?? DateTime.now,
       _enabled = enabled;

  final Stream<List<ActionListItem>> _source;
  final ReminderSink _sink;
  final DateTime Function() _clock;
  final Duration settle;

  /// Notifications handed to the system at once (iOS keeps at most 64).
  final int limit;

  bool _enabled;
  StreamSubscription<List<ActionListItem>>? _sub;
  Timer? _settleTimer;
  List<ActionListItem> _latest = const [];
  List<ReminderMoment>? _sent;

  /// Starts listening (the first emission arrives with the current data).
  void start() {
    _sub ??= _source.listen((items) {
      _latest = items;
      _scheduleReplan();
    });
  }

  /// The user's on/off switch.
  void setEnabled(bool value) {
    if (value == _enabled) return;
    _enabled = value;
    _scheduleReplan();
  }

  /// App back in the foreground: the clock moved on, so what was planned may
  /// be stale (past moments); re-plan from the data already in hand.
  void resume() => _scheduleReplan();

  void _scheduleReplan() {
    _settleTimer?.cancel();
    _settleTimer = Timer(settle, replan);
  }

  /// Plans now (tests call this directly).
  Future<void> replan() async {
    _settleTimer?.cancel();
    final plan = _enabled
        ? planReminders(
            [
              for (final a in _latest)
                ReminderSource(
                  id: a.id,
                  name: a.name,
                  startAt: a.startAt,
                  endAt: a.endAt,
                  isAllDay: a.isAllDay,
                ),
            ],
            _clock(),
            limit: limit,
          )
        : const <ReminderMoment>[];
    final last = _sent;
    if (last != null && _same(last, plan)) return;
    // The first plan of a session is only sent when it has something to
    // schedule, or when switching off must clear what was left behind.
    _sent = plan;
    await _sink.replaceAll(plan);
  }

  static bool _same(List<ReminderMoment> a, List<ReminderMoment> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void dispose() {
    _settleTimer?.cancel();
    _sub?.cancel();
    _sub = null;
  }
}

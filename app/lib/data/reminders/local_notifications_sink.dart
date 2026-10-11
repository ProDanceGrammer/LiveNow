import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../core/settings.dart';
import '../../domain/reminder_plan.dart';
import 'reminder_scheduler.dart';

/// The real notification centre: iOS holds the scheduled notifications itself
/// (they fire with the app closed and cost nothing while waiting); Windows
/// has no such queue for an unpackaged app, so ONE timer waits for the next
/// moment and shows its toast (only while the app runs). Every failure is
/// swallowed: reminders must never be able to break the app.
class LocalNotificationsSink implements ReminderSink {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool? _ready;
  bool _asked = false;

  Timer? _timer;
  List<ReminderMoment> _pending = const [];

  static bool get _isIos => !kIsWeb && Platform.isIOS;
  static bool get _isWindows => !kIsWeb && Platform.isWindows;

  /// Which platforms get reminders at all.
  static bool get supported => _isIos || _isWindows;

  Future<bool> _init() async {
    if (_ready != null) return _ready!;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
          windows: WindowsInitializationSettings(
            appName: 'LiveNow',
            appUserModelId: 'io.livenow.LiveNow',
            guid: '6f1d6b0e-3c5a-4d6e-9a53-0b5d7f3a21c4',
          ),
        ),
      );
      _ready = true;
    } catch (_) {
      _ready = false;
    }
    return _ready!;
  }

  Future<void> _askPermission() async {
    if (_asked || !_isIos) return;
    _asked = true;
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, sound: true);
    } catch (_) {}
  }

  static String _title(ReminderMoment m) =>
      m.kind == ReminderKind.start ? 'Starting now' : 'Time is up';

  @override
  Future<void> replaceAll(List<ReminderMoment> moments) async {
    if (!supported) return;
    if (!await _init()) return;
    try {
      if (_isIos) {
        await _plugin.cancelAll();
        if (moments.isEmpty) return;
        await _askPermission();
        final zone = tz.getLocation(AppSettings.timeZoneName);
        for (final m in moments) {
          await _plugin.zonedSchedule(
            id: m.notificationId,
            scheduledDate: tz.TZDateTime.from(m.at, zone),
            notificationDetails: const NotificationDetails(
              iOS: DarwinNotificationDetails(),
            ),
            title: _title(m),
            body: m.title,
            androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          );
        }
      } else {
        _pending = moments;
        _arm();
      }
    } catch (_) {}
  }

  /// Windows: one timer for the soonest moment, re-armed after it fires.
  void _arm() {
    _timer?.cancel();
    _timer = null;
    if (_pending.isEmpty) return;
    final next = _pending.first;
    final wait = next.at.difference(DateTime.now().toUtc());
    _timer = Timer(wait.isNegative ? Duration.zero : wait, () async {
      _pending = _pending.skip(1).toList();
      try {
        await _plugin.show(
          id: next.notificationId,
          title: _title(next),
          body: next.title,
          notificationDetails: const NotificationDetails(),
        );
      } catch (_) {}
      _arm();
    });
  }
}

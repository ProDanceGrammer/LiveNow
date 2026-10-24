import '../core/number_rules.dart' show kMaxEstimatedMinutes;

/// Fallback duration when an action has nothing to derive one from — matches
/// the original Notion "Predicted Time Consumption" formula's fallback.
const Duration defaultActionDuration = Duration(minutes: 60);

/// The single source of truth for how long an action takes (there is no
/// manual "Estimated minutes" input any more).
///
/// 1. Both [startAt] and [endAt] set (and end not before start): the gap.
///    Start/Finish keep `start_at`/`end_at` in sync with the real run (a
///    finished action is "actual start -> finish", a running one is
///    "started -> projected end"), so this already reflects actual time and
///    no separate occurrence lookup is needed. A zero gap is kept as-is (a
///    deliberately point-in-time action isn't padded out).
/// 2. Else a legacy [legacyEstimatedMinutes] (old rows/templates only; never
///    written by the UI now), if positive.
/// 3. Else [defaultActionDuration].
Duration computeActionDuration({
  required DateTime? startAt,
  required DateTime? endAt,
  int? legacyEstimatedMinutes,
}) {
  if (startAt != null && endAt != null && !endAt.isBefore(startAt)) {
    return endAt.difference(startAt);
  }
  if (legacyEstimatedMinutes != null && legacyEstimatedMinutes > 0) {
    // Capped: Duration(minutes: 1 << 62) overflows its microsecond counter.
    return Duration(
      minutes: legacyEstimatedMinutes > kMaxEstimatedMinutes
          ? kMaxEstimatedMinutes
          : legacyEstimatedMinutes,
    );
  }
  return defaultActionDuration;
}

/// How long a continuation of an action should take, mirroring the Notion
/// "Predicted Time Consumption" formula: the linked Countable Activity's
/// recent average wins, else the average of recent same-name runs in the
/// action's chain ([chainSamples]), else the action's [ownDuration].
Duration predictedDuration({
  required Duration ownDuration,
  Duration? countableAverage,
  List<Duration> chainSamples = const [],
}) {
  if (countableAverage != null && countableAverage > Duration.zero) {
    return countableAverage;
  }
  if (chainSamples.isNotEmpty) {
    final totalMicros = chainSamples.fold<int>(
      0,
      (sum, d) => sum + d.inMicroseconds,
    );
    return Duration(microseconds: totalMicros ~/ chainSamples.length);
  }
  return ownDuration;
}

/// Formats [d] using its two most significant consecutive units (skipping the
/// second if it's zero): '20 sec', '1 min', '1 hour 23 min', '7 hours',
/// '2 days', '1 day 3 hours'. Seconds only show while the whole duration is
/// under a minute: from 60 s up they are dropped ('20 min 26 sec' reads
/// '20 min'). Negative durations are treated as zero.
String formatDuration(Duration d) {
  final secs = d.isNegative ? 0 : d.inSeconds;
  var total = secs >= 60 ? secs - secs % 60 : secs;
  final days = total ~/ 86400;
  total %= 86400;
  final hours = total ~/ 3600;
  total %= 3600;
  final minutes = total ~/ 60;
  final seconds = total % 60;

  final parts = <(int, String, String)>[
    (days, 'day', 'days'),
    (hours, 'hour', 'hours'),
    (minutes, 'min', 'min'),
    (seconds, 'sec', 'sec'),
  ];
  final first = parts.indexWhere((p) => p.$1 > 0);
  if (first == -1) return '0 sec';

  String fmt((int, String, String) p) => '${p.$1} ${p.$1 == 1 ? p.$2 : p.$3}';
  final out = [fmt(parts[first])];
  if (first + 1 < parts.length && parts[first + 1].$1 > 0) {
    out.add(fmt(parts[first + 1]));
  }
  return out.join(' ');
}

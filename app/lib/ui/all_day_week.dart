import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart' show StateProvider;

import '../core/local_time.dart';
import '../data/queries.dart';
import 'device_prefs.dart';
import 'providers.dart';
import 'views/calendar_layout.dart' show calendarAnchorStart;

// The week strip of ALL-DAY actions above Current Actions: which week it shows,
// what it lists and the "show done" choice. The strip itself is
// `views/all_day_week_strip.dart`.

/// How many weeks the strip is moved away from the current week (0 = this
/// week, -1 = last week). Not persisted: a restart shows this week again.
final allDayStripWeekOffsetProvider = StateProvider<int>((ref) => 0);

/// The UTC instant of the Monday 00:00 (Istanbul) that starts the strip's week.
/// Follows the minute tick, so the strip rolls over to the new week by itself
/// after midnight on Sunday.
final allDayStripWeekStartProvider = Provider.autoDispose<DateTime>((ref) {
  final monday = calendarAnchorStart(ref.watch(currentBoardNowProvider), 7);
  return calendarAddDays(monday, 7 * ref.watch(allDayStripWeekOffsetProvider));
});

/// Every all-day action of the strip's week, done or not (the strip hides the
/// done ones unless [showDoneAllDayProvider] says otherwise).
final allDayStripItemsProvider = StreamProvider.autoDispose<List<ActionListItem>>(
  (ref) {
    final start = ref.watch(allDayStripWeekStartProvider);
    return ref
        .watch(viewQueriesProvider)
        .watchAllDayRange(
          weekStartUtc: start,
          weekEndUtc: calendarAddDays(start, 7),
        );
  },
);

/// Device preference keys (`ui_prefs.json`, not synced).
const kShowDoneAllDayKey = 'show_done_all_day';
const kAllDayStripOpenKey = 'allday_strip_open';

/// Whether done all-day actions stay in the strip (default: they disappear).
final showDoneAllDayProvider = Provider<bool>(
  (ref) => ref.watch(devicePrefBoolProvider((kShowDoneAllDayKey, false))),
);

/// Whether the strip is unfolded (a phone can fold it away; default open).
final allDayStripOpenProvider = Provider<bool>(
  (ref) => ref.watch(devicePrefBoolProvider((kAllDayStripOpenKey, true))),
);

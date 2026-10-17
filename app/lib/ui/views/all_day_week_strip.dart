import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../core/local_time.dart';
import '../../core/settings.dart';
import '../../data/queries.dart';
import '../../domain/action_service.dart' show ScheduleChange;
import '../../domain/all_day_postpone.dart';
import '../all_day_week.dart';
import '../device_prefs.dart';
import '../edit_action.dart';
import '../layout.dart';
import '../providers.dart';
import '../theme/glass_theme.dart';
import '../undo.dart';
import '../urgency_colors.dart';
import '../widgets/glass.dart';
import '../widgets/glass_icon_tile.dart';
import '../widgets/hover_toolbar.dart';
import '../widgets/round_check.dart';

/// The key of the strip (the Current board's marquee selection ignores presses
/// that start on it).
const kAllDayStripKey = ValueKey('allday-strip');

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec', //
];

tz.TZDateTime _local(DateTime utc) =>
    tz.TZDateTime.from(utc, tz.getLocation(AppSettings.timeZoneName));

/// "12 - 18 Oct 2026", or "28 Sep - 4 Oct 2026" across a month end.
String _weekLabel(DateTime mondayUtc) {
  final first = _local(mondayUtc);
  final last = _local(calendarAddDays(mondayUtc, 6));
  final from = first.month == last.month
      ? '${first.day}'
      : '${first.day} ${_months[first.month - 1]}';
  return '$from – ${last.day} ${_months[last.month - 1]} ${last.year}';
}

/// The week's all-day actions above the Current Actions board: seven day columns
/// (a phone: one list per day), each action a small card with its Done
/// checkbox; on hover (a phone: long-press) it offers to postpone to the next
/// Monday or by 7 days. Done cards are hidden unless the setting / the eye
/// button says otherwise. With nothing to show it shrinks to a thin row.
class AllDayWeekStrip extends ConsumerWidget {
  const AllDayWeekStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final phone = usePhoneLayout(context);
    final start = ref.watch(allDayStripWeekStartProvider);
    final offset = ref.watch(allDayStripWeekOffsetProvider);
    final now = ref.watch(currentBoardNowProvider);
    final showDone = ref.watch(showDoneAllDayProvider);
    final open = !phone || ref.watch(allDayStripOpenProvider);
    final items =
        ref.watch(allDayStripItemsProvider).value ?? const <ActionListItem>[];
    final scheme = Theme.of(context).colorScheme;
    final glass = context.glass;

    final dayStarts = [for (var i = 0; i < 7; i++) calendarAddDays(start, i)];
    final byDay = List.generate(7, (_) => <ActionListItem>[]);
    for (final a in items) {
      final s = a.startAt;
      if (s == null || (!showDone && a.isDoneBefore)) continue;
      var day = 0;
      for (var i = 6; i >= 0; i--) {
        if (!s.isBefore(dayStarts[i])) {
          day = i;
          break;
        }
      }
      byDay[day].add(a);
    }
    final total = byDay.fold<int>(0, (n, l) => n + l.length);
    final today = localDayStart(now);

    // The cards scroll inside this height: the Current board below always keeps
    // most of the window.
    final cap = (MediaQuery.sizeOf(context).height * 0.3 - 70).clamp(80.0, 300.0);

    Widget header() => Row(
      children: [
        IconButton(
          key: const ValueKey('allday-strip-prev'),
          tooltip: 'Previous week',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.chevron_left),
          onPressed: () =>
              ref.read(allDayStripWeekOffsetProvider.notifier).state--,
        ),
        TextButton(
          key: const ValueKey('allday-strip-today'),
          onPressed: offset == 0
              ? null
              : () => ref.read(allDayStripWeekOffsetProvider.notifier).state = 0,
          child: const Text('Today'),
        ),
        IconButton(
          key: const ValueKey('allday-strip-next'),
          tooltip: 'Next week',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.chevron_right),
          onPressed: () =>
              ref.read(allDayStripWeekOffsetProvider.notifier).state++,
        ),
        Expanded(
          child: Text(
            _weekLabel(start),
            key: const ValueKey('allday-strip-label'),
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        IconButton(
          key: const ValueKey('allday-strip-eye'),
          tooltip: showDone ? 'Hide done all-day actions' : 'Show done all-day actions',
          visualDensity: VisualDensity.compact,
          isSelected: showDone,
          icon: Icon(showDone ? Icons.visibility : Icons.visibility_off_outlined),
          onPressed: () => setDevicePrefBool(ref, kShowDoneAllDayKey, !showDone),
        ),
        if (phone)
          IconButton(
            key: const ValueKey('allday-strip-toggle'),
            tooltip: open ? 'Fold the week' : 'Unfold the week',
            visualDensity: VisualDensity.compact,
            icon: Icon(open ? Icons.expand_less : Icons.expand_more),
            onPressed: () => setDevicePrefBool(ref, kAllDayStripOpenKey, !open),
          ),
      ],
    );

    Widget dayNames() => Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
      child: Row(
        children: [
          for (var i = 0; i < 7; i++)
            Expanded(
              child: Container(
                key: ValueKey('allday-strip-day-$i'),
                margin: const EdgeInsets.symmetric(horizontal: 2),
                padding: const EdgeInsets.symmetric(vertical: 3),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: dayStarts[i] == today
                      ? scheme.primary.withValues(alpha: 0.2)
                      : null,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${_weekdays[i]} ${_local(dayStarts[i]).day}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: dayStarts[i] == today
                        ? FontWeight.w700
                        : FontWeight.w500,
                    color: glass.textSecondary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    Widget columns() => ConstrainedBox(
      constraints: BoxConstraints(maxHeight: cap),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Column(
                      key: ValueKey('allday-strip-col-$i'),
                      children: [
                        for (final a in byDay[i])
                          _StripCard(key: ValueKey('allday-card-${a.id}'), item: a),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    Widget stacked() => ConstrainedBox(
      constraints: BoxConstraints(maxHeight: cap),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < 7; i++)
                if (byDay[i].isNotEmpty) ...[
                  Padding(
                    key: ValueKey('allday-strip-day-$i'),
                    padding: const EdgeInsets.only(top: 4, bottom: 2),
                    child: Text(
                      '${_weekdays[i]} ${_local(dayStarts[i]).day}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: dayStarts[i] == today
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: dayStarts[i] == today
                            ? scheme.primary
                            : glass.textSecondary,
                      ),
                    ),
                  ),
                  for (final a in byDay[i])
                    _StripCard(key: ValueKey('allday-card-${a.id}'), item: a),
                ],
            ],
          ),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
      child: GlassSurface(
        key: kAllDayStripKey,
        radius: 20,
        shadow: false,
        blurWindow: false,
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              header(),
              if (open && !phone) dayNames(),
              // Nothing to show: just the thin header (and, on the desktop, the
              // day names) - the Current board gets the height back.
              if (open && total > 0) (phone ? stacked() : columns()),
            ],
          ),
        ),
      ),
    );
  }
}

/// One all-day action in the strip: round Done checkbox + name, tinted like the
/// calendar chips (urgency colour; white when it has no growth direction).
class _StripCard extends ConsumerWidget {
  const _StripCard({super.key, required this.item});

  final ActionListItem item;

  void _move(
    BuildContext context,
    WidgetRef ref,
    DateTime Function(DateTime) rule,
    String what,
  ) {
    final s = item.startAt;
    if (s == null) return;
    runUndoableMoveMany(
      context,
      ref,
      [ScheduleChange(item.id, startAt: rule(s), endAt: null, isAllDay: true)],
      description: what,
    );
  }

  void _toMonday(BuildContext context, WidgetRef ref) =>
      _move(context, ref, allDayToMonday, 'Moved to Monday');

  void _plusWeek(BuildContext context, WidgetRef ref) =>
      _move(context, ref, allDayPlusSevenDays, 'Moved 7 days');

  /// Phone: long-press opens the same two choices (there is no hover).
  Future<void> _menu(BuildContext context, WidgetRef ref, Offset at) async {
    final box = Overlay.of(context).context.findRenderObject() as RenderBox;
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(at & Size.zero, Offset.zero & box.size),
      items: const [
        PopupMenuItem(
          key: ValueKey('allday-menu-monday'),
          value: 'monday',
          child: Text('Postpone to Monday'),
        ),
        PopupMenuItem(
          key: ValueKey('allday-menu-week'),
          value: 'week',
          child: Text('Postpone 7 days'),
        ),
      ],
    );
    if (choice == null || !context.mounted) return;
    if (choice == 'monday') {
      _toMonday(context, ref);
    } else {
      _plusWeek(context, ref);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final phone = usePhoneLayout(context);
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    final urgency = ref.watch(actionUrgencyProvider.select((m) => m[item.id]));
    final unlinked = ref.watch(
      actionsWithDirectionsProvider.select(
        (s) => s != null && !s.contains(item.id),
      ),
    );
    final done = item.isDoneBefore;
    final tint = unlinked
        ? emptyColors(dark: dark, done: done)
        : urgency != null
        ? (done
              ? urgencyColorsMuted(urgency, dark: dark)
              : urgencyColors(urgency, dark: dark))
        : null;
    final fg = tint?.fg ?? scheme.onSurface;

    final body = Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: tint?.bg ?? context.glass.fillStrong,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => openActionEditor(context, ref, item.id),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 4, 8, 4),
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: RoundCheck(
                    key: ValueKey('allday-card-check-${item.id}'),
                    value: done,
                    size: 16,
                    hit: 24,
                    color: fg,
                    checkColor: tint?.bg ?? scheme.surface,
                    onTap: () => runUndoableToggleDone(context, ref, item.id),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    item.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: fg,
                      decoration: done ? TextDecoration.lineThrough : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (phone) {
      return GestureDetector(
        onLongPressStart: (d) => _menu(context, ref, d.globalPosition),
        child: body,
      );
    }
    return HoverToolbarHost(
      toolbarHeight: 40,
      toolbarBuilder: (_) => HoverToolbarPill(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GlassIconTile(
              key: ValueKey('allday-card-monday-${item.id}'),
              icon: Icons.calendar_view_week,
              hue: GlassHue.blue,
              tooltip: 'Postpone to Monday',
              size: 28,
              iconSize: 18,
              onTap: () => _toMonday(context, ref),
            ),
            const SizedBox(width: 2),
            GlassIconTile(
              key: ValueKey('allday-card-week-${item.id}'),
              icon: Icons.fast_forward,
              hue: GlassHue.lavender,
              tooltip: 'Postpone 7 days',
              size: 28,
              iconSize: 18,
              onTap: () => _plusWeek(context, ref),
            ),
          ],
        ),
      ),
      child: body,
    );
  }
}

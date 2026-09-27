import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/queries.dart';
import '../edit_action.dart';
import '../providers.dart';
import '../widgets/action_tile.dart';

const _dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// A simple week-grouped list (not a full hour-grid calendar): a header with
/// prev/next navigation, then one section per day showing that day's
/// one-off (non-habit) actions.
class CalendarWeekView extends ConsumerWidget {
  const CalendarWeekView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weekStart = ref.watch(calendarWeekStartProvider);
    final itemsAsync = ref.watch(calendarWeekProvider);

    return Column(
      children: [
        _WeekHeader(weekStart: weekStart),
        const Divider(height: 1),
        Expanded(
          child: itemsAsync.when(
            data: (items) => _WeekBody(weekStart: weekStart, items: items),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
          ),
        ),
      ],
    );
  }
}

class _WeekHeader extends ConsumerWidget {
  final DateTime weekStart;

  const _WeekHeader({required this.weekStart});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final local = weekStart.toLocal();
    final endLocal = weekStart.add(const Duration(days: 6)).toLocal();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: 'Previous week',
            onPressed: () =>
                ref.read(calendarWeekStartProvider.notifier).state =
                    weekStart.subtract(const Duration(days: 7)),
          ),
          Expanded(
            child: Center(child: Text('${_fmt(local)} — ${_fmt(endLocal)}')),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Next week',
            onPressed: () =>
                ref.read(calendarWeekStartProvider.notifier).state =
                    weekStart.add(const Duration(days: 7)),
          ),
        ],
      ),
    );
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

class _WeekBody extends StatelessWidget {
  final DateTime weekStart;
  final List<ActionListItem> items;

  const _WeekBody({required this.weekStart, required this.items});

  @override
  Widget build(BuildContext context) {
    final weekStartLocalDate = _dateOnly(weekStart.toLocal());
    final byDay = <int, List<ActionListItem>>{
      for (var i = 0; i < 7; i++) i: [],
    };

    for (final item in items) {
      if (item.startAt == null) continue;
      final localDate = _dateOnly(item.startAt!.toLocal());
      final dayIndex = localDate.difference(weekStartLocalDate).inDays;
      if (dayIndex >= 0 && dayIndex < 7) {
        byDay[dayIndex]!.add(item);
      }
    }

    return ListView(
      children: [
        for (var i = 0; i < 7; i++)
          _DaySection(
            label:
                '${_dayNames[i]} ${_fmtShort(weekStartLocalDate.add(Duration(days: i)))}',
            items: byDay[i]!,
          ),
      ],
    );
  }

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  String _fmtShort(DateTime d) =>
      '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

class _DaySection extends ConsumerWidget {
  final String label;
  final List<ActionListItem> items;

  const _DaySection({required this.label, required this.items});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(label, style: Theme.of(context).textTheme.titleSmall),
        ),
        if (items.isEmpty)
          const Padding(
            padding: EdgeInsets.only(left: 16, bottom: 8),
            child: Text('—', style: TextStyle(color: Colors.grey)),
          )
        else
          for (final item in items)
            ActionTile(
              key: ValueKey(item.id),
              action: item,
              onTap: () => openActionEditor(context, ref, item.id),
            ),
      ],
    );
  }
}

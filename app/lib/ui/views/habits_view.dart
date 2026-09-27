import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../edit_action.dart';
import '../providers.dart';
import '../widgets/action_tile.dart';

/// Open habits, split into all-day and timed sections (bad habits aren't
/// part of the MVP view).
class HabitsView extends ConsumerWidget {
  const HabitsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(habitsProvider);

    return itemsAsync.when(
      data: (items) {
        if (items.isEmpty) {
          return const Center(child: Text('No habits yet.'));
        }
        final timed = items.where((a) => !a.isAllDay).toList();
        final allDay = items.where((a) => a.isAllDay).toList();

        return ListView(
          children: [
            if (timed.isNotEmpty) ...[
              const _SectionHeader('Timed'),
              for (final item in timed)
                ActionTile(
                  key: ValueKey(item.id),
                  action: item,
                  onTap: () => openActionEditor(context, ref, item.id),
                ),
            ],
            if (allDay.isNotEmpty) ...[
              const _SectionHeader('All day'),
              for (final item in allDay)
                ActionTile(
                  key: ValueKey(item.id),
                  action: item,
                  onTap: () => openActionEditor(context, ref, item.id),
                ),
            ],
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/queries.dart';
import '../providers.dart';
import '../widgets/action_card.dart';

/// The default view: a two-column board (like a Kanban/Trello board),
/// split by completion status rather than by list membership — "done
/// before" on the left, "not finished yet" on the right.
class CurrentActionsView extends ConsumerWidget {
  const CurrentActionsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final doneAsync = ref.watch(currentDoneProvider);
    final notDoneAsync = ref.watch(currentNotDoneProvider);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _BoardColumn(
            title: 'Done Before',
            asyncCards: doneAsync,
            emptyMessage: 'Nothing done yet.',
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: _BoardColumn(
            title: 'Not Done Yet',
            asyncCards: notDoneAsync,
            emptyMessage: 'Nothing left to do.',
          ),
        ),
      ],
    );
  }
}

class _BoardColumn extends StatelessWidget {
  final String title;
  final AsyncValue<List<ActionListItem>> asyncCards;
  final String emptyMessage;

  const _BoardColumn({
    required this.title,
    required this.asyncCards,
    required this.emptyMessage,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(width: 8),
              asyncCards.when(
                data: (cards) => Text(
                  '${cards.length}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                loading: () => const SizedBox.shrink(),
                error: (e, _) => const SizedBox.shrink(),
              ),
            ],
          ),
        ),
        Expanded(
          child: asyncCards.when(
            data: (cards) => cards.isEmpty
                ? Center(child: Text(emptyMessage))
                : ListView.builder(
                    itemCount: cards.length,
                    itemBuilder: (context, i) =>
                        ActionCard(action: cards[i]),
                  ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
          ),
        ),
      ],
    );
  }
}

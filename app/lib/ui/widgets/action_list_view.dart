import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;

import '../../data/queries.dart';
import '../edit_action.dart';
import 'action_tile.dart';

/// A plain, tap-to-edit list backed by a live view query (used by All
/// Actions). The Current board and the calendar have their own layout and
/// build directly on the provider instead.
class ActionListView extends ConsumerWidget {
  final ProviderListenable<AsyncValue<List<ActionListItem>>> provider;
  final String emptyMessage;

  /// The list's scroll controller (the All view's marquee scrolls it).
  final ScrollController? controller;

  const ActionListView({
    super.key,
    required this.provider,
    required this.emptyMessage,
    this.controller,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(provider);
    return itemsAsync.when(
      data: (items) => items.isEmpty
          ? Center(child: Text(emptyMessage))
          : ListView.builder(
              controller: controller,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: items.length,
              itemBuilder: (context, i) => ActionTile(
                key: ValueKey(items[i].id),
                action: items[i],
                onTap: () => openActionEditor(context, ref, items[i].id),
              ),
            ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }
}

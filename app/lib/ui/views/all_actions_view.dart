import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/queries.dart';
import '../providers.dart';
import '../widgets/action_list_view.dart';

/// [allActionsProvider] narrowed by [allActionsQueryProvider]: a
/// case-insensitive "contains" on the loaded names. Done in Dart because
/// SQLite's LIKE only folds ASCII (Cyrillic would not match).
final filteredAllActionsProvider =
    Provider.autoDispose<AsyncValue<List<ActionListItem>>>((ref) {
      final all = ref.watch(allActionsProvider);
      final q = ref.watch(allActionsQueryProvider).trim().toLowerCase();
      if (q.isEmpty) return all;
      return all.whenData(
        (items) =>
            items.where((a) => a.name.toLowerCase().contains(q)).toList(),
      );
    });

/// Every action regardless of status (open or done) — the one place to see
/// everything, most recently updated first — with a search field on top.
class AllActionsView extends ConsumerStatefulWidget {
  const AllActionsView({super.key});

  @override
  ConsumerState<AllActionsView> createState() => _AllActionsViewState();
}

class _AllActionsViewState extends ConsumerState<AllActionsView> {
  final _controller = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      if (mounted) ref.read(allActionsQueryProvider.notifier).state = text;
    });
  }

  void _clear() {
    _debounce?.cancel();
    _controller.clear();
    ref.read(allActionsQueryProvider.notifier).state = '';
  }

  @override
  Widget build(BuildContext context) {
    final searching = ref.watch(
      allActionsQueryProvider.select((q) => q.trim().isNotEmpty),
    );
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            key: const ValueKey('allSearchField'),
            controller: _controller,
            onChanged: _onChanged,
            decoration: InputDecoration(
              hintText: 'Search actions',
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              suffixIcon: ValueListenableBuilder<TextEditingValue>(
                valueListenable: _controller,
                builder: (context, v, _) => v.text.isEmpty
                    ? const SizedBox.shrink()
                    : IconButton(
                        key: const ValueKey('allSearchClear'),
                        tooltip: 'Clear',
                        icon: const Icon(Icons.close),
                        onPressed: _clear,
                      ),
              ),
            ),
          ),
        ),
        Expanded(
          child: ActionListView(
            provider: filteredAllActionsProvider,
            emptyMessage: searching
                ? 'No matching actions.'
                : 'No actions yet.',
          ),
        ),
      ],
    );
  }
}

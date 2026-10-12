import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/queries.dart';
import '../../domain/all_actions_view_rules.dart';
import '../providers.dart';
import '../widgets/action_list_view.dart';
import '../widgets/all_actions_options_panel.dart';

/// [allActionsProvider] filtered, searched and sorted by the All list's
/// controls (see `domain/all_actions_view_rules.dart`). Everything is done in
/// Dart over the loaded rows (SQLite's LIKE only folds ASCII, so Cyrillic
/// would not match); the lean link / notes streams are subscribed only while
/// a filter or search flag needs them.
final filteredAllActionsProvider =
    Provider.autoDispose<AsyncValue<List<ActionListItem>>>((ref) {
      final all = ref.watch(allActionsProvider);
      final q = ref.watch(allActionsQueryProvider).trim().toLowerCase();
      final flags = ref.watch(allActionsSearchFlagsProvider);
      final filters = ref.watch(allActionsFiltersProvider);
      final sort = ref.watch(allActionsSortProvider);

      final searching = q.isNotEmpty;
      final useNotes = searching && flags.notes;
      final useDirectionNames = searching && flags.directions;

      Set<String>? notesMatches;
      if (useNotes) {
        final n = ref.watch(allActionsNotesMatchProvider(q));
        if (n.hasError) return AsyncValue.error(n.error!, n.stackTrace!);
        if (!n.hasValue) return const AsyncValue.loading();
        notesMatches = n.requireValue;
      }

      Map<String, Set<String>>? metricIds;
      Map<String, String>? metricNames;
      if (useDirectionNames || filters.metricIds.isNotEmpty) {
        final m = ref.watch(allActionsMetricIdsProvider);
        if (m.hasError) return AsyncValue.error(m.error!, m.stackTrace!);
        if (!m.hasValue) return const AsyncValue.loading();
        metricIds = m.requireValue;
        if (useDirectionNames) {
          metricNames = {
            for (final d in ref.watch(metricsProvider).value ?? const [])
              d.id: d.name.toLowerCase(),
          };
        }
      }

      Map<String, Set<String>>? predecessors;
      if (filters.previous.active) {
        final p = ref.watch(allActionsPredecessorsProvider);
        if (!p.hasValue) return const AsyncValue.loading();
        predecessors = p.requireValue;
      }
      Map<String, Set<String>>? successors;
      if (filters.next.active) {
        final s = ref.watch(allActionsSuccessorsProvider);
        if (!s.hasValue) return const AsyncValue.loading();
        successors = s.requireValue;
      }

      // Urgency is live (changes every minute): only follow it when needed.
      final needsUrgency =
          filters.usesUrgency || sort.any((k) => k.field == SortField.urgency);
      final urgency = needsUrgency
          ? ref.watch(actionUrgencyProvider)
          : const <String, double>{};

      return all.whenData(
        (items) => arrangeActions(
          items: items,
          sort: sort,
          filters: filters,
          query: q,
          flags: flags,
          urgency: urgency,
          links: AllActionsLinkData(
            metricIdsByAction: metricIds,
            metricNamesById: metricNames,
            predecessors: predecessors,
            successors: successors,
          ),
          notesMatches: notesMatches,
        ),
      );
    });

/// Every action regardless of status (open or done) — the one place to see
/// everything — with a search field, sort chips and filters on top. Default
/// order: most recently edited first.
class AllActionsView extends ConsumerStatefulWidget {
  const AllActionsView({super.key});

  @override
  ConsumerState<AllActionsView> createState() => _AllActionsViewState();
}

class _AllActionsViewState extends ConsumerState<AllActionsView> {
  final _controller = TextEditingController();
  Timer? _debounce;
  bool _panelOpen = false;

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
    final narrowed = ref.watch(
      allActionsQueryProvider.select((q) => q.trim().isNotEmpty),
    );
    final filtering = ref.watch(
      allActionsFiltersProvider.select((f) => f.active),
    );
    final flags = ref.watch(allActionsSearchFlagsProvider);
    void setFlags(SearchFlags f) =>
        ref.read(allActionsSearchFlagsProvider.notifier).state = f;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Expanded(
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
              const SizedBox(width: 4),
              IconButton(
                key: const ValueKey('allOptionsToggle'),
                tooltip: _panelOpen
                    ? 'Hide sort and filters'
                    : 'Sort and filters',
                isSelected: _panelOpen || filtering,
                icon: const Icon(Icons.tune),
                onPressed: () => setState(() => _panelOpen = !_panelOpen),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Align(
            alignment: Alignment.centerLeft,
            // One row that scales down to fit a narrow phone (no wrapping).
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Search in',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    key: const ValueKey('searchFlagName'),
                    visualDensity: VisualDensity.compact,
                    label: const Text('Name'),
                    selected: flags.name,
                    onSelected: (v) => setFlags(flags.copyWith(name: v)),
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    key: const ValueKey('searchFlagNotes'),
                    visualDensity: VisualDensity.compact,
                    label: const Text('Notes'),
                    selected: flags.notes,
                    onSelected: (v) => setFlags(flags.copyWith(notes: v)),
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    key: const ValueKey('searchFlagDirections'),
                    visualDensity: VisualDensity.compact,
                    label: const Text('Directions'),
                    selected: flags.directions,
                    onSelected: (v) => setFlags(flags.copyWith(directions: v)),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_panelOpen) const AllActionsOptionsPanel(),
        const SizedBox(height: 12),
        Expanded(
          child: ActionListView(
            provider: filteredAllActionsProvider,
            emptyMessage: narrowed || filtering
                ? 'No matching actions.'
                : 'No actions yet.',
          ),
        ),
      ],
    );
  }
}

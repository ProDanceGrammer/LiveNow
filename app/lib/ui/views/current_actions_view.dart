import '../shortcut_keys.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/queries.dart';
import '../current_selection.dart';
import '../layout.dart';
import '../providers.dart';
import '../theme/glass_theme.dart';
import '../undo.dart';
import '../widgets/action_card.dart';
import '../widgets/glass.dart';
import 'all_day_week_strip.dart';

/// Tint of the two header blocks: only a little deeper than the cards so they
/// read as headings without being heavy. Derived from the theme tokens only.
Color boardHeaderTint(ColorScheme scheme, GlassTheme glass) {
  final base = Color.alphaBlend(
    scheme.primary.withValues(alpha: glass.dark ? 0.08 : 0.35),
    glass.fillStrong,
  );
  // Dark: a weak dose of the shadow token (black) makes it slightly deeper.
  return glass.dark
      ? Color.alphaBlend(
          glass.shadow.withValues(alpha: glass.shadow.a * 0.5),
          base,
        )
      : base;
}

/// Text colour on [boardHeaderTint].
Color boardHeaderTextColor(GlassTheme glass) => glass.textPrimary;

const _kHeaderKey = ValueKey('boardHeader');
const _kShowMoreKey = ValueKey('currentShowMore');

/// The default view: a two-column board (like a Kanban/Trello board),
/// split by completion status rather than by list membership — "done
/// before" on the left, "not finished yet" on the right.
///
/// Cards can be multi-selected (Ctrl/Shift+click, or dragging a rectangle
/// over empty space) and deleted together with the Delete key.
class CurrentActionsView extends ConsumerStatefulWidget {
  const CurrentActionsView({super.key});

  @override
  ConsumerState<CurrentActionsView> createState() => _CurrentActionsViewState();
}

class _CurrentActionsViewState extends ConsumerState<CurrentActionsView> {
  final _focus = FocusNode(debugLabel: 'CurrentActionsView');
  final _marquee = ValueNotifier<Rect?>(null);
  int? _pointer;
  Offset _startLocal = Offset.zero;
  Offset _startGlobal = Offset.zero;
  bool _additive = false;

  /// Phone: which of the two columns is shown (false = Not Done Yet).
  bool _showDone = false;

  @override
  void dispose() {
    _focus.dispose();
    _marquee.dispose();
    super.dispose();
  }

  bool get _addModifier =>
      isPrimaryPressed() ||
      HardwareKeyboard.instance.isShiftPressed;

  /// Walks the built subtree once: the (viewport-clipped) global rect of every
  /// built card, plus the rects of things a drag must not start on.
  ({Map<String, Rect> cards, List<Rect> blockers}) _scan() {
    final cards = <String, Rect>{};
    final blockers = <Rect>[];
    Rect? boxRect(Element e) {
      final ro = e.renderObject;
      if (ro is! RenderBox || !ro.attached || !ro.hasSize) return null;
      return ro.localToGlobal(Offset.zero) & ro.size;
    }

    void visit(Element e) {
      final w = e.widget;
      if (w is ActionCard) {
        var r = boxRect(e);
        if (r != null) {
          // Cards in the list's cache extent are built but not visible.
          final viewport = Scrollable.maybeOf(e)?.context.findRenderObject();
          if (viewport is RenderBox && viewport.hasSize) {
            r = r.intersect(
              viewport.localToGlobal(Offset.zero) & viewport.size,
            );
          }
          // The card's own box excludes the 8x4 margin around the glass, so
          // the gaps between cards count as empty space.
          r = Rect.fromLTRB(r.left + 8, r.top + 4, r.right - 8, r.bottom - 4);
          if (r.width > 0 && r.height > 0) {
            cards[w.action.id] = r;
            blockers.add(r);
          }
        }
        return;
      }
      if (w.key == _kHeaderKey ||
          w.key == _kShowMoreKey ||
          w.key == kAllDayStripKey) {
        final r = boxRect(e);
        if (r != null) blockers.add(r);
      }
      e.visitChildren(visit);
    }

    (context as Element).visitChildren(visit);
    return (cards: cards, blockers: blockers);
  }

  void _down(PointerDownEvent e) {
    _focus.requestFocus();
    if (e.kind != PointerDeviceKind.mouse || e.buttons != kPrimaryMouseButton) {
      return;
    }
    if (_scan().blockers.any((r) => r.contains(e.position))) return;
    _pointer = e.pointer;
    _startLocal = e.localPosition;
    _startGlobal = e.position;
    _additive = _addModifier;
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer != _pointer) return;
    if ((e.localPosition - _startLocal).distance < 4 &&
        _marquee.value == null) {
      return;
    }
    _marquee.value = Rect.fromPoints(_startLocal, e.localPosition);
  }

  void _up(PointerUpEvent e) {
    if (e.pointer != _pointer) return;
    final dragged = _marquee.value != null;
    _pointer = null;
    _marquee.value = null;
    final notifier = ref.read(currentSelectionProvider.notifier);
    if (!dragged) {
      // A plain click on empty space clears.
      if (!_additive) notifier.state = const {};
      return;
    }
    final area = Rect.fromPoints(_startGlobal, e.position);
    final hit = <String>{
      for (final entry in _scan().cards.entries)
        if (entry.value.overlaps(area)) entry.key,
    };
    notifier.state = _additive ? {...notifier.state, ...hit} : hit;
  }

  void _cancel(PointerCancelEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    _marquee.value = null;
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final notifier = ref.read(currentSelectionProvider.notifier);
    final selection = notifier.state;
    if (selection.isEmpty) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      notifier.state = const {};
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.delete) {
      notifier.state = const {};
      runUndoableDeleteMany(context, ref, selection.toList());
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Drops selected ids that no longer exist in either column.
  void _prune() {
    final done = ref.read(currentDoneProvider).value;
    final notDone = ref.read(currentNotDoneProvider).value;
    if (done == null || notDone == null) return;
    final selection = ref.read(currentSelectionProvider);
    if (selection.isEmpty) return;
    final alive = {for (final a in done) a.id, for (final a in notDone) a.id};
    if (selection.every(alive.contains)) return;
    ref.read(currentSelectionProvider.notifier).state = selection
        .where(alive.contains)
        .toSet();
  }

  Widget _doneColumn(
    AsyncValue<List<ActionListItem>> cards,
    AsyncValue<int> total, {
    bool header = true,
    bool compact = false,
  }) => _BoardColumn(
    title: 'Done Before',
    showHeader: header,
    compact: compact,
    asyncCards: cards,
    total: total.value,
    onShowMore: () =>
        ref.read(currentDoneLimitProvider.notifier).state += kCurrentPageSize,
    emptyMessage: 'Nothing done yet.',
  );

  Widget _notDoneColumn(
    AsyncValue<List<ActionListItem>> cards,
    AsyncValue<int> total, {
    bool header = true,
    bool compact = false,
  }) => _BoardColumn(
    title: 'Not Done Yet',
    showHeader: header,
    compact: compact,
    asyncCards: cards,
    total: total.value,
    onShowMore: () => ref.read(currentNotDoneLimitProvider.notifier).state +=
        kCurrentPageSize,
    emptyMessage: 'Nothing left to do.',
  );

  @override
  Widget build(BuildContext context) {
    final doneAsync = ref.watch(currentDoneProvider);
    final notDoneAsync = ref.watch(currentNotDoneProvider);
    final doneCount = ref.watch(currentDoneCountProvider);
    final notDoneCount = ref.watch(currentNotDoneCountProvider);
    ref.listen(currentDoneProvider, (_, _) => _prune());
    ref.listen(currentNotDoneProvider, (_, _) => _prune());
    final primary = Theme.of(context).colorScheme.primary;
    final phone = usePhoneLayout(context);
    // A phone turned sideways has the room for both columns at once (so no
    // switch): they sit side by side under slim titles.
    final landscape =
        phone && MediaQuery.orientationOf(context) == Orientation.landscape;

    return Focus(
      focusNode: _focus,
      onKeyEvent: _key,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _down,
        onPointerMove: _move,
        onPointerUp: _up,
        onPointerCancel: _cancel,
        child: Stack(
          children: [
            // The week's all-day actions above the board (it takes some of the
            // height; with nothing to show it is only a thin row).
            Column(
              children: [
                const AllDayWeekStrip(),
                Expanded(
                  child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: landscape
                  ? Column(
                      children: [
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: _doneColumn(
                                  doneAsync,
                                  doneCount,
                                  compact: true,
                                ),
                              ),
                              Expanded(
                                child: _notDoneColumn(
                                  notDoneAsync,
                                  notDoneCount,
                                  compact: true,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const _PhoneSelectionBar(),
                      ],
                    )
                  : phone
                  ? Column(
                      children: [
                        _PhoneSwitch(
                          showDone: _showDone,
                          onChanged: (v) => setState(() => _showDone = v),
                        ),
                        Expanded(
                          child: _showDone
                              ? _doneColumn(doneAsync, doneCount, header: false)
                              : _notDoneColumn(
                                  notDoneAsync,
                                  notDoneCount,
                                  header: false,
                                ),
                        ),
                        const _PhoneSelectionBar(),
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _doneColumn(doneAsync, doneCount)),
                        Expanded(
                          child: _notDoneColumn(notDoneAsync, notDoneCount),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: ValueListenableBuilder<Rect?>(
                  valueListenable: _marquee,
                  builder: (context, r, _) => r == null
                      ? const SizedBox()
                      : Stack(
                          children: [
                            Positioned.fromRect(
                              rect: r,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: primary.withValues(alpha: 0.15),
                                  border: Border.all(
                                    color: primary.withValues(alpha: 0.8),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BoardColumn extends StatelessWidget {
  final String title;
  final AsyncValue<List<ActionListItem>> asyncCards;

  /// Total number of cards in this column (the page may show fewer).
  final int? total;
  final VoidCallback onShowMore;
  final String emptyMessage;

  /// The title block; a phone shows the column through its own switch instead.
  final bool showHeader;

  /// A slim one-line title instead of the big block (a phone held sideways,
  /// where both columns share a short screen).
  final bool compact;

  const _BoardColumn({
    this.showHeader = true,
    this.compact = false,
    required this.title,
    required this.asyncCards,
    required this.total,
    required this.onShowMore,
    required this.emptyMessage,
  });

  @override
  Widget build(BuildContext context) {
    final glass = context.glass;
    final text = Theme.of(context).textTheme;
    final textColor = boardHeaderTextColor(glass);
    // A compact glass header block, then the cards directly on the page
    // background (no big surface behind them).
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 6, vertical: compact ? 4 : 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showHeader && compact)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                title,
                key: _kHeaderKey,
                textAlign: TextAlign.center,
                style: text.titleSmall?.copyWith(color: textColor),
              ),
            ),
          if (showHeader && !compact)
            GlassSurface(
              key: _kHeaderKey,
              radius: 20,
              blurWindow: false,
              // The deeper tint sits inside the glass edge (1.2 px) so the
              // bright border stays visible.
              child: Padding(
                padding: const EdgeInsets.all(1.2),
                child: DecoratedBox(
                  key: const ValueKey('boardHeaderTint'),
                  decoration: BoxDecoration(
                    color: boardHeaderTint(
                      Theme.of(context).colorScheme,
                      glass,
                    ),
                    borderRadius: BorderRadius.circular(18.8),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Text(
                      title,
                      textAlign: TextAlign.center,
                      style: text.titleMedium?.copyWith(color: textColor),
                    ),
                  ),
                ),
              ),
            ),
          if (showHeader && !compact) const SizedBox(height: 8),
          Expanded(
            child: asyncCards.when(
              // Raising the page size restarts the query; keep the cards
              // (and the scroll position) on screen meanwhile.
              skipLoadingOnReload: true,
              data: (cards) {
                if (cards.isEmpty) return Center(child: Text(emptyMessage));
                final hasMore = (total ?? 0) > cards.length;
                return ListView.builder(
                  // Sideways on a phone the round + button floats over the
                  // right column: leave room to scroll the last card past it.
                  padding: EdgeInsets.only(bottom: compact ? 80 : 0),
                  itemCount: cards.length + (hasMore ? 1 : 0),
                  itemBuilder: (context, i) => i == cards.length
                      ? Align(
                          alignment: Alignment.center,
                          child: TextButton(
                            key: _kShowMoreKey,
                            onPressed: onShowMore,
                            child: const Text('Show more'),
                          ),
                        )
                      : ActionCard(
                          key: ValueKey(cards[i].id),
                          action: cards[i],
                        ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
            ),
          ),
        ],
      ),
    );
  }
}

/// Phone: the two board columns as a two-button switch (same tinted blocks as
/// the desktop headers; the chosen one is outlined).
class _PhoneSwitch extends StatelessWidget {
  const _PhoneSwitch({required this.showDone, required this.onChanged});

  final bool showDone;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final glass = context.glass;
    final scheme = Theme.of(context).colorScheme;
    Widget block(String label, bool done) {
      final selected = showDone == done;
      return Expanded(
        child: GlassSurface(
          key: ValueKey(done ? 'board-switch-done' : 'board-switch-notdone'),
          radius: 20,
          shadow: false,
          blurWindow: false,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => onChanged(done),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? boardHeaderTint(scheme, glass) : null,
                borderRadius: BorderRadius.circular(20),
                border: selected
                    ? Border.all(color: scheme.primary, width: 2)
                    : null,
              ),
              child: Text(
                label,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: boardHeaderTextColor(glass),
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 8, 6, 0),
      child: Row(
        children: [
          block('Done Before', true),
          const SizedBox(width: 8),
          block('Not Done Yet', false),
        ],
      ),
    );
  }
}

/// Phone: after a long-press selected cards, a bar to delete or clear them.
class _PhoneSelectionBar extends ConsumerWidget {
  const _PhoneSelectionBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selection = ref.watch(currentSelectionProvider);
    if (selection.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
      child: GlassSurface(
        key: const ValueKey('phone-selection-bar'),
        radius: 20,
        shadow: false,
        blurWindow: false,
        child: Row(
          children: [
            IconButton(
              tooltip: 'Clear selection',
              icon: const Icon(Icons.close),
              onPressed: () =>
                  ref.read(currentSelectionProvider.notifier).state = const {},
            ),
            Expanded(child: Text('${selection.length} selected')),
            TextButton.icon(
              key: const ValueKey('phone-selection-delete'),
              style: TextButton.styleFrom(foregroundColor: scheme.error),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete'),
              onPressed: () {
                final ids = selection.toList();
                ref.read(currentSelectionProvider.notifier).state = const {};
                runUndoableDeleteMany(context, ref, ids);
              },
            ),
          ],
        ),
      ),
    );
  }
}

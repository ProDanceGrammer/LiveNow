import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/global_search.dart';
import 'root_navigator.dart';
import 'widgets/global_search_dialog.dart';

/// Marks one page of a `TabBarView`: those pages stay alive (and keep their
/// tickers) while another tab is shown, so "visible" has to be asked of the tab
/// controller. A [SearchTargetState] inside a [TabPage] is current only while its
/// tab is the selected one.
class TabPage extends InheritedWidget {
  const TabPage({
    super.key,
    required this.controller,
    required this.index,
    required super.child,
  });

  final TabController controller;
  final int index;

  bool get selected => controller.index == index;

  static TabPage? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<TabPage>();

  @override
  bool updateShouldNotify(TabPage oldWidget) => false;
}

/// A view that has a search bar and can open / focus it on Ctrl+F.
class SearchTarget {
  const SearchTarget({required this.isCurrent, required this.open});

  /// True while the view is the one the user is looking at (not a hidden,
  /// kept-alive section, not a tab that is off screen, not under a dialog).
  final bool Function() isCurrent;

  /// Shows the search field when it sits behind an icon, focuses it and selects
  /// its text.
  final void Function() open;
}

/// The views that registered a search; Ctrl+F asks them in turn.
class SearchTargets {
  final _targets = <SearchTarget>[];

  void add(SearchTarget t) => _targets.add(t);
  void remove(SearchTarget t) => _targets.remove(t);

  /// What the shell opens when no view claims Ctrl+F (a section without a search
  /// bar): the Ctrl+K window for the section on screen.
  Set<SearchSection> Function()? fallbackScope;

  /// Ctrl+F. The most recently registered current view wins (a dialog's search
  /// before the page's); when none is current and nothing is on top of the page,
  /// the Ctrl+K window opens, scoped to what the shell says is on screen.
  void trigger() {
    for (final t in _targets.reversed) {
      if (t.isCurrent()) {
        t.open();
        return;
      }
    }
    final nav = rootNavigatorKey.currentState;
    final overlay = nav?.overlay;
    // A dialog or another route is open and has no search: leave it alone.
    if (nav == null || overlay == null || !overlay.mounted || nav.canPop()) {
      return;
    }
    openGlobalSearch(sections: fallbackScope?.call() ?? const {});
  }
}

/// Opens the Ctrl+K window (or closes it when it is open) from anywhere: it needs
/// a context inside the navigator, which the root navigator's overlay has.
void openGlobalSearch({Set<SearchSection> sections = const {}}) {
  final overlay = rootNavigatorKey.currentState?.overlay;
  if (overlay == null || !overlay.mounted) return;
  GlobalSearchDialog.toggle(overlay.context, sections: sections);
}

final searchTargetsProvider = Provider<SearchTargets>((ref) => SearchTargets());

/// For a [State] that owns a search bar: call [registerSearchTarget] in
/// `initState` and [unregisterSearchTarget] in `dispose`, and implement
/// [openSearch]. [searchIsCurrent] may be tightened (e.g. "only on this tab").
mixin SearchTargetState<T extends StatefulWidget> on State<T> {
  SearchTarget? _searchTarget;
  SearchTargets? _searchRegistry;

  /// Shows the field if needed, focuses it and selects its text.
  void openSearch();

  /// Extra conditions beyond "visible and on the top route".
  bool get searchIsCurrent => true;

  bool _isCurrent() {
    if (!mounted) return false;
    // Hidden kept-alive sections have their tickers switched off.
    if (!TickerMode.getValuesNotifier(context).value.enabled) return false;
    // A dialog on top hides the page's search bars.
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return false;
    // A page of a TabBarView that another tab has covered.
    final page = TabPage.maybeOf(context);
    if (page != null && !page.selected) return false;
    return searchIsCurrent;
  }

  void registerSearchTarget() {
    final container = ProviderScope.containerOf(context, listen: false);
    _searchRegistry = container.read(searchTargetsProvider);
    _searchTarget = SearchTarget(isCurrent: _isCurrent, open: openSearch);
    _searchRegistry!.add(_searchTarget!);
  }

  void unregisterSearchTarget() {
    final t = _searchTarget;
    if (t != null) _searchRegistry?.remove(t);
    _searchTarget = null;
  }
}

/// Focuses [node] on the next frame (after a field that was behind an icon has
/// been built) and selects everything in [controller].
void focusSearchField(FocusNode node, TextEditingController controller) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    node.requestFocus();
    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: controller.text.length,
    );
  });
}

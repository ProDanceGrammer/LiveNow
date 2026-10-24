import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/capped_read.dart';
import '../../domain/action_import_service.dart';
import '../calendar_fullscreen.dart';
import '../current_icons.dart';
import '../layout.dart';
import '../providers.dart';
import '../views/all_actions_view.dart';
import '../views/calendar_view.dart';
import '../views/current_actions_view.dart';
import '../search_targets.dart';
import '../widgets/glass.dart';
import 'forms_screen.dart';
import 'templates_screen.dart';

/// Asks the user for the Notion actions export and returns its text (null =
/// cancelled). A provider so tests can replace the native file dialog.
final actionsCsvPickerProvider = Provider<Future<String?> Function()>(
  (ref) => () async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'CSV',
          extensions: ['csv'],
          // iOS ignores extensions: it needs type identifiers (without them
          // the picker shows nothing selectable).
          uniformTypeIdentifiers: [
            'public.comma-separated-values-text',
            'public.text',
          ],
          mimeTypes: ['text/csv', 'text/plain'],
        ),
      ],
    );
    return file == null ? null : readTextCapped(file);
  },
);

final actionImportServiceProvider = Provider<ActionImportService>(
  (ref) => ActionImportService(ref.watch(databaseProvider)),
);

/// The views inside the Actions section, in switch order.
enum ActionsSub {
  current('Current Actions', 'Current Actions', Icons.bolt_rounded),
  calendar('Calendar', 'Calendar', Icons.event),
  all('All', 'All Actions', Icons.list_alt_rounded),
  templates('Templates', 'Templates', Icons.dashboard_customize),
  forms('Forms', 'Forms', Icons.fact_check_outlined);

  const ActionsSub(this.label, this.title, this.icon);

  /// The tab's icon.
  final IconData icon;

  /// Tab text.
  final String label;

  /// Tab text on a phone (shorter: three tabs share the width).
  String get phoneLabel => this == current ? 'Current' : label;

  /// Page (AppBar) title while this view is shown.
  final String title;
}

/// The Actions section: a compact glass switch on top and either the Current
/// Actions board or the Calendar below it. Like the shell's sections, a
/// sub-view is built the first time it is shown and then kept alive hidden
/// (no painting, no focus). The swap is instant (no animation).
class ActionsSection extends ConsumerStatefulWidget {
  const ActionsSection({super.key, required this.sub, required this.onChanged});

  final ActionsSub sub;
  final ValueChanged<ActionsSub> onChanged;

  @override
  ConsumerState<ActionsSection> createState() => _ActionsSectionState();
}

class _ActionsSectionState extends ConsumerState<ActionsSection>
    with SingleTickerProviderStateMixin, SearchTargetState<ActionsSection> {
  final _visited = <ActionsSub>{};
  bool _calendarShown = false;
  late final TabController _tabs;

  static Widget _viewFor(ActionsSub sub) => switch (sub) {
    ActionsSub.current => const CurrentActionsView(),
    ActionsSub.calendar => const CalendarView(),
    ActionsSub.all => const AllActionsView(),
    ActionsSub.templates => const TemplatesScreen(embedded: true),
    ActionsSub.forms => const FormsScreen(),
  };

  @override
  void initState() {
    super.initState();
    // Instant tab switch: zero animation duration, driven by [widget.sub].
    _tabs = TabController(
      length: ActionsSub.values.length,
      initialIndex: widget.sub.index,
      vsync: this,
      animationDuration: Duration.zero,
    )..addListener(_onTab);
    registerSearchTarget();
  }

  // Ctrl+F: the Current board's search (only while that tab is shown).
  @override
  bool get searchIsCurrent => widget.sub == ActionsSub.current;

  @override
  void openSearch() {
    if (!_searchOpen) setState(() => _searchOpen = true);
    focusSearchField(_searchFocus, _searchText);
  }

  void _onTab() {
    final picked = ActionsSub.values[_tabs.index];
    if (picked != widget.sub) widget.onChanged(picked);
  }

  @override
  void didUpdateWidget(ActionsSection old) {
    super.didUpdateWidget(old);
    if (_tabs.index != widget.sub.index) _tabs.index = widget.sub.index;
  }

  @override
  void dispose() {
    unregisterSearchTarget();
    _searchDebounce?.cancel();
    _searchText.dispose();
    _searchFocus.dispose();
    _tabs.dispose();
    super.dispose();
  }

  // The Current board's name search: the field is shown by the icon next to
  // the direction-icons switch; typing filters after a 200 ms pause, closing
  // the field clears the filter.
  bool _searchOpen = false;
  final _searchText = TextEditingController();
  final _searchFocus = FocusNode();
  Timer? _searchDebounce;

  void _toggleSearch() {
    setState(() => _searchOpen = !_searchOpen);
    if (!_searchOpen) {
      _searchText.clear();
      _applySearch('');
    }
  }

  void _onSearchChanged(String text) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(
      const Duration(milliseconds: 200),
      () => _applySearch(text),
    );
  }

  void _applySearch(String text) {
    _searchDebounce?.cancel();
    ref.read(currentSearchProvider.notifier).state = text;
  }

  @override
  Widget build(BuildContext context) {
    _visited.add(widget.sub);
    // The shell hides inactive sections with a disabled TickerMode, so this
    // is "the Actions section is on screen". Hand keyboard focus to the
    // Calendar whenever it becomes the shown view (after this frame, once
    // ExcludeFocus has been lifted from it).
    final shown =
        widget.sub == ActionsSub.calendar &&
        TickerMode.valuesOf(context).enabled;
    if (shown && !_calendarShown) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(calendarFocusRequestProvider.notifier).state++;
      });
    }
    _calendarShown = shown;
    final phone = usePhoneLayout(context);
    // Phone Calendar in full screen: the view tabs go away too.
    final fullCalendar =
        phone &&
        widget.sub == ActionsSub.calendar &&
        ref.watch(phoneCalendarFullProvider);
    return Column(
      children: [
        if (!fullCalendar)
          Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 4, 4),
                  child: GlassSurface(
                    radius: 20,
                    shadow: false,
                    blurWindow: false,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: TabBar(
                        key: const ValueKey('actions-switch'),
                        controller: _tabs,
                        // Four tabs plus the two icon buttons do not fit 375 px:
                        // on a phone the tabs scroll sideways instead of
                        // clipping their names.
                        isScrollable: phone,
                        tabAlignment: phone ? TabAlignment.start : null,
                        splashFactory: NoSplash.splashFactory,
                        labelPadding: phone
                            ? const EdgeInsets.symmetric(horizontal: 12)
                            : null,
                        tabs: [
                          for (final s in ActionsSub.values)
                            Tab(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(s.icon, size: 18),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      phone ? s.phoneLabel : s.label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (widget.sub == ActionsSub.current)
                Builder(
                  builder: (context) {
                    final on = ref.watch(currentIconsProvider);
                    final scheme = Theme.of(context).colorScheme;
                    return IconButton(
                      key: const ValueKey('current-icons-toggle'),
                      isSelected: on,
                      // The same icon as the 'Growth directions' rail item.
                      icon: const Icon(Icons.insights),
                      tooltip: on
                          ? 'Hide growth direction icons'
                          : 'Show growth direction icons',
                      style: IconButton.styleFrom(
                        backgroundColor: on ? scheme.primaryContainer : null,
                        foregroundColor: on ? scheme.onPrimaryContainer : null,
                      ),
                      onPressed: () =>
                          ref.read(currentIconsProvider.notifier).toggle(),
                    );
                  },
                ),
              if (widget.sub == ActionsSub.current)
                IconButton(
                  key: const ValueKey('current-search-toggle'),
                  isSelected: _searchOpen,
                  icon: Icon(_searchOpen ? Icons.search_off : Icons.search),
                  tooltip: _searchOpen ? 'Close search' : 'Search actions',
                  onPressed: _toggleSearch,
                ),
              const SizedBox(width: 8),
            ],
          ),
        if (_searchOpen && widget.sub == ActionsSub.current)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: TextField(
              key: const ValueKey('current-search-field'),
              controller: _searchText,
              focusNode: _searchFocus,
              autofocus: true,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search by name',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Clear',
                  onPressed: () {
                    _searchText.clear();
                    _applySearch('');
                  },
                ),
              ),
              onChanged: _onSearchChanged,
            ),
          ),
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              for (final s in ActionsSub.values)
                if (_visited.contains(s))
                  Visibility(
                    key: ValueKey('actions-view-${s.name}'),
                    visible: s == widget.sub,
                    maintainState: true,
                    child: ExcludeFocus(
                      excluding: s != widget.sub,
                      child: _viewFor(s),
                    ),
                  ),
            ],
          ),
        ),
      ],
    );
  }
}

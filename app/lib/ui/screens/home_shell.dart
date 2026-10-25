import 'dart:io' show Platform;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show ServicesBinding;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../widgets/action_editor.dart';
import '../accounts/account_providers.dart';
import '../../data/reminders/reminder_scheduler.dart';
import '../backup_providers.dart';
import '../calendar_fullscreen.dart';
import '../current_selection.dart';
import '../layout.dart';
import '../../domain/plan_service.dart' show PlanConfirmResult;
import '../plan_providers.dart' show planServiceProvider;
import '../providers.dart' show setCalendarDayCount;
import '../notch_side.dart';
import '../rail_collapsed.dart';
import '../reminders.dart';
import '../theme_mode.dart';
import '../widgets/app_toast.dart' show toastBottomInset;
import '../widgets/glass.dart';
import '../../domain/global_search.dart' show SearchSection;
import '../search_targets.dart';
import '../sync_providers.dart';
import '../text_tool_access.dart';
import '../widgets/instant_rail.dart';
import '../widgets/sync_status_button.dart';
import 'actions_section.dart';
import 'budget_screen.dart';
import 'forms_screen.dart';
import 'growth_directions_screen.dart';
import 'settings_screen.dart';
import 'templates_screen.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell>
    with WidgetsBindingObserver {
  ReminderScheduler? _reminders;
  final _textToolAccess = TextToolAccess();

  int _index = 0;
  bool _phoneCalendarInit = false;
  final _bodyKey = GlobalKey();

  /// Sections opened so far. A section is built the first time it is shown
  /// and then kept alive (hidden, not painted, no tickers, no focus), so
  /// switching back is instant instead of rebuilding the screen and
  /// re-running its queries every time.
  final _visited = <int>{0};

  /// Which view the Actions section (index 0) shows.
  ActionsSub _actionsSub = ActionsSub.current;

  /// What Ctrl+F opens in a section without a search bar of its own: the Ctrl+K
  /// window, narrowed to what is on screen (the Calendar shows actions, Growth
  /// directions; elsewhere everything).
  Set<SearchSection> _searchScope() => switch (_index) {
    0 => _actionsSub == ActionsSub.calendar ? {SearchSection.actions} : {},
    1 => {SearchSection.directions},
    _ => {},
  };

  @override
  void initState() {
    super.initState();
    ref.read(searchTargetsProvider).fallbackScope = _searchScope;
    // Sync starts with the app (the PC opens its server when a phone is
    // paired, a phone syncs). Never under `flutter test`: no sockets there.
    if (!Platform.environment.containsKey('FLUTTER_TEST')) {
      // Only the main account syncs (see syncAllowedProvider).
      if (ref.read(syncAllowedProvider)) {
        Future<void>.microtask(() => startSyncForRole(ref));
      }
      // Start/end notifications (iOS, Windows): no polling, see reminders.dart.
      Future<void>.microtask(() => _reminders = startReminders(ref));
      // The 5-hourly backup file (desktop, only when switched on in Settings).
      if (autoBackupSupported) {
        Future<void>.microtask(
          () => ref.read(autoBackupSchedulerProvider).reschedule(),
        );
      }
      // Plan items marked "forever" keep the next 8 weeks filled in. Desktop
      // only, so a PC and a phone do not both generate the same occurrences
      // before they have synced.
      if (autoBackupSupported) {
        Future<void>.microtask(
          () => ref.read(planServiceProvider).refillForever().catchError(
            (Object _) => const PlanConfirmResult([], 0),
          ),
        );
      }
      WidgetsBinding.instance.addObserver(this);
      // Accessibility tree for other programs' text tools (Settings switch).
      ref.listenManual(
        textToolAccessProvider,
        (_, on) => _textToolAccess.apply(on),
        fireImmediately: true,
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back in the foreground: re-plan from what is already loaded.
    if (state == AppLifecycleState.resumed) {
      _reminders?.resume();
      if (autoBackupSupported) {
        ref.read(autoBackupSchedulerProvider).reschedule();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reminders?.dispose();
    _textToolAccess.dispose();
    super.dispose();
  }

  static const _destinations = [
    InstantRailItem(icon: Icons.checklist_rounded, label: 'Actions'),
    InstantRailItem(icon: Icons.insights, label: 'Growth directions'),
    InstantRailItem(
      icon: Icons.account_balance_wallet_outlined,
      label: 'Budget',
    ),
  ];

  /// Bottom-navigation labels on a phone (the rail's two-line ones are long).
  static const _phoneLabels = ['Actions', 'Growth Directions', 'Budget'];

  static const _titles = [
    null, // Actions: the active sub-view's name
    'Growth directions',
    'Budget',
  ];

  /// Index of the first section that is its own Scaffold (with its own FAB).
  static const _firstOwnScaffold = 1;

  Widget _viewFor(int i) => switch (i) {
    0 => ActionsSection(
      sub: _actionsSub,
      onChanged: (s) => setState(() {
        if (s == ActionsSub.calendar) {
          ref.read(phoneCalendarFullProvider.notifier).state = true;
        }
        _actionsSub = s;
      }),
    ),
    1 => const GrowthDirectionsScreen(),
    _ => const BudgetScreen(),
  };

  @override
  Widget build(BuildContext context) {
    if (usePhoneLayout(context)) {
      // Android's Back button / gesture: dialogs are their own routes and pop
      // first; here Back steps out of a section (Budget -> Actions, Calendar ->
      // Current Actions) and only leaves the app from the first screen.
      final atHome = _index == 0 && _actionsSub == ActionsSub.current;
      return PopScope(
        canPop: atHome,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          setState(() {
            if (_index != 0) {
              _index = 0;
              _visited.add(0);
            } else {
              _actionsSub = ActionsSub.current;
            }
          });
        },
        child: _buildPhone(context),
      );
    }
    if (toastBottomInset.value != 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        toastBottomInset.value = 0;
      });
    }
    return Column(
      children: [
        _buildMenuBar(context),
        Expanded(child: _buildScaffold(context)),
      ],
    );
  }

  /// The round "new" button of the Actions section: a new action, or a new
  /// template while the Templates tab is open.
  Widget _newFab(BuildContext context) {
    final templates = _actionsSub == ActionsSub.templates;
    final forms = _actionsSub == ActionsSub.forms;
    return FloatingActionButton(
      heroTag: null,
      onPressed: () => templates
          ? TemplatesScreen.showNewTemplate(context)
          : forms
          ? FormsScreen.showNewForm(context)
          : ActionEditorDialog.show(context),
      tooltip: templates
          ? 'New template'
          : forms
          ? 'New form'
          : 'New action',
      child: const Icon(Icons.add),
    );
  }

  /// The sections opened so far, only the selected one visible.
  Widget _sections() => Stack(
    fit: StackFit.expand,
    children: [
      for (var i = 0; i < _titles.length; i++)
        if (_visited.contains(i))
          Visibility(
            key: ValueKey('shell-view-$i'),
            visible: i == _index,
            maintainState: true,
            child: ExcludeFocus(excluding: i != _index, child: _viewFor(i)),
          ),
    ],
  );

  /// The phone layout: app bar, the sections, bottom navigation. No menu bar,
  /// no side rail, dark mode lives in the app bar's menu.
  Widget _buildPhone(BuildContext context) {
    if (!_phoneCalendarInit) {
      // A phone starts the calendar on one day (the setting is kept).
      _phoneCalendarInit = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setCalendarDayCount(ref, 1);
      });
    }
    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;
    // The Calendar fills the whole screen on a phone: no app bar, no view
    // tabs (ActionsSection hides them too) and no bottom navigation.
    final full =
        (_index == 0 &&
            _actionsSub == ActionsSub.calendar &&
            ref.watch(phoneCalendarFullProvider)) ||
        (_index == 1 && ref.watch(phoneMindmapFullProvider));
    // Toasts sit above the bottom navigation while it is on screen.
    // Landscape trades the title row and bottom bar for a slim side rail
    // (more height for the content, and it clears the camera notch).
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final navInset = (full || landscape) ? 0.0 : 80.0;
    if (toastBottomInset.value != navInset) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        toastBottomInset.value = navInset;
      });
    }
    final body = Stack(
      // Keeps the sections' state when the layout around them changes (full
      // screen, landscape rail).
      key: _bodyKey,
      children: [
        Positioned.fill(child: _sections()),
        // Hidden while cards are selected: it sat on top of the selection
        // bar's Delete button.
        if (_index < _firstOwnScaffold &&
            !full &&
            ref.watch(currentSelectionProvider).isEmpty)
          Positioned(right: 16, bottom: 16, child: _newFab(context)),
      ],
    );
    if (landscape && !full) {
      return Scaffold(
        body: SafeArea(
          child: Row(
            children: [
              _buildLandscapeRail(context, isDark),
              Expanded(child: body),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      appBar: full
          ? null
          : AppBar(
              title: Text(
                _titles[_index] ?? _actionsSub.title,
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontSize: 22),
              ),
              actions: [
                const SyncStatusButton(),
                PopupMenuButton<String>(
                  key: const ValueKey('phone-menu'),
                  onSelected: (v) => v == 'settings'
                      ? SettingsScreen.open(context)
                      : ref.read(themeModeProvider.notifier).toggle(),
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      key: ValueKey('phone-menu-settings'),
                      value: 'settings',
                      child: Text('Settings'),
                    ),
                    CheckedPopupMenuItem(
                      value: 'dark',
                      checked: isDark,
                      child: const Text('Dark mode'),
                    ),
                  ],
                ),
              ],
            ),
      // Full screen sideways: only the notch side keeps its safe-area band, the
      // other side is used (iOS reports the same inset on both sides).
      body: full
          ? SafeArea(
              left: !landscape || ref.watch(notchOnLeftProvider),
              right: !landscape || !ref.watch(notchOnLeftProvider),
              bottom: false,
              child: body,
            )
          : body,
      bottomNavigationBar: full
          ? null
          : GlassSurface(
              radius: 0,
              shadow: false,
              // A smaller label so "Growth Directions" stays on ONE line (a
              // wrapped label pushed its icon up out of line with the others).
              child: NavigationBarTheme(
                data: NavigationBarTheme.of(context).copyWith(
                  labelPadding: EdgeInsets.zero,
                  labelTextStyle: WidgetStatePropertyAll(
                    Theme.of(context).textTheme.labelMedium
                        ?.copyWith(fontSize: 10.5, fontWeight: FontWeight.w500),
                  ),
                ),
                child: NavigationBar(
                  key: const ValueKey('phone-nav'),
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  selectedIndex: _index,
                  onDestinationSelected: (i) => setState(() {
                    if (i == 0 && _actionsSub == ActionsSub.calendar) {
                      ref.read(phoneCalendarFullProvider.notifier).state = true;
                    }
                    _index = i;
                    _visited.add(i);
                  }),
                  destinations: [
                    for (var i = 0; i < _destinations.length; i++)
                      NavigationDestination(
                        icon: Icon(_destinations[i].icon),
                        label: _phoneLabels[i],
                      ),
                  ],
                ),
              ),
            ),
    );
  }

  /// Landscape phone: the three sections as an icon-only strip on the left,
  /// with sync and the menu at its bottom (the way the desktop rail collapses).
  Widget _buildLandscapeRail(BuildContext context, bool isDark) {
    final scheme = Theme.of(context).colorScheme;
    return GlassSurface(
      key: const ValueKey('phone-rail'),
      radius: 0,
      shadow: false,
      child: SizedBox(
        width: 56,
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            children: [
              const SizedBox(height: 4),
              for (var i = 0; i < _destinations.length; i++)
                IconButton(
                  key: ValueKey('phone-rail-$i'),
                  isSelected: i == _index,
                  tooltip: _phoneLabels[i],
                  icon: Icon(_destinations[i].icon),
                  style: IconButton.styleFrom(
                    backgroundColor: i == _index
                        ? scheme.primaryContainer
                        : null,
                    foregroundColor: i == _index
                        ? scheme.onPrimaryContainer
                        : null,
                  ),
                  onPressed: () => setState(() {
                    if (i == 0 && _actionsSub == ActionsSub.calendar) {
                      ref.read(phoneCalendarFullProvider.notifier).state = true;
                    }
                    _index = i;
                    _visited.add(i);
                  }),
                ),
              const Spacer(),
              const SyncStatusButton(),
              PopupMenuButton<String>(
                key: const ValueKey('phone-menu'),
                onSelected: (v) => v == 'settings'
                    ? SettingsScreen.open(context)
                    : ref.read(themeModeProvider.notifier).toggle(),
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    key: ValueKey('phone-menu-settings'),
                    value: 'settings',
                    child: Text('Settings'),
                  ),
                  CheckedPopupMenuItem(
                    value: 'dark',
                    checked: isDark,
                    child: const Text('Dark mode'),
                  ),
                ],
              ),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuBar(BuildContext context) {
    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;
    return GlassSurface(
      radius: 0,
      shadow: false,
      child: Material(
        color: Colors.transparent,
        child: Align(
          alignment: Alignment.centerLeft,
          child: MenuBar(
            style: const MenuStyle(
              elevation: WidgetStatePropertyAll(0),
              backgroundColor: WidgetStatePropertyAll(Colors.transparent),
              shape: WidgetStatePropertyAll(RoundedRectangleBorder()),
            ),
            children: [
              SubmenuButton(
                menuChildren: [
                  MenuItemButton(
                    key: const ValueKey('menu-settings'),
                    onPressed: () => SettingsScreen.open(context),
                    // Plain labels: MenuAcceleratorLabel('&File') makes MenuBar
                    // own Alt (a lone Alt focuses the bar, Alt+F/V/S/X/D are
                    // consumed), and Alt is reserved for the owner's own hotkeys.
                    child: const Text('Settings…'),
                  ),
                  MenuItemButton(
                    onPressed: () => ServicesBinding.instance.exitApplication(
                      ui.AppExitType.required,
                    ),
                    child: const Text('Exit'),
                  ),
                ],
                child: const Text('File'),
              ),
              SubmenuButton(
                menuChildren: [
                  CheckboxMenuButton(
                    value: isDark,
                    onChanged: (_) =>
                        ref.read(themeModeProvider.notifier).toggle(),
                    // Label only: the binding itself lives in main.dart's
                    // CallbackShortcuts (above the Navigator, so dialogs get it
                    // too). A `shortcut:` here would register a second binding.
                    trailingIcon: Text(
                      'Ctrl+Shift+L',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    child: const Text('Dark mode'),
                  ),
                ],
                child: const Text('View'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    final collapsed = ref.watch(railCollapsedProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_index] ?? _actionsSub.title),
        actions: const [SyncStatusButton(), SizedBox(width: 8)],
      ),
      // The New-action FAB is drawn here instead of via Scaffold.
      // floatingActionButton: the Scaffold runs a 200 ms scale transition
      // whenever its FAB appears/disappears, even with noAnimation, and the
      // section switch must leave nothing animating. Growth directions and
      // Templates are their own Scaffolds with their own FAB; only Actions
      // (both sub-views) and All show this one.
      body: Stack(
        children: [
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, box) => Row(
                children: [
                  // Scrollable so the rail never overflows if there isn't enough
                  // vertical space for every destination (e.g. a short window).
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 0, 12),
                    child: GlassSurface(
                      child: SingleChildScrollView(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: box.maxHeight - 12,
                          ),
                          child: IntrinsicHeight(
                            child: InstantRail(
                              selectedIndex: _index,
                              onSelected: (i) => setState(() {
                                _index = i;
                                _visited.add(i);
                              }),
                              items: _destinations,
                              collapsed: collapsed,
                              onToggleCollapsed: () => ref
                                  .read(railCollapsedProvider.notifier)
                                  .toggle(),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const VerticalDivider(
                    width: 12,
                    thickness: 0,
                    color: Colors.transparent,
                  ),
                  Expanded(child: _sections()),
                ],
              ),
            ),
          ),
          if (_index < _firstOwnScaffold)
            Positioned(right: 16, bottom: 16, child: _newFab(context)),
        ],
      ),
    );
  }
}

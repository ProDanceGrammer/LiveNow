import 'dart:io' show Platform;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show ServicesBinding;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../widgets/action_editor.dart';
import '../../data/reminders/reminder_scheduler.dart';
import '../calendar_fullscreen.dart';
import '../current_selection.dart';
import '../layout.dart';
import '../providers.dart' show setCalendarDayCount;
import '../rail_collapsed.dart';
import '../reminders.dart';
import '../theme_mode.dart';
import '../widgets/app_toast.dart' show toastBottomInset;
import '../widgets/glass.dart';
import '../sync_providers.dart';
import '../widgets/instant_rail.dart';
import '../widgets/sync_status_button.dart';
import 'actions_section.dart';
import 'budget_screen.dart';
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

  int _index = 0;
  bool _phoneCalendarInit = false;

  /// Sections opened so far. A section is built the first time it is shown
  /// and then kept alive (hidden, not painted, no tickers, no focus), so
  /// switching back is instant instead of rebuilding the screen and
  /// re-running its queries every time.
  final _visited = <int>{0};

  /// Which view the Actions section (index 0) shows.
  ActionsSub _actionsSub = ActionsSub.current;

  @override
  void initState() {
    super.initState();
    // Sync starts with the app (the PC opens its server when a phone is
    // paired, a phone syncs). Never under `flutter test`: no sockets there.
    if (!Platform.environment.containsKey('FLUTTER_TEST')) {
      Future<void>.microtask(() => startSyncForRole(ref));
      // Start/end notifications (iOS, Windows): no polling, see reminders.dart.
      Future<void>.microtask(() => _reminders = startReminders(ref));
      WidgetsBinding.instance.addObserver(this);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back in the foreground: re-plan from what is already loaded.
    if (state == AppLifecycleState.resumed) _reminders?.resume();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reminders?.dispose();
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
    if (usePhoneLayout(context)) return _buildPhone(context);
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
    return FloatingActionButton(
      onPressed: () => templates
          ? TemplatesScreen.showNewTemplate(context)
          : ActionEditorDialog.show(context),
      tooltip: templates ? 'New template' : 'New action',
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
        _index == 0 &&
        _actionsSub == ActionsSub.calendar &&
        ref.watch(phoneCalendarFullProvider);
    // Toasts sit above the bottom navigation while it is on screen.
    final navInset = full ? 0.0 : 80.0;
    if (toastBottomInset.value != navInset) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        toastBottomInset.value = navInset;
      });
    }
    final body = Stack(
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
      body: full ? SafeArea(bottom: false, child: body) : body,
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
                    Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w500,
                    ),
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
                    child: const MenuAcceleratorLabel('&Settings…'),
                  ),
                  MenuItemButton(
                    onPressed: () => ServicesBinding.instance.exitApplication(
                      ui.AppExitType.required,
                    ),
                    child: const MenuAcceleratorLabel('E&xit'),
                  ),
                ],
                child: const MenuAcceleratorLabel('&File'),
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
                    child: const MenuAcceleratorLabel('&Dark mode'),
                  ),
                ],
                child: const MenuAcceleratorLabel('&View'),
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

import 'dart:io' show Platform;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show ServicesBinding;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../widgets/action_editor.dart';
import '../layout.dart';
import '../providers.dart' show setCalendarDayCount;
import '../rail_collapsed.dart';
import '../theme_mode.dart';
import '../widgets/glass.dart';
import '../sync_providers.dart';
import '../widgets/instant_rail.dart';
import '../widgets/sync_status_button.dart';
import 'actions_section.dart';
import 'budget_screen.dart';
import 'growth_directions_screen.dart';
import 'templates_screen.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
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
    }
  }

  static const _destinations = [
    InstantRailItem(icon: Icons.checklist_rounded, label: 'Actions'),
    InstantRailItem(icon: Icons.insights, label: 'Growth directions'),
    InstantRailItem(icon: Icons.dashboard_customize, label: 'Templates'),
    InstantRailItem(
      icon: Icons.account_balance_wallet_outlined,
      label: 'Budget',
    ),
  ];

  /// Bottom-navigation labels on a phone (the rail's two-line ones are long).
  static const _phoneLabels = ['Actions', 'Growth', 'Templates', 'Budget'];

  static const _titles = [
    null, // Actions: the active sub-view's name
    'Growth directions',
    'Templates',
    'Budget',
  ];

  /// Index of the first section that is its own Scaffold (with its own FAB).
  static const _firstOwnScaffold = 1;

  Widget _viewFor(int i) => switch (i) {
    0 => ActionsSection(
      sub: _actionsSub,
      onChanged: (s) => setState(() => _actionsSub = s),
    ),
    1 => const GrowthDirectionsScreen(),
    2 => const TemplatesScreen(),
    _ => const BudgetScreen(),
  };

  @override
  Widget build(BuildContext context) {
    if (usePhoneLayout(context)) return _buildPhone(context);
    return Column(
      children: [
        _buildMenuBar(context),
        Expanded(child: _buildScaffold(context)),
      ],
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
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _titles[_index] ?? _actionsSub.title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 22),
        ),
        actions: [
          const SyncStatusButton(),
          PopupMenuButton<String>(
            key: const ValueKey('phone-menu'),
            onSelected: (_) => ref.read(themeModeProvider.notifier).toggle(),
            itemBuilder: (_) => [
              CheckedPopupMenuItem(
                value: 'dark',
                checked: isDark,
                child: const Text('Dark mode'),
              ),
            ],
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(child: _sections()),
          if (_index < _firstOwnScaffold)
            Positioned(
              right: 16,
              bottom: 16,
              child: FloatingActionButton(
                onPressed: () => ActionEditorDialog.show(context),
                tooltip: 'New action',
                child: const Icon(Icons.add),
              ),
            ),
        ],
      ),
      bottomNavigationBar: GlassSurface(
        radius: 0,
        shadow: false,
        child: NavigationBar(
          key: const ValueKey('phone-nav'),
          backgroundColor: Colors.transparent,
          elevation: 0,
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() {
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
            Positioned(
              right: 16,
              bottom: 16,
              child: FloatingActionButton(
                onPressed: () => ActionEditorDialog.show(context),
                tooltip: 'New action',
                child: const Icon(Icons.add),
              ),
            ),
        ],
      ),
    );
  }
}

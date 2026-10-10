import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show ServicesBinding;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../widgets/action_editor.dart';
import '../rail_collapsed.dart';
import '../theme_mode.dart';
import '../widgets/glass.dart';
import '../widgets/instant_rail.dart';
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

  /// Sections opened so far. A section is built the first time it is shown
  /// and then kept alive (hidden, not painted, no tickers, no focus), so
  /// switching back is instant instead of rebuilding the screen and
  /// re-running its queries every time.
  final _visited = <int>{0};

  /// Which view the Actions section (index 0) shows.
  ActionsSub _actionsSub = ActionsSub.current;

  static const _destinations = [
    InstantRailItem(icon: Icons.checklist_rounded, label: 'Actions'),
    InstantRailItem(icon: Icons.insights, label: 'Growth directions'),
    InstantRailItem(icon: Icons.dashboard_customize, label: 'Templates'),
    InstantRailItem(
      icon: Icons.account_balance_wallet_outlined,
      label: 'Budget',
    ),
  ];

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
    return Column(
      children: [
        _buildMenuBar(context),
        Expanded(child: _buildScaffold(context)),
      ],
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
      appBar: AppBar(title: Text(_titles[_index] ?? _actionsSub.title)),
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
                  Expanded(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        for (var i = 0; i < _titles.length; i++)
                          if (_visited.contains(i))
                            Visibility(
                              key: ValueKey('shell-view-$i'),
                              visible: i == _index,
                              maintainState: true,
                              child: ExcludeFocus(
                                excluding: i != _index,
                                child: _viewFor(i),
                              ),
                            ),
                      ],
                    ),
                  ),
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

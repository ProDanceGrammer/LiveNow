import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show ServicesBinding;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../views/all_actions_view.dart';
import '../views/calendar_view.dart';
import '../views/current_actions_view.dart';
import '../views/most_important_view.dart';
import '../views/operational_view.dart';
import '../views/todo_view.dart';
import '../widgets/action_editor.dart';
import '../theme_mode.dart';
import 'growth_directions_screen.dart';
import 'templates_screen.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;

  static const _destinations = [
    NavigationRailDestination(
      icon: Icon(Icons.view_column),
      label: Text('Current'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.bolt),
      label: Text('Operational'),
    ),
    NavigationRailDestination(icon: Icon(Icons.checklist), label: Text('TODO')),
    NavigationRailDestination(
      icon: Icon(Icons.star),
      label: Text('Most Important'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.calendar_view_week),
      label: Text('Calendar'),
    ),
    NavigationRailDestination(icon: Icon(Icons.list_alt), label: Text('All')),
    NavigationRailDestination(
      icon: Icon(Icons.insights),
      label: Text('Growth directions'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.dashboard_customize),
      label: Text('Templates'),
    ),
  ];

  static const _titles = [
    'Current Actions',
    'Operational',
    'TODO',
    'Most Important to Schedule',
    'Calendar',
    'All Actions',
    'Growth directions',
    'Templates',
  ];

  static const _views = [
    CurrentActionsView(),
    OperationalView(),
    TodoView(),
    MostImportantView(),
    CalendarView(),
    AllActionsView(),
    GrowthDirectionsScreen(),
    TemplatesScreen(),
  ];

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
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainer,
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
    );
  }

  Widget _buildScaffold(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_titles[_index])),
      body: LayoutBuilder(
        builder: (context, box) => Row(
          children: [
            // Scrollable so the rail never overflows if there isn't enough
            // vertical space for every destination (e.g. a short window).
            SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: box.maxHeight),
                child: IntrinsicHeight(
                  child: NavigationRail(
                    selectedIndex: _index,
                    onDestinationSelected: (i) => setState(() => _index = i),
                    labelType: NavigationRailLabelType.all,
                    destinations: _destinations,
                  ),
                ),
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: _views[_index]),
          ],
        ),
      ),
      // Metrics and Templates (last two indices) are their own Scaffolds
      // with their own FAB for adding a metric/template; only the six action
      // views (including Current and All) share this one.
      floatingActionButton: _index < 6
          ? FloatingActionButton(
              onPressed: () => ActionEditorDialog.show(context),
              tooltip: 'New action',
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}

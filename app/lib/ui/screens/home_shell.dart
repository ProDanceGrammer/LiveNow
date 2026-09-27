import 'package:flutter/material.dart';

import '../views/calendar_week_view.dart';
import '../views/habits_view.dart';
import '../views/most_important_view.dart';
import '../views/operational_view.dart';
import '../views/todo_view.dart';
import '../widgets/action_editor.dart';
import 'metrics_screen.dart';
import 'templates_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _destinations = [
    NavigationRailDestination(
      icon: Icon(Icons.bolt),
      label: Text('Operational'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.checklist),
      label: Text('TODO'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.star),
      label: Text('Most Important'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.calendar_view_week),
      label: Text('Calendar'),
    ),
    NavigationRailDestination(icon: Icon(Icons.repeat), label: Text('Habits')),
    NavigationRailDestination(
      icon: Icon(Icons.insights),
      label: Text('Metrics'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.dashboard_customize),
      label: Text('Templates'),
    ),
  ];

  static const _titles = [
    'Operational',
    'TODO',
    'Most Important to Schedule',
    'Calendar',
    'Habits',
    'Metrics',
    'Templates',
  ];

  static const _views = [
    OperationalView(),
    TodoView(),
    MostImportantView(),
    CalendarWeekView(),
    HabitsView(),
    MetricsScreen(),
    TemplatesScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_titles[_index])),
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            labelType: NavigationRailLabelType.all,
            destinations: _destinations,
          ),
          const VerticalDivider(width: 1),
          Expanded(child: _views[_index]),
        ],
      ),
      // Metrics and Templates (index 5, 6) are their own Scaffolds with
      // their own FAB for adding a metric/template; only the five action
      // views share this one.
      floatingActionButton: _index < 5
          ? FloatingActionButton(
              onPressed: () => ActionEditorDialog.show(context),
              tooltip: 'New action',
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}

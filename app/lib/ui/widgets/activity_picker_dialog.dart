import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/database.dart' show ActionTemplate, CountableActivity;
import '../dialog_stack.dart';

/// What the user chose in the [ActivityPickerDialog].
sealed class ActivityPick {
  const ActivityPick();
}

class ActivityPickNone extends ActivityPick {
  const ActivityPickNone();
}

class ActivityPickExisting extends ActivityPick {
  final String id;
  const ActivityPickExisting(this.id);
}

class ActivityPickTemplate extends ActivityPick {
  final String name;
  const ActivityPickTemplate(this.name);
}

class ActivityPickNew extends ActivityPick {
  const ActivityPickNew();
}

/// Searchable "Countable activity" chooser. 'None' is pinned on top and
/// 'New activity…' at the bottom whatever the filter; in between come the
/// activities, then templates without a same-name activity ('(template)').
class ActivityPickerDialog extends StatefulWidget {
  final List<CountableActivity> activities;
  final List<ActionTemplate> templates;

  const ActivityPickerDialog({
    super.key,
    required this.activities,
    required this.templates,
  });

  static Future<ActivityPick?> show(
    BuildContext context, {
    required List<CountableActivity> activities,
    required List<ActionTemplate> templates,
  }) {
    return showStackedDialog<ActivityPick>(
      context: context,
      builder: (_) =>
          ActivityPickerDialog(activities: activities, templates: templates),
    );
  }

  @override
  State<ActivityPickerDialog> createState() => _ActivityPickerDialogState();
}

class _ActivityPickerDialogState extends State<ActivityPickerDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final known = {
      for (final a in widget.activities) a.name.trim().toLowerCase(),
    };
    final seen = <String>{};
    final templateNames = <String>[
      for (final t in widget.templates)
        if (!known.contains(t.name.trim().toLowerCase()) &&
            seen.add(t.name.trim().toLowerCase()))
          t.name.trim(),
    ];
    bool match(String n) => n.toLowerCase().contains(_query);
    final rows = <Widget>[
      for (final a in widget.activities)
        if (match(a.name))
          ListTile(
            title: Text(a.name),
            onTap: () => Navigator.of(context).pop(ActivityPickExisting(a.id)),
          ),
      for (final n in templateNames)
        if (match(n))
          ListTile(
            title: Text('$n (template)'),
            onTap: () => Navigator.of(context).pop(ActivityPickTemplate(n)),
          ),
    ];

    return AlertDialog(
      title: const Text('Countable activity'),
      content: SizedBox(
        width: math.min(640.0, MediaQuery.sizeOf(context).width - 80),
        height: 400,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Search'),
              onChanged: (v) => setState(() => _query = v.toLowerCase()),
            ),
            ListTile(
              key: const ValueKey('activityNone'),
              title: const Text('None'),
              onTap: () => Navigator.of(context).pop(const ActivityPickNone()),
            ),
            Expanded(child: ListView(children: rows)),
            ListTile(
              key: const ValueKey('activityNew'),
              title: const Text('New activity…'),
              onTap: () => Navigator.of(context).pop(const ActivityPickNew()),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

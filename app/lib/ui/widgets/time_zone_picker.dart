import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../core/zone_info.dart';
import '../dialog_stack.dart';
import 'direction_badge.dart' show emojiLabelStyle;

/// Every real region zone ("Europe/Kyiv"), not the legacy aliases (US/Eastern,
/// Etc/GMT+3 ...), plus UTC. Sorted by name.
List<String> selectableTimeZones() {
  const regions = {
    'Africa', 'America', 'Antarctica', 'Arctic', 'Asia', 'Atlantic',
    'Australia', 'Europe', 'Indian', 'Pacific',
  };
  return [
    'UTC',
    for (final name in tz.timeZoneDatabase.locations.keys)
      if (regions.contains(name.split('/').first) && name.contains('/')) name,
  ]..sort();
}

/// A searchable list of every timezone, each with its flag, city and current
/// UTC offset. Returns the IANA name, or null when cancelled.
///
/// [defaultOption] (e.g. "Use my timezone") adds a button that returns an EMPTY
/// string: the caller's "no zone of its own".
Future<String?> pickTimeZone(
  BuildContext context, {
  String? current,
  String title = 'Choose a timezone',
  String? defaultOption,
}) => showStackedDialog<String>(
  context: context,
  builder: (_) => _TimeZoneDialog(
    current: current,
    title: title,
    defaultOption: defaultOption,
  ),
);

class _TimeZoneDialog extends StatefulWidget {
  const _TimeZoneDialog({
    required this.current,
    required this.title,
    this.defaultOption,
  });

  final String? current;
  final String title;
  final String? defaultOption;

  @override
  State<_TimeZoneDialog> createState() => _TimeZoneDialogState();
}

class _TimeZoneDialogState extends State<_TimeZoneDialog> {
  final _all = selectableTimeZones();
  final _now = DateTime.now().toUtc();
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase().replaceAll(' ', '_');
    final shown = [
      for (final z in _all)
        if (q.isEmpty || z.toLowerCase().contains(q)) z,
    ];
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 460,
        height: 460,
        child: Column(
          children: [
            TextField(
              key: const ValueKey('zone-search'),
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Search a city or region',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            Expanded(
              child: shown.isEmpty
                  ? const Center(child: Text('No matching timezone.'))
                  : ListView.builder(
                      itemCount: shown.length,
                      itemBuilder: (context, i) {
                        final z = shown[i];
                        return ListTile(
                          key: ValueKey('zone-$z'),
                          dense: true,
                          selected: z == widget.current,
                          title: Text(
                            zoneDefaultLabel(z),
                            style: emojiLabelStyle,
                          ),
                          subtitle: Text(
                            '$z · ${formatZoneOffset(zoneOffset(z, _now))}',
                          ),
                          onTap: () => Navigator.of(context).pop(z),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        if (widget.defaultOption != null)
          TextButton(
            key: const ValueKey('zone-default'),
            onPressed: () => Navigator.of(context).pop(''),
            child: Text(widget.defaultOption!),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

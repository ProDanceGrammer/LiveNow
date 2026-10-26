import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings.dart';
import '../../core/zone_info.dart';
import '../../data/database.dart' show CalendarZone;
import '../../data/time_zone_setup.dart';
import '../../domain/calendar_zone_service.dart';
import '../calendar_zone_providers.dart';
import '../theme/glass_theme.dart';
import '../undo.dart';
import 'app_toast.dart';
import 'direction_badge.dart' show emojiLabelStyle;
import 'emoji_picker_button.dart';
import 'time_zone_picker.dart';

/// Settings: the timezone the app lives in (the computer's, or one you choose)
/// and up to three extra timezones shown as hour columns in the calendar.
class TimeZoneSettings extends ConsumerStatefulWidget {
  const TimeZoneSettings({super.key});

  @override
  ConsumerState<TimeZoneSettings> createState() => _TimeZoneSettingsState();
}

class _TimeZoneSettingsState extends ConsumerState<TimeZoneSettings> {
  bool? _chosen; // null until the file was read
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    readTimeZoneOverride().then((o) {
      if (mounted) setState(() => _chosen = o != null);
    });
  }

  Future<void> _change() async {
    final overlay = rootOverlayOf(context);
    final zone = await pickTimeZone(
      context,
      current: AppSettings.timeZoneName,
      title: 'Your timezone',
    );
    if (zone == null) return;
    await writeTimeZoneOverride(zone);
    if (!mounted) return;
    setState(() {
      _chosen = true;
      _changed = zone != AppSettings.timeZoneName;
    });
    if (_changed) showInfoToast(overlay, 'Restart LiveNow to use $zone.');
  }

  Future<void> _follow() async {
    final overlay = rootOverlayOf(context);
    await writeTimeZoneOverride(null);
    final device = await detectDeviceTimeZone();
    if (!mounted) return;
    setState(() {
      _chosen = false;
      _changed = device != null && device != AppSettings.timeZoneName;
    });
    if (_changed) showInfoToast(overlay, 'Restart LiveNow to use $device.');
  }

  Future<void> _add() async {
    final overlay = rootOverlayOf(context);
    final service = ref.read(calendarZoneServiceProvider);
    final zone = await pickTimeZone(context, title: 'Add a calendar timezone');
    if (zone == null) return;
    try {
      await service.add(zone);
    } on CalendarZoneLimitException {
      showInfoToast(overlay, 'At most $kMaxCalendarZones extra timezones.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = context.glass;
    final zones = ref.watch(calendarZonesProvider).value ?? const [];
    final current = AppSettings.timeZoneName;
    final now = DateTime.now().toUtc();
    final why = _chosen == null
        ? current
        : _chosen!
        ? '$current - chosen by you. Days, midnight and reminders use it.'
        : "$current - this computer's timezone. Days, midnight and "
              'reminders use it.';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          key: const ValueKey('settings-timezone'),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          title: Text(
            '${zoneDefaultLabel(current)}  ·  '
            '${formatZoneOffset(zoneOffset(current, now))}',
            style: emojiLabelStyle,
          ),
          subtitle: Text(why),
          trailing: Wrap(
            spacing: 8,
            children: [
              TextButton(
                key: const ValueKey('settings-timezone-change'),
                onPressed: _change,
                child: const Text('Change…'),
              ),
              if (_chosen == true)
                TextButton(
                  key: const ValueKey('settings-timezone-follow'),
                  onPressed: _follow,
                  child: const Text('Follow this computer'),
                ),
            ],
          ),
        ),
        if (_changed)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Restart LiveNow to apply the new timezone.',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Extra timezones in the calendar',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              TextButton.icon(
                key: const ValueKey('settings-zone-add'),
                onPressed: zones.length >= kMaxCalendarZones ? null : _add,
                icon: const Icon(Icons.add),
                label: const Text('Add'),
              ),
            ],
          ),
        ),
        if (zones.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              "Their hours appear left of the calendar's own, so you can read "
              'the time somewhere else at a glance (up to $kMaxCalendarZones).',
              style: TextStyle(color: g.textSecondary),
            ),
          ),
        for (final z in zones)
          _ZoneRow(key: ValueKey('zone-row-${z.id}'), zone: z),
      ],
    );
  }
}

class _ZoneRow extends ConsumerStatefulWidget {
  const _ZoneRow({super.key, required this.zone});

  final CalendarZone zone;

  @override
  ConsumerState<_ZoneRow> createState() => _ZoneRowState();
}

class _ZoneRowState extends ConsumerState<_ZoneRow> {
  late final _label = TextEditingController(text: widget.zone.label);

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  void _save() => ref
      .read(calendarZoneServiceProvider)
      .rename(widget.zone.id, _label.text)
      .then((_) {
        // A blank name came back as the default (flag + city).
        if (mounted && _label.text.trim().isEmpty) {
          _label.text = zoneDefaultLabel(widget.zone.tz);
        }
      });

  Future<void> _delete() async {
    final overlay = rootOverlayOf(context);
    final history = ref.read(undoHistoryProvider.notifier);
    final service = ref.read(calendarZoneServiceProvider);
    final row = await service.remove(widget.zone.id);
    if (row == null) return;
    offerUndo(
      overlay,
      history,
      'Removed timezone "${row.label}"',
      () => service.restore(row),
    );
  }

  @override
  Widget build(BuildContext context) {
    final g = context.glass;
    final z = widget.zone;
    final offset = formatZoneOffset(zoneOffset(z.tz, DateTime.now().toUtc()));
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              key: ValueKey('zone-label-${z.id}'),
              controller: _label,
              style: emojiLabelStyle,
              decoration: InputDecoration(
                isDense: true,
                labelText: 'Name in the calendar',
                helperText: '${z.tz} · $offset',
                helperStyle: TextStyle(color: g.textSecondary),
                suffixIcon: EmojiPickerButton(
                  controller: _label,
                  onChanged: _save,
                ),
              ),
              onSubmitted: (_) => _save(),
              onTapOutside: (_) => _save(),
            ),
          ),
          IconButton(
            key: ValueKey('zone-delete-${z.id}'),
            tooltip: 'Remove this timezone',
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: _delete,
          ),
        ],
      ),
    );
  }
}

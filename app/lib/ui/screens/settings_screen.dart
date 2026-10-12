import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/reminders/local_notifications_sink.dart';
import '../data_imports.dart';
import '../reminders.dart';
import '../work_hours.dart';
import '../../domain/work_hours.dart';
import '../theme_mode.dart';
import '../theme/glass_theme.dart';
import '../widgets/param_icons.dart';
import '../widgets/section_block.dart';
import '../widgets/sync_settings_dialog.dart' show SyncSettingsBody;

/// The Settings page (phone and desktop): sync, light/dark mode and every
/// import / export in one place.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final dark = ref.watch(themeModeProvider) == ThemeMode.dark;
    final hours = ref.watch(workHoursProvider);

    Widget title(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 0),
      child: Text(text, style: theme.textTheme.titleMedium),
    );

    Widget tile(
      String key,
      IconData? icon,
      String label,
      Future<void> Function(BuildContext, WidgetRef) run, {
      String? subtitle,
      Widget? leading,
    }) => ListTile(
      key: ValueKey(key),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: leading ?? Icon(icon),
      title: Text(label),
      subtitle: subtitle == null ? null : Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => run(context, ref),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            children: [
              title('Sync'),
              const _Panel(
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: SyncSettingsBody(),
                ),
              ),
              title('Appearance'),
              SectionBlock(
                padding: const EdgeInsets.all(12),
                child: SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<ThemeMode>(
                    key: const ValueKey('settings-theme'),
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                        value: ThemeMode.light,
                        icon: Icon(Icons.light_mode_outlined),
                        label: Text('Light'),
                      ),
                      ButtonSegment(
                        value: ThemeMode.dark,
                        icon: Icon(Icons.dark_mode_outlined),
                        label: Text('Dark'),
                      ),
                    ],
                    selected: {dark ? ThemeMode.dark : ThemeMode.light},
                    onSelectionChanged: (s) =>
                        ref.read(themeModeProvider.notifier).setMode(s.first),
                  ),
                ),
              ),
              if (LocalNotificationsSink.supported) ...[
                title('Notifications'),
                _Panel(
                  child: SwitchListTile(
                    key: const ValueKey('settings-reminders'),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    title: const Text(
                      'Remind me when an action starts or ends',
                    ),
                    subtitle: Text(
                      defaultTargetPlatform == TargetPlatform.iOS
                          ? 'Delivered by iOS, also while LiveNow is closed'
                          : 'Only while LiveNow is open',
                    ),
                    value: ref.watch(remindersEnabledProvider),
                    onChanged: (v) =>
                        ref.read(remindersEnabledProvider.notifier).set(v),
                  ),
                ),
              ],
              title('Working hours'),
              _Panel(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    children: [
                      _TimeTile(
                        tileKey: 'settings-work-start',
                        icon: Icons.wb_sunny_outlined,
                        label: 'Work starts',
                        minutes: hours.workStart,
                        onPick: (m) => _setHours(
                          context,
                          ref,
                          hours.copyWith(workStart: m),
                        ),
                      ),
                      _TimeTile(
                        tileKey: 'settings-work-end',
                        icon: Icons.nightlight_outlined,
                        label: 'Work ends',
                        subtitle: '"After work" postpones go here',
                        minutes: hours.workEnd,
                        onPick: (m) =>
                            _setHours(context, ref, hours.copyWith(workEnd: m)),
                      ),
                      _TimeTile(
                        tileKey: 'settings-morning',
                        icon: Icons.wb_twilight_rounded,
                        label: 'Morning',
                        subtitle:
                            'The time "morning" postpones go to (it may differ '
                            'from the start of work)',
                        minutes: hours.morning,
                        onPick: (m) =>
                            _setHours(context, ref, hours.copyWith(morning: m)),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Working days',
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Next working morning and "What is done?" skip '
                              'the other days',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                for (var d = 1; d <= 7; d++)
                                  FilterChip(
                                    key: ValueKey('settings-workday-$d'),
                                    label: Text(
                                      const [
                                        'Mon',
                                        'Tue',
                                        'Wed',
                                        'Thu',
                                        'Fri',
                                        'Sat',
                                        'Sun',
                                      ][d - 1],
                                    ),
                                    selected: hours.workingWeekdays.contains(d),
                                    onSelected: (on) => _setHours(
                                      context,
                                      ref,
                                      hours.copyWith(
                                        workingWeekdays: {
                                          ...hours.workingWeekdays,
                                        }..addAll(on ? {d} : {})
                                          ..removeWhere((x) => !on && x == d),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              title('Import'),
              _Panel(
                child: Column(
                  children: [
                    tile(
                      'settings-import-actions',
                      Icons.checklist_rounded,
                      'Actions (CSV)',
                      importActionsCsv,
                      subtitle: 'Notion actions export',
                    ),
                    tile(
                      'settings-import-templates',
                      Icons.dashboard_customize,
                      'Templates (CSV)',
                      importTemplatesCsv,
                      subtitle: 'Same Notion export, as templates',
                    ),
                    tile(
                      'settings-import-growth',
                      Icons.insights,
                      'Growth directions (CSV)',
                      importGrowthCsv,
                      subtitle: 'Replaces all growth directions',
                    ),
                    tile(
                      'settings-import-growth-icons',
                      Icons.emoji_emotions_outlined,
                      'Growth direction icons',
                      importGrowthIcons,
                      subtitle: 'Saved Notion page or name + emoji list',
                    ),
                    tile(
                      'settings-import-budget',
                      Icons.account_balance_wallet_outlined,
                      'Budget (CSV or backup)',
                      importBudgetData,
                      subtitle: 'Replaces the budget data',
                    ),
                    tile(
                      'settings-import-budget-icons',
                      null,
                      'Budget category icons (CSV)',
                      importBudgetIcons,
                      leading: const ParamIcon(Param.categories, size: 24),
                    ),
                  ],
                ),
              ),
              title('Export'),
              _Panel(
                child: Column(
                  children: [
                    tile(
                      'settings-export-budget-json',
                      Icons.save_alt,
                      'Budget backup (JSON)',
                      exportBudgetJson,
                    ),
                    tile(
                      'settings-export-budget-csv',
                      Icons.table_chart_outlined,
                      'Budget CSV files',
                      exportBudgetCsv,
                    ),
                  ],
                ),
              ),
              title('About'),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
                child: Text(
                  'Flag emoji on Windows are drawn with Twemoji '
                  '(© Twitter, Inc. and other contributors, CC-BY 4.0).',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A rounded glass-tinted panel that is itself a Material, so the ListTiles
/// inside paint their ink on it (a decorated Container around them would hide
/// it).
class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final g = context.glass;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Material(
        color: g.fill.withValues(alpha: g.fill.a * 0.5),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(GlassTheme.radiusControl),
          side: BorderSide(color: g.border),
        ),
        child: child,
      ),
    );
  }
}

/// Applies new working hours, or says why they are refused.
void _setHours(BuildContext context, WidgetRef ref, WorkHours hours) {
  final problem = ref.read(workHoursProvider.notifier).set(hours);
  if (problem != null) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(problem)));
  }
}

/// A settings row showing a time of day; a tap opens the time picker.
class _TimeTile extends StatelessWidget {
  const _TimeTile({
    required this.tileKey,
    required this.icon,
    required this.label,
    required this.minutes,
    required this.onPick,
    this.subtitle,
  });

  final String tileKey;
  final IconData icon;
  final String label;
  final String? subtitle;
  final int minutes;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) => ListTile(
    key: ValueKey(tileKey),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
    leading: Icon(icon),
    title: Text(label),
    subtitle: subtitle == null ? null : Text(subtitle!),
    trailing: Text(
      WorkHours.format(minutes),
      style: Theme.of(context).textTheme.titleMedium,
    ),
    onTap: () async {
      final picked = await showTimePicker(
        context: context,
        initialTime: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        ),
      );
      if (picked != null) onPick(picked.hour * 60 + picked.minute);
    },
  );
}

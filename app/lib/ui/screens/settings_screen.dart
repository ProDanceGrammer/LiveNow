import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/reminders/local_notifications_sink.dart';
import '../data_imports.dart';
import '../reminders.dart';
import '../theme_mode.dart';
import '../theme/glass_theme.dart';
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

    Widget title(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 0),
      child: Text(text, style: theme.textTheme.titleMedium),
    );

    Widget tile(
      String key,
      IconData icon,
      String label,
      Future<void> Function(BuildContext, WidgetRef) run, {
      String? subtitle,
    }) => ListTile(
      key: ValueKey(key),
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
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
                    contentPadding: EdgeInsets.zero,
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
                      Icons.category_outlined,
                      'Budget category icons (CSV)',
                      importBudgetIcons,
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

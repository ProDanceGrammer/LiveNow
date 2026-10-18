import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../sync_providers.dart';
import 'sync_settings_dialog.dart';

/// The app-bar button that opens the sync settings. On a phone it shows the
/// state (syncing / offline / error); a badge counts items that changed on both
/// devices and were not reviewed yet.
class SyncStatusButton extends ConsumerWidget {
  const SyncStatusButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(syncRoleProvider);
    final status = ref.watch(syncClientProvider);
    final host = ref.watch(syncHostControllerProvider);
    final unseen = ref.watch(syncUnseenConflictsProvider).value ?? 0;
    final scheme = Theme.of(context).colorScheme;

    final (icon, tip, color) = role == SyncRole.host
        ? (
            host.running ? Icons.sync : Icons.sync_disabled,
            host.running ? 'Sync: phones can connect' : 'Sync',
            null as Color?,
          )
        : switch (status.phase) {
            SyncPhase.unpaired => (
              Icons.sync_disabled,
              'Pair with your PC',
              null,
            ),
            SyncPhase.syncing => (Icons.sync, 'Syncing…', scheme.primary),
            SyncPhase.offline => (
              Icons.cloud_off,
              'PC (hub) not reachable',
              scheme.outline,
            ),
            SyncPhase.error => (
              Icons.sync_problem,
              status.message ?? 'Sync failed',
              scheme.error,
            ),
            SyncPhase.idle => (
              Icons.sync,
              status.lastSync == null
                  ? 'Sync'
                  : 'Synced ${formatAgo(status.lastSync!)}',
              null,
            ),
          };

    Widget button = IconButton(
      key: const ValueKey('sync-status'),
      tooltip: tip,
      icon: Icon(icon, color: color),
      onPressed: () => SyncSettingsDialog.show(context),
    );
    if (unseen > 0) {
      button = Badge.count(count: unseen, child: button);
    }
    return button;
  }
}

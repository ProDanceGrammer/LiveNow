import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/sync/sync_models.dart';
import '../dialog_stack.dart';
import '../sync_providers.dart';
import 'app_toast.dart';

const _kinds = {
  'actions': 'Action',
  'metrics': 'Growth direction',
  'metric_dependencies': 'Direction link',
  'action_metrics': 'Action link',
  'action_dependencies': 'Action chain',
  'action_occurrences': 'Time record',
  'action_templates': 'Template',
  'countable_activities': 'Activity',
  'budget_accounts': 'Account',
  'budget_categories': 'Budget category',
  'budget_transactions': 'Transaction',
  'budget_settings': 'Budget setting',
};

final _deviceIdProvider = FutureProvider<String>(
  (ref) => ref.watch(syncStoreProvider).deviceId(),
);

/// Edits that lost a merge: the same item was changed on both devices, the
/// newest change was kept and the other one is listed here so it can be put
/// back (which makes it a new edit that then wins on every device).
class SyncConflictsDialog extends ConsumerWidget {
  const SyncConflictsDialog({super.key});

  static Future<void> show(BuildContext context) => showStackedDialog<void>(
    context: context,
    builder: (_) => const SyncConflictsDialog(),
  ).then((_) {});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conflicts = ref.watch(syncConflictsProvider).value ?? const [];
    final me = ref.watch(_deviceIdProvider).value;
    final store = ref.read(syncStoreProvider);
    final revision = ref.read(syncRevisionProvider.notifier);
    final width = MediaQuery.sizeOf(context).width;

    Future<void> restore(SyncConflict c) async {
      final overlay = rootOverlayOf(context);
      try {
        final ok = await store.restoreConflict(c.id);
        showInfoToast(
          overlay,
          ok ? 'Restored the other version' : 'Nothing to restore',
        );
      } on Object {
        showInfoToast(
          overlay,
          'Could not restore it: something it refers to no longer exists',
        );
      }
      revision.bump();
    }

    return AlertDialog(
      title: const Text('Changed on both devices'),
      content: SizedBox(
        width: width < 560 ? width - 80 : 480,
        child: conflicts.isEmpty
            ? const Text('Nothing to review.')
            : ListView(
                shrinkWrap: true,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text(
                      'The newest change was kept. You can bring the other '
                      'version back.',
                    ),
                  ),
                  for (final c in conflicts)
                    ListTile(
                      key: ValueKey('conflict-${c.id}'),
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        '${_kinds[c.table] ?? c.table}'
                        '${c.label == null || c.label!.isEmpty ? '' : ' "${c.label}"'}',
                      ),
                      subtitle: Text(
                        c.loserOrigin == me
                            ? 'Your change was replaced by one from the other '
                                  'device'
                            : 'A change from the other device was replaced by '
                                  'yours',
                      ),
                      trailing: c.loserData == null
                          ? null
                          : TextButton(
                              key: ValueKey('conflict-restore-${c.id}'),
                              onPressed: () => restore(c),
                              child: const Text('Restore'),
                            ),
                    ),
                ],
              ),
      ),
      actions: [
        if (conflicts.isNotEmpty)
          TextButton(
            key: const ValueKey('conflicts-dismiss'),
            onPressed: () async {
              await store.dismissConflicts();
              revision.bump();
            },
            child: const Text('Dismiss all'),
          ),
        TextButton(
          onPressed: () async {
            await store.markConflictsSeen();
            revision.bump();
            if (context.mounted) Navigator.of(context).pop();
          },
          child: const Text('Close'),
        ),
      ],
    );
  }
}

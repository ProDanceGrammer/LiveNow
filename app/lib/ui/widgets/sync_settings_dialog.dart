import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../data/sync/http_transport.dart';
import '../../domain/sync/sync_crypto.dart';
import '../../domain/sync/sync_protocol.dart';
import '../dialog_stack.dart';
import '../sync_providers.dart';
import 'app_toast.dart';
import 'sync_conflicts_dialog.dart';
import 'sync_scan_dialog.dart';

/// "5 min ago" style text for the last sync.
String formatAgo(DateTime then, {DateTime? now}) {
  final d = (now ?? DateTime.now()).difference(then);
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  return '${d.inDays} d ago';
}

final _hostEnabledProvider = FutureProvider.autoDispose<bool>((ref) {
  ref.watch(syncRevisionProvider);
  return ref.watch(syncHostControllerProvider.notifier).enabled();
});

/// Sync settings. On the PC: let phones sync, pair a new phone (QR code),
/// paired phones. On a phone: pair with the PC, status, Sync now.
class SyncSettingsDialog extends ConsumerWidget {
  const SyncSettingsDialog({super.key});

  static Future<void> show(BuildContext context) => showStackedDialog<void>(
    context: context,
    builder: (_) => const SyncSettingsDialog(),
  ).then((_) {});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final host = ref.watch(syncRoleProvider) == SyncRole.host;
    final width = MediaQuery.sizeOf(context).width;
    return AlertDialog(
      title: const Text('Sync'),
      content: SizedBox(
        width: width < 560 ? width - 80 : 480,
        child: SingleChildScrollView(
          child: host ? const _HostPanel() : const _ClientPanel(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

/// The sync controls themselves (PC or phone, by role), without a dialog
/// around them: the Settings page embeds this.
class SyncSettingsBody extends ConsumerWidget {
  const SyncSettingsBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final host = ref.watch(syncRoleProvider) == SyncRole.host;
    return host ? const _HostPanel() : const _ClientPanel();
  }
}

class _ConflictsRow extends ConsumerWidget {
  const _ConflictsRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = ref.watch(syncConflictsProvider).value?.length ?? 0;
    if (n == 0) return const SizedBox.shrink();
    return ListTile(
      key: const ValueKey('sync-review-conflicts'),
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.merge_type),
      title: Text('$n item${n == 1 ? '' : 's'} changed on both devices'),
      subtitle: const Text('The newest change was kept'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => SyncConflictsDialog.show(context),
    );
  }
}

// ---- PC -------------------------------------------------------------------------

class _HostPanel extends ConsumerWidget {
  const _HostPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final host = ref.watch(syncHostControllerProvider);
    final controller = ref.read(syncHostControllerProvider.notifier);
    final peers = ref.watch(syncPeerListProvider).value ?? const [];
    final enabled = ref.watch(_hostEnabledProvider).value ?? true;

    ref.listen(syncHostControllerProvider.select((s) => s.lastPaired), (
      prev,
      next,
    ) {
      if (next != null && next != prev) {
        showInfoToast(rootOverlayOf(context), 'Paired with ${next.name}');
      }
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SwitchListTile(
          key: const ValueKey('sync-enabled-switch'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Let paired phones sync'),
          subtitle: const Text('Only while LiveNow is open on this PC'),
          value: enabled,
          onChanged: controller.setEnabled,
        ),
        Text(
          host.error ??
              (host.running
                  ? 'Listening for phones on port ${host.port}'
                  : 'Not listening'),
          key: const ValueKey('sync-server-status'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        Text('Paired phones', style: Theme.of(context).textTheme.titleSmall),
        if (peers.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('No phone is paired yet.'),
          ),
        for (final p in peers)
          ListTile(
            key: ValueKey('sync-peer-${p.deviceId}'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.phone_iphone),
            title: Text(p.name),
            trailing: IconButton(
              key: ValueKey('sync-remove-${p.deviceId}'),
              tooltip: 'Remove this phone',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                final ok = await _confirm(
                  context,
                  title: 'Remove ${p.name}?',
                  text:
                      'It can no longer sync with this PC until it is paired '
                      'again. Its data stays on the phone.',
                  action: 'Remove',
                );
                if (ok) await controller.removePeer(p.deviceId);
              },
            ),
          ),
        const SizedBox(height: 8),
        if (host.pairing != null)
          _PairingCode(code: host.pairing!, expires: host.pairingExpires!)
        else
          FilledButton.tonalIcon(
            key: const ValueKey('sync-pair-phone'),
            icon: const Icon(Icons.qr_code_2),
            label: const Text('Pair a new phone'),
            onPressed: controller.startPairing,
          ),
        const _ConflictsRow(),
      ],
    );
  }
}

class _PairingCode extends ConsumerStatefulWidget {
  const _PairingCode({required this.code, required this.expires});
  final PairingUri code;
  final DateTime expires;

  @override
  ConsumerState<_PairingCode> createState() => _PairingCodeState();
}

class _PairingCodeState extends ConsumerState<_PairingCode> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(
      const Duration(seconds: 1),
      (_) => mounted ? setState(() {}) : null,
    );
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final left = widget.expires.difference(DateTime.now());
    final seconds = left.isNegative ? 0 : left.inSeconds;
    final text = widget.code.toString();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.all(8),
          child: QrImageView(
            key: const ValueKey('sync-qr'),
            data: text,
            size: 200,
            backgroundColor: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'On your phone open LiveNow, tap the sync button and scan this code. '
          'Both devices must be on the same Wi-Fi.',
          style: Theme.of(context).textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        SelectableText(
          text,
          key: const ValueKey('sync-code-text'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton.icon(
              key: const ValueKey('sync-copy-code'),
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('Copy code'),
              onPressed: () => Clipboard.setData(ClipboardData(text: text)),
            ),
            Text(
              'valid for ${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}',
              key: const ValueKey('sync-countdown'),
            ),
          ],
        ),
        TextButton(
          key: const ValueKey('sync-pair-cancel'),
          onPressed: ref
              .read(syncHostControllerProvider.notifier)
              .cancelPairing,
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

// ---- phone ----------------------------------------------------------------------

class _ClientPanel extends ConsumerStatefulWidget {
  const _ClientPanel();

  @override
  ConsumerState<_ClientPanel> createState() => _ClientPanelState();
}

class _ClientPanelState extends ConsumerState<_ClientPanel> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  bool get _canScan =>
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.android;

  Future<void> _scan() async {
    final text = await SyncScanDialog.show(context);
    if (text != null && mounted) {
      _code.text = text;
      await _pair();
    }
  }

  Future<void> _pair() async {
    final PairingUri code;
    try {
      code = PairingUri.parse(_code.text);
    } on FormatException {
      setState(() => _error = 'That is not a LiveNow pairing code.');
      return;
    }
    final counts = await ref.read(syncStoreProvider).rowCounts();
    if (!mounted) return;
    if (counts.values.any((n) => n > 0)) {
      final ok = await _confirm(
        context,
        title: 'Replace the data on this phone?',
        text:
            'The PC\'s data will replace everything on this phone '
            '(${counts['actions']} actions, ${counts['metrics']} growth '
            'directions, ${counts['budget_transactions']} transactions). A '
            'backup copy of the phone\'s data is kept for 30 days.',
        action: 'Replace',
      );
      if (!ok || !mounted) return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(syncClientProvider.notifier).pairAndReplace(code);
      _code.clear();
    } on SyncAuthException {
      _error =
          'The code was wrong or has expired. Show a new one on the PC. '
          'Also check that both clocks are right.';
    } on SyncUnreachable {
      _error =
          'Could not reach the PC. Is LiveNow open on it, and are both '
          'devices on the same Wi-Fi?';
    } on Object catch (e) {
      _error = '$e';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(syncClientProvider);
    final paired = status.phase != SyncPhase.unpaired;
    final theme = Theme.of(context);

    if (!paired) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Pair this phone with your PC to keep both in step. On the PC '
            'open Sync and choose "Pair a new phone".',
          ),
          const SizedBox(height: 12),
          if (_canScan)
            FilledButton.icon(
              key: const ValueKey('sync-scan'),
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Scan the code'),
              onPressed: _busy ? null : _scan,
            ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('sync-code-field'),
            controller: _code,
            decoration: const InputDecoration(
              labelText: 'Or paste the code',
              hintText: 'livenow://pair?...',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonal(
              key: const ValueKey('sync-pair-button'),
              onPressed: _busy ? null : _pair,
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Pair'),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _error!,
                key: const ValueKey('sync-error'),
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
        ],
      );
    }

    final line = switch (status.phase) {
      SyncPhase.syncing => 'Syncing…',
      SyncPhase.offline || SyncPhase.error => status.message ?? 'Failed',
      _ =>
        status.lastSync == null
            ? 'Not synced yet'
            : 'Last synced ${formatAgo(status.lastSync!)}',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.computer),
          title: Text(status.peerName ?? 'Your PC'),
          subtitle: Text(
            line,
            key: const ValueKey('sync-status-line'),
            style: status.phase == SyncPhase.error
                ? TextStyle(color: theme.colorScheme.error)
                : null,
          ),
        ),
        Row(
          children: [
            FilledButton.icon(
              key: const ValueKey('sync-now'),
              icon: const Icon(Icons.sync),
              label: const Text('Sync now'),
              onPressed: status.phase == SyncPhase.syncing
                  ? null
                  : () => ref.read(syncClientProvider.notifier).syncNow(),
            ),
            const Spacer(),
            TextButton(
              key: const ValueKey('sync-forget'),
              onPressed: () async {
                final ok = await _confirm(
                  context,
                  title: 'Forget this PC?',
                  text:
                      'This phone stops syncing. Its data stays as it is and '
                      'you can pair again later.',
                  action: 'Forget',
                );
                if (ok) await ref.read(syncClientProvider.notifier).forget();
              },
              child: const Text('Forget PC'),
            ),
          ],
        ),
        const _ConflictsRow(),
      ],
    );
  }
}

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String text,
  required String action,
}) async =>
    await showStackedDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(text),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('sync-confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;

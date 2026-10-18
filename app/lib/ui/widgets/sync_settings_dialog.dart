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
import 'sync_pair_approval_dialog.dart';
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
    final width = MediaQuery.sizeOf(context).width;
    return AlertDialog(
      title: const Text('Sync'),
      content: SizedBox(
        width: width < 560 ? width - 80 : 480,
        child: const SingleChildScrollView(child: _SyncPanel()),
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
  Widget build(BuildContext context, WidgetRef ref) => const _SyncPanel();
}

/// Which panel fits this device: a PC that serves phones itself, a desktop
/// connected to the always-on hub, or a phone.
class _SyncPanel extends ConsumerWidget {
  const _SyncPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(syncRoleProvider) == SyncRole.host) return const _HostPanel();
    return ref.watch(hubConnectedProvider)
        ? const _HubPanel()
        : const _ClientPanel();
  }
}

class _ConflictsRow extends ConsumerWidget {
  const _ConflictsRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n =
        (ref.watch(syncConflictsProvider).value?.length ?? 0) +
        (ref.watch(hubConflictsProvider).value?.length ?? 0);
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

    // A phone that knows the code waits here for the owner's yes or no.
    ref.listen(syncHostControllerProvider.select((s) => s.pendingPair), (
      prev,
      next,
    ) async {
      if (next == null || prev != null) return;
      final approved = await SyncPairApprovalDialog.show(context, next);
      controller.answerPair(approved);
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
        const Divider(height: 24),
        const _HubConnectTile(),
      ],
    );
  }
}

/// On a PC that serves phones itself: switch to the always-on hub (a LiveNow
/// background program on this PC that keeps the data and answers phones even
/// when this window is closed).
class _HubConnectTile extends ConsumerStatefulWidget {
  const _HubConnectTile();

  @override
  ConsumerState<_HubConnectTile> createState() => _HubConnectTileState();
}

class _HubConnectTileState extends ConsumerState<_HubConnectTile> {
  bool _busy = false;
  String? _error;

  /// Asks Windows to run the hub's scheduled task; the hub needs a moment to
  /// open its port and write its pairing text.
  Future<void> _startHub() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final started = await ref.read(hubStarterProvider)();
    if (mounted) {
      setState(() {
        _busy = false;
        _error = started
            ? 'The hub is starting. Wait a few seconds, then connect.'
            : 'The hub is not installed. Run claude_dev\\hub\\install_hub.ps1 '
                  'first.';
      });
    }
  }

  Future<void> _connect() async {
    final ok = await _confirm(
      context,
      title: 'Connect to the local hub?',
      text:
          'This PC will sync with the always-on hub like a phone does: all '
          'your data is sent to the hub and nothing is deleted here. Phones '
          'then pair with the hub instead of this window (their old pairings '
          'with this window are forgotten; their data stays).',
      action: 'Connect',
    );
    if (!ok || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(syncClientProvider.notifier).connectLocalHub();
    } on FormatException catch (e) {
      _error = e.message;
    } on SyncAuthException {
      _error = 'The hub refused this PC. Restart the hub and try again.';
    } on SyncUnreachable {
      _error = 'The hub did not answer. Is it running?';
    } on Object catch (e) {
      _error = '$e';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Always-on hub', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          'Keeps your data and syncs with your phone even when LiveNow is '
          'closed on this PC.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            FilledButton.tonalIcon(
              key: const ValueKey('sync-hub-connect'),
              icon: const Icon(Icons.dns_outlined),
              label: const Text('Connect to the local hub'),
              onPressed: _busy ? null : _connect,
            ),
            TextButton(
              key: const ValueKey('sync-hub-start'),
              onPressed: _busy ? null : _startHub,
              child: const Text('Start the hub'),
            ),
          ],
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _error!,
              key: const ValueKey('sync-hub-error'),
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
      ],
    );
  }
}

/// A desktop connected to the hub: status, Sync now, the phones paired with the
/// hub, and pairing a new phone (the hub has no window: the code and the
/// "Pair this phone?" question appear here).
class _HubPanel extends ConsumerStatefulWidget {
  const _HubPanel();

  @override
  ConsumerState<_HubPanel> createState() => _HubPanelState();
}

class _HubPanelState extends ConsumerState<_HubPanel> {
  PairingUri? _code;
  DateTime? _expires;
  Timer? _poll;
  bool _asking = false;
  String? _error;

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _startPairing() async {
    setState(() => _error = null);
    try {
      final r = await ref.read(hubAdminProvider).run((h) => h.startPairing());
      if (!mounted) return;
      setState(() {
        _code = r.code;
        _expires = DateTime.now().add(Duration(seconds: r.seconds));
      });
      _poll?.cancel();
      _poll = Timer.periodic(const Duration(seconds: 1), (_) => _check());
    } on Object catch (e) {
      if (mounted) setState(() => _error = 'Could not reach the hub ($e)');
    }
  }

  void _stopPairing() {
    _poll?.cancel();
    _poll = null;
    if (mounted) {
      setState(() {
        _code = null;
        _expires = null;
      });
    }
  }

  Future<void> _cancel() async {
    final hub = ref.read(hubAdminProvider);
    _stopPairing();
    try {
      await hub.run((h) => h.cancelPairing());
    } on Object {
      // The code lapses by itself.
    }
  }

  /// Every second while a code shows: has a phone asked to pair?
  Future<void> _check() async {
    if (_asking || !mounted) return;
    if (_expires != null && DateTime.now().isAfter(_expires!)) {
      _stopPairing();
      return;
    }
    final access = ref.read(hubAdminProvider);
    try {
      final pending = await access.run((h) => h.pending());
      if (pending == null || !mounted) return;
      _asking = true;
      final approved = await SyncPairApprovalDialog.show(context, pending);
      await access.run((h) => h.answer(approved));
      _asking = false;
      if (approved && mounted) {
        showInfoToast(rootOverlayOf(context), 'Paired with ${pending.name}');
        _stopPairing();
        ref.read(syncRevisionProvider.notifier).bump();
      }
    } on Object {
      _asking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(syncClientProvider);
    final theme = Theme.of(context);
    final peers = ref.watch(hubPeersProvider);
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
          leading: const Icon(Icons.dns_outlined),
          title: Text(status.peerName ?? 'LiveNow hub'),
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
                  title: 'Disconnect from the hub?',
                  text:
                      'This PC stops syncing with the hub and serves phones '
                      'itself again while LiveNow is open. Your data stays as '
                      'it is.',
                  action: 'Disconnect',
                );
                if (ok) await ref.read(syncClientProvider.notifier).forget();
              },
              child: const Text('Disconnect hub'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text('Paired phones', style: theme.textTheme.titleSmall),
        ...switch (peers) {
          AsyncData(:final value) => [
            if (value.where((p) => !p.admin).isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('No phone is paired with the hub yet.'),
              ),
            for (final p in value.where((p) => !p.admin))
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
                          'It can no longer sync with the hub until it is '
                          'paired again. Its data stays on the phone.',
                      action: 'Remove',
                    );
                    if (!ok) return;
                    await ref
                        .read(hubAdminProvider)
                        .run((h) => h.removePeer(p.deviceId));
                    ref.read(syncRevisionProvider.notifier).bump();
                  },
                ),
              ),
          ],
          AsyncError() => [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'The hub did not answer, so the phones cannot be listed.',
                key: ValueKey('sync-hub-peers-error'),
              ),
            ),
          ],
          _ => [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('…'),
            ),
          ],
        },
        const SizedBox(height: 8),
        if (_code != null)
          _PairingCode(code: _code!, expires: _expires!, onCancel: _cancel)
        else
          FilledButton.tonalIcon(
            key: const ValueKey('sync-pair-phone'),
            icon: const Icon(Icons.qr_code_2),
            label: const Text('Pair a new phone'),
            onPressed: _startPairing,
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _error!,
              key: const ValueKey('sync-hub-error'),
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
        const _ConflictsRow(),
      ],
    );
  }
}

class _PairingCode extends ConsumerStatefulWidget {
  const _PairingCode({
    required this.code,
    required this.expires,
    this.onCancel,
  });
  final PairingUri code;
  final DateTime expires;

  /// What Cancel does; default = close this PC's own pairing window (a hub
  /// pairing is closed on the hub instead).
  final VoidCallback? onCancel;

  @override
  ConsumerState<_PairingCode> createState() => _PairingCodeState();
}

class _PairingCodeState extends ConsumerState<_PairingCode> {
  Timer? _tick;
  bool _copied = false;

  /// The code on the clipboard (Windows keeps a clipboard history) is useless
  /// once pairing ends: clear it, but only if it is still this code.
  Future<void> _clearClipboard(String text) async {
    try {
      final now = await Clipboard.getData(Clipboard.kTextPlain);
      if (now?.text == text) {
        await Clipboard.setData(const ClipboardData(text: ''));
      }
    } on Object {
      // No clipboard access: nothing to clear.
    }
  }

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
    if (_copied) _clearClipboard(widget.code.toString());
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
              onPressed: () {
                _copied = true;
                Clipboard.setData(ClipboardData(text: text));
              },
            ),
            Text(
              'valid for ${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}',
              key: const ValueKey('sync-countdown'),
            ),
          ],
        ),
        TextButton(
          key: const ValueKey('sync-pair-cancel'),
          onPressed:
              widget.onCancel ??
              ref.read(syncHostControllerProvider.notifier).cancelPairing,
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
    var replace = false;
    if (counts.values.any((n) => n > 0)) {
      final choice = await showStackedDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('This phone already has data'),
          content: Text(
            'Keep both: the phone\'s '
            '(${counts['actions']} actions, ${counts['metrics']} growth '
            'directions, ${counts['budget_transactions']} transactions) and '
            'the PC\'s data are merged, nothing is deleted, and for an action '
            'edited on both the newest edit wins. This is the safe choice, '
            'also after re-pairing.\n\n'
            'Replace: the PC\'s data replaces everything on this phone, so '
            'edits not yet sent are lost.\n\n'
            'A backup copy of the phone\'s data is kept for 30 days either '
            'way.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              key: const ValueKey('sync-replace'),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Replace'),
            ),
            FilledButton(
              key: const ValueKey('sync-merge'),
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Keep both'),
            ),
          ],
        ),
      );
      if (choice == null || !mounted) return;
      replace = choice;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(syncClientProvider.notifier).pairAndReplace(code, replace: replace);
      _code.clear();
    } on SyncAuthException {
      _error =
          'The code was wrong or has expired, or the PC declined. Show a '
          'new one on the PC. Also check that both clocks are right.';
    } on FormatException catch (e) {
      _error = e.message;
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

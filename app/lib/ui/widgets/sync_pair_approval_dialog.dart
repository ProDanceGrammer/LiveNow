import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/sync/sync_server.dart' show PairRequest;
import '../dialog_stack.dart';

/// "Pair this phone?" - shown on the PC when a phone has proved it knows the
/// pairing code. The code alone is not enough: it may have been photographed
/// or read over a shoulder, so the owner confirms who is asking. Gives up and
/// says no after 60 seconds.
class SyncPairApprovalDialog extends StatefulWidget {
  const SyncPairApprovalDialog({super.key, required this.request});

  final PairRequest request;

  /// True = approved. Not dismissible by tapping outside.
  static Future<bool> show(BuildContext context, PairRequest request) async =>
      await showStackedDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => SyncPairApprovalDialog(request: request),
      ) ??
      false;

  @override
  State<SyncPairApprovalDialog> createState() => _SyncPairApprovalDialogState();
}

class _SyncPairApprovalDialogState extends State<SyncPairApprovalDialog> {
  Timer? _giveUp;

  @override
  void initState() {
    super.initState();
    _giveUp = Timer(const Duration(seconds: 60), () {
      if (mounted) Navigator.of(context).pop(false);
    });
  }

  @override
  void dispose() {
    _giveUp?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Pair this phone?'),
      content: Text(
        'A phone named "${widget.request.name}" entered the pairing code and '
        'asks to sync with this PC. It will be able to read and change all '
        'your data.\n\nApprove only if you just scanned the code on your own '
        'phone.',
      ),
      actions: [
        TextButton(
          key: const ValueKey('sync-pair-deny'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Deny'),
        ),
        FilledButton(
          key: const ValueKey('sync-pair-approve'),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Approve'),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../dialog_stack.dart';

/// Scans the QR code shown on the PC and returns its text (null if closed).
/// Phone only: the camera plugin does not exist on desktop.
class SyncScanDialog extends StatelessWidget {
  const SyncScanDialog({super.key});

  static Future<String?> show(BuildContext context) =>
      showStackedDialog<String>(
        context: context,
        builder: (_) => const SyncScanDialog(),
      );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Scan the code on your PC'),
      content: SizedBox(
        width: 320,
        height: 320,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: MobileScanner(
            onDetect: (capture) {
              final text = capture.barcodes
                  .map((b) => b.rawValue)
                  .whereType<String>()
                  .firstWhere(
                    (t) => t.startsWith('livenow://'),
                    orElse: () => '',
                  );
              if (text.isNotEmpty) Navigator.of(context).pop(text);
            },
          ),
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

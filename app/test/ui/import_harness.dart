import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef ImportAction = Future<void> Function(BuildContext, WidgetRef);

/// The import/export buttons moved to Settings; the screen tests that used to
/// tap them call the same shared functions (`ui/data_imports.dart`) through
/// these buttons instead, above the screen under test.
class ImportHarness extends ConsumerWidget {
  const ImportHarness({super.key, required this.actions, required this.child});

  /// Button key -> what it runs.
  final Map<String, ImportAction> actions;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    body: Column(
      children: [
        Row(
          children: [
            for (final e in actions.entries)
              TextButton(
                key: ValueKey(e.key),
                onPressed: () => e.value(context, ref),
                child: Text(e.key),
              ),
          ],
        ),
        Expanded(child: child),
      ],
    ),
  );
}

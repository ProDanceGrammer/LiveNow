import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'domain/postpone_rules.dart';
import 'ui/screens/home_shell.dart';
import 'ui/undo.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  initPostponeTimeZoneData();
  runApp(const ProviderScope(child: LiveNowApp()));
}

class LiveNowApp extends ConsumerWidget {
  const LiveNowApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Wrapped outside MaterialApp (not just around HomeShell) so Ctrl+Z
    // still reaches every dialog too — a dialog is pushed as a sibling
    // route on the app's own Navigator, not a descendant of `home`, so a
    // shortcut scoped to `home` alone would miss it.
    return CallbackShortcuts(
      bindings: {
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyZ):
            () => performUndo(ref),
      },
      child: Focus(
        autofocus: true,
        child: MaterialApp(
          title: 'LiveNow',
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
            useMaterial3: true,
          ),
          home: const HomeShell(),
        ),
      ),
    );
  }
}

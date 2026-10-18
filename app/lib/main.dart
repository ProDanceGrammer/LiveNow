import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'domain/postpone_rules.dart';
import 'hub/hub_main.dart';
import 'ui/link_launcher.dart';
import 'ui/root_navigator.dart';
import 'ui/screens/home_shell.dart';
import 'ui/theme/app_theme.dart';
import 'ui/widgets/glass.dart';
import 'ui/theme_mode.dart';
import 'ui/undo.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  initPostponeTimeZoneData();
  if (isHubMode(args)) {
    // The sync hub: no UI (runApp is never called, so nothing is drawn).
    await runHub(args);
    return;
  }
  installNotesLinkLauncher();
  final initialTheme = await loadThemeMode();
  runApp(
    ProviderScope(
      overrides: [
        themeModeProvider.overrideWith(() => ThemeModeNotifier(initialTheme)),
      ],
      child: const LiveNowApp(),
    ),
  );
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
        LogicalKeySet(
          LogicalKeyboardKey.control,
          LogicalKeyboardKey.keyZ,
        ): () =>
            performUndo(ref),
        LogicalKeySet(
          LogicalKeyboardKey.control,
          LogicalKeyboardKey.shift,
          LogicalKeyboardKey.keyL,
        ): () =>
            ref.read(themeModeProvider.notifier).toggle(),
      },
      child: Focus(
        autofocus: true,
        child: MaterialApp(
          navigatorKey: rootNavigatorKey,
          title: 'LiveNow',
          theme: buildAppTheme(Brightness.light),
          darkTheme: buildAppTheme(Brightness.dark),
          themeMode: ref.watch(themeModeProvider),
          // The window background (gradient + clouds + its blurred snapshot)
          // sits once under every page and dialog; pages are transparent.
          builder: (context, child) =>
              GlassBackground(child: child ?? const SizedBox.shrink()),
          home: const HomeShell(),
        ),
      ),
    );
  }
}

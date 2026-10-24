import 'ui/search_targets.dart';
import 'ui/shortcut_keys.dart';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/error_log.dart';
import 'domain/postpone_rules.dart';
import 'hub/hub_main.dart';
import 'ui/accounts/account_gate.dart';
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
  // Anything that throws out of an async callback (a button's write failing,
  // a stream erroring) is also written to error.log; the default handling
  // (console) stays.
  final previousOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    previousOnError?.call(details);
    ErrorLog.write(details.exception, details.stack, context: 'Flutter');
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    ErrorLog.write(error, stack, context: 'async');
    return false;
  };
  if (isHubMode(args)) {
    // The sync hub: no UI (runApp is never called, so nothing is drawn).
    await runHub(args);
    return;
  }
  installNotesLinkLauncher();
  final initialTheme = await loadThemeMode();
  // The gate finds / adopts the accounts, signs one in and builds the app in a
  // ProviderScope keyed by that account (see account_gate.dart).
  runApp(
    AccountGate(
      initialTheme: initialTheme,
      appBuilder: (context, account) => const LiveNowApp(),
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
        primaryActivator(LogicalKeyboardKey.keyZ): () =>
            performUndo(ref),
        primaryActivator(LogicalKeyboardKey.keyL, shift: true): () =>
            ref.read(themeModeProvider.notifier).toggle(),
        // Ctrl+F: the search bar of the view on screen; Ctrl+K: search over
        // everything.
        primaryActivator(LogicalKeyboardKey.keyF): () =>
            ref.read(searchTargetsProvider).trigger(),
        primaryActivator(LogicalKeyboardKey.keyK): openGlobalSearch,
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

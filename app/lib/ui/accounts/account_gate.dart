import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/accounts/account_auth.dart';
import '../../data/accounts/account_crypto.dart';
import '../../data/accounts/account_models.dart';
import '../../data/accounts/account_registry.dart';
import '../../data/accounts/adoption.dart';
import '../../data/accounts/profile_paths.dart';
import '../theme/app_theme.dart';
import '../theme_mode.dart';
import '../widgets/glass.dart';
import 'account_picker.dart';
import 'account_providers.dart';
import 'idle_lock.dart';
import 'account_session.dart';

/// Sits above everything: finds (or, for the data that existed before accounts,
/// adopts) the account registry, signs an account in and only then builds the
/// app inside a [ProviderScope] KEYED by the account, so a switch disposes every
/// provider, timer, sync controller and the database of the account that was
/// open and starts the next one from scratch.
///
/// With one account and no password it is invisible: the app opens as it always
/// did. The picker appears when there are several accounts or a password.
class AccountGate extends StatefulWidget {
  const AccountGate({
    super.key,
    required this.initialTheme,
    required this.appBuilder,
    this.root,
    this.kdfIterations = kAccountKdfIterations,
    this.idleUnit = const Duration(minutes: 1),
  });

  /// One "minute" of the idle-lock setting (tests shorten it).
  final Duration idleUnit;

  final ThemeMode initialTheme;

  /// Tests give a temp folder; null = the real app-support root (or
  /// `LIVENOW_DATA_DIR`).
  final Directory? root;

  /// Tests lower this (the real cost is the point in production).
  final int kdfIterations;

  /// Builds the app once an account is signed in (`main()` passes `LiveNowApp`;
  /// tests pass a small stand-in).
  final Widget Function(BuildContext context, Account account) appBuilder;

  @override
  State<AccountGate> createState() => _AccountGateState();
}

class _AccountGateState extends State<AccountGate> {
  AccountsStart? _start;
  AccountAuth? _auth;
  Object? _error;
  Account? _signedIn;
  int _generation = 0;
  int _idleMinutes = kIdleLockDefaultMinutes;
  bool _explicitSignOut = false;
  late ThemeMode _theme = widget.initialTheme;

  AccountRegistry get _registry => _start!.registry;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    activeProfileDirectory = null;
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      _start = null;
    });
    try {
      final root = widget.root ?? await appSupportRoot();
      final start = await loadOrAdoptRegistry(root);
      if (!mounted) return;
      _auth = AccountAuth(start.registry, iterations: widget.kdfIterations);
      setState(() => _start = start);
      await _maybeAutoSignIn();
    } on Object catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  /// One account without a password, or the last one used when it has none:
  /// straight in. Anything else (several accounts with no passwordless last
  /// one, a password, a deliberate sign-out) shows the picker.
  Future<void> _maybeAutoSignIn() async {
    final start = _start!;
    if (start.needsFirstRun || _explicitSignOut) return;
    final reg = start.registry;
    if (reg.accounts.length == 1 && !reg.accounts.first.hasPassword) {
      return _signIn(reg.accounts.first);
    }
    final last = reg.byId(reg.lastAccountId);
    if (last != null && !last.hasPassword) return _signIn(last);
  }

  Future<void> _signIn(Account account) async {
    final reg = _registry;
    await reg.setLast(account.id);
    final dir = await reg.profileDir(account).create(recursive: true);
    // Theme is per DEVICE: reread it (it may have changed in the last account).
    final loaded = await Future.wait<Object>([
      loadThemeMode(),
      loadIdleLockMinutes(dir),
    ]);
    final theme = loaded[0] as ThemeMode;
    final idle = loaded[1] as int;
    activeProfileDirectory = dir;
    if (!mounted) return;
    setState(() {
      _theme = theme;
      _idleMinutes = idle;
      _signedIn = account;
      _explicitSignOut = false;
      _generation++;
    });
  }

  void _setIdleMinutes(int minutes) {
    setState(() => _idleMinutes = minutes);
    final dir = activeProfileDirectory;
    if (dir != null) saveIdleLockMinutes(dir, minutes);
  }

  void _signOut() {
    activeProfileDirectory = null;
    setState(() {
      _signedIn = null;
      _explicitSignOut = true;
    });
  }

  /// A first-run name: creates the main account (whose folder is the root).
  Future<void> _firstRun(String name) async {
    final reg = _registry;
    final main = await reg.addMain(name);
    if (!mounted) return;
    setState(() => _start = AccountsStart(reg, needsFirstRun: false));
    await _signIn(main);
  }

  @override
  Widget build(BuildContext context) {
    final signed = _signedIn;
    if (signed != null && _start != null) {
      final session = AccountSession(
        accountId: signed.id,
        registry: _registry,
        auth: _auth!,
        signOut: _signOut,
        changed: () => setState(() {}),
        idleMinutes: _idleMinutes,
        setIdleMinutes: _setIdleMinutes,
      );
      // Only an account WITH a password locks itself; Off (0) never does.
      final locks = _registry.byId(signed.id)?.hasPassword ?? false;
      return AccountSessionScope(
        session: session,
        child: IdleLock(
          timeout: locks && _idleMinutes > 0
              ? widget.idleUnit * _idleMinutes
              : null,
          onLock: _signOut,
          child: ProviderScope(
          key: ValueKey('${signed.id}#$_generation'),
          overrides: [
            themeModeProvider.overrideWith(() => ThemeModeNotifier(_theme)),
            syncAllowedProvider.overrideWithValue(signed.syncAllowed),
          ],
          child: Builder(builder: (c) => widget.appBuilder(c, signed)),
          ),
        ),
      );
    }
    return _GateApp(
      theme: _theme,
      child: _error != null
          ? _GateError(error: _error!, onRetry: _load)
          : _start == null
          ? const Scaffold(
              backgroundColor: Colors.transparent,
              body: Center(child: CircularProgressIndicator()),
            )
          : _start!.needsFirstRun
          ? FirstRunScreen(onCreate: _firstRun)
          : AccountPickerScreen(
              registry: _registry,
              auth: _auth!,
              onSignedIn: _signIn,
              onChanged: () => setState(() {}),
            ),
    );
  }
}

/// The picker's own app shell: the same theme and glass background, a separate
/// navigator (the real app's `rootNavigatorKey` belongs to [LiveNowApp]).
class _GateApp extends StatelessWidget {
  const _GateApp({required this.theme, required this.child});

  final ThemeMode theme;
  final Widget child;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'LiveNow',
    debugShowCheckedModeBanner: false,
    theme: buildAppTheme(Brightness.light),
    darkTheme: buildAppTheme(Brightness.dark),
    themeMode: theme,
    builder: (context, c) => GlassBackground(child: c ?? const SizedBox.shrink()),
    home: child,
  );
}

/// The registry (or the safety copy) failed: say so and offer a retry. The app
/// never carries on as if there were no accounts, and never overwrites a
/// registry it could not read.
class _GateError extends StatelessWidget {
  const _GateError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_person_outlined, size: 40),
                const SizedBox(height: 12),
                Text(
                  'LiveNow could not open your accounts',
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  '$error\n\nYour data has not been touched.',
                  key: const ValueKey('account-error'),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  key: const ValueKey('account-retry'),
                  onPressed: onRetry,
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

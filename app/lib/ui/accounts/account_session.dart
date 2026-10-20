import 'package:flutter/widgets.dart';

import '../../data/accounts/account_auth.dart';
import '../../data/accounts/account_models.dart';
import '../../data/accounts/account_registry.dart';

/// The signed-in account as the rest of the app sees it: who it is, the
/// registry and the auth rules (for Settings), and two actions the gate owns.
/// Null in tests that do not mount the gate, so every consumer must cope with
/// `maybeOf` returning null (it then simply shows no account section).
class AccountSession {
  const AccountSession({
    required this.accountId,
    required this.registry,
    required this.auth,
    required this.signOut,
    required this.changed,
  });

  final String accountId;
  final AccountRegistry registry;
  final AccountAuth auth;

  /// Leaves this account and shows the account picker (the open account's
  /// providers, timers and sync controllers are disposed with it).
  final VoidCallback signOut;

  /// Tell the gate the registry changed (a rename, a password, 2FA...), so the
  /// settings and the picker read the new values.
  final VoidCallback changed;

  /// Fresh from the registry (a rename shows at once).
  Account get account => registry.byId(accountId)!;
}

/// Provides the [AccountSession] below the gate.
class AccountSessionScope extends InheritedWidget {
  const AccountSessionScope({
    super.key,
    required this.session,
    required super.child,
  });

  final AccountSession session;

  static AccountSession? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<AccountSessionScope>()
      ?.session;

  // The gate rebuilds the scope when the registry changes: dependents re-read.
  @override
  bool updateShouldNotify(AccountSessionScope oldWidget) => true;
}

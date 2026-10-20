import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../data/accounts/account_auth.dart';
import '../../data/accounts/account_models.dart';
import '../../data/accounts/account_registry.dart';

/// Shortest password a new account accepts.
const int kMinPasswordLength = 8;

String _lockMessage(DateTime until) {
  final left = until.difference(DateTime.now());
  final s = left.inSeconds < 1 ? 1 : left.inSeconds;
  final text = s >= 60 ? '${(s / 60).ceil()} min' : '$s s';
  return 'Too many wrong tries. Try again in $text.';
}

/// First run on a new install: a name for the first account (its folder is the
/// app's own data folder). A password can be added later in Settings.
class FirstRunScreen extends StatefulWidget {
  const FirstRunScreen({super.key, required this.onCreate});

  final Future<void> Function(String name) onCreate;

  @override
  State<FirstRunScreen> createState() => _FirstRunScreenState();
}

class _FirstRunScreenState extends State<FirstRunScreen> {
  final _name = TextEditingController(text: 'Me');
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    if (_busy) return;
    setState(() => _busy = true);
    await widget.onCreate(_name.text.trim().isEmpty ? 'Me' : _name.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return _Centered(
      title: 'Welcome to LiveNow',
      children: [
        const Text('What should we call your account?'),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('first-run-name'),
          controller: _name,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
          onSubmitted: (_) => _go(),
        ),
        const SizedBox(height: 16),
        FilledButton(
          key: const ValueKey('first-run-ok'),
          onPressed: _busy ? null : _go,
          child: const Text('Start'),
        ),
      ],
    );
  }
}

/// Who is using LiveNow: one card per account (a lock marks a password, a shield
/// 2FA), plus "Add account". A tap signs in, asking for the password and the
/// second factor first when the account has them.
class AccountPickerScreen extends StatelessWidget {
  const AccountPickerScreen({
    super.key,
    required this.registry,
    required this.auth,
    required this.onSignedIn,
    required this.onChanged,
  });

  final AccountRegistry registry;
  final AccountAuth auth;
  final Future<void> Function(Account account) onSignedIn;
  final VoidCallback onChanged;

  Future<void> _open(BuildContext context, Account a) async {
    if (!a.hasPassword) return onSignedIn(a);
    final result = await showDialog<SignInResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => SignInDialog(account: a, auth: auth),
    );
    if (result == null || !context.mounted) return;
    if (result.usedRecoveryCode) {
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('You used a recovery code'),
          content: Text(
            '${auth.recoveryCodesLeft(a.id)} left. In Settings > Account you '
            'can make a new set, or turn two-factor off and on again to set up '
            'your authenticator app again.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(c).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
    await onSignedIn(a);
  }

  Future<void> _add(BuildContext context) async {
    final created = await showDialog<Account>(
      context: context,
      builder: (_) => NewAccountDialog(registry: registry, auth: auth),
    );
    onChanged();
    if (created != null && context.mounted) await onSignedIn(created);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _Centered(
      title: 'Who is using LiveNow?',
      children: [
        for (final a in registry.accounts)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                key: ValueKey('account-card-${a.id}'),
                leading: CircleAvatar(
                  child: Text(
                    a.name.isEmpty ? '?' : a.name.characters.first.toUpperCase(),
                  ),
                ),
                title: Text(a.name),
                subtitle: Text(
                  a.isMain ? 'Main account · syncs with your hub' : 'This device only',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (a.hasTwoFactor)
                      const Icon(Icons.verified_user_outlined, size: 20),
                    if (a.hasPassword)
                      const Padding(
                        padding: EdgeInsets.only(left: 6),
                        child: Icon(Icons.lock_outline, size: 20),
                      ),
                  ],
                ),
                onTap: () => _open(context, a),
              ),
            ),
          ),
        const SizedBox(height: 4),
        OutlinedButton.icon(
          key: const ValueKey('account-add'),
          icon: const Icon(Icons.person_add_alt_1),
          label: const Text('Add account'),
          onPressed: () => _add(context),
        ),
        const SizedBox(height: 16),
        Text(
          'A password and two-factor keep other people on this computer out of '
          'your account. They do not encrypt the files on disk.',
          style: theme.textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _Centered extends StatelessWidget {
  const _Centered({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  ...children,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// What a finished sign-in tells the picker.
class SignInResult {
  const SignInResult({this.usedRecoveryCode = false, this.key});
  final bool usedRecoveryCode;

  /// The password-derived AES key (Settings uses it to re-seal secrets).
  final Uint8List? key;
}

/// Password, then (when the account has 2FA) the authenticator or a recovery
/// code. Wrong tries show a short message; too many show how long to wait. The
/// dialog never says which of the two was wrong beyond "password" / "code".
class SignInDialog extends StatefulWidget {
  const SignInDialog({
    super.key,
    required this.account,
    required this.auth,
    this.title,
    this.confirmLabel = 'Sign in',
  });

  final Account account;
  final AccountAuth auth;

  /// Settings reuses this dialog to confirm it is really the owner before a
  /// sensitive change ("Confirm it is you").
  final String? title;
  final String confirmLabel;

  @override
  State<SignInDialog> createState() => _SignInDialogState();
}

class _SignInDialogState extends State<SignInDialog> {
  final _field = TextEditingController();
  bool _busy = false;
  bool _askCode = false;
  String? _error;
  PasswordCheck? _password;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final text = _field.text;
    setState(() {
      _busy = true;
      _error = null;
    });
    final id = widget.account.id;
    if (!_askCode) {
      final r = await widget.auth.checkPassword(id, text);
      if (!mounted) return;
      if (!r.ok) {
        return _fail(
          r.status == CheckStatus.locked
              ? _lockMessage(r.lockedUntil!)
              : 'Wrong password.',
        );
      }
      if (widget.account.hasTwoFactor) {
        _password = r;
        _field.clear();
        setState(() {
          _askCode = true;
          _busy = false;
        });
        return;
      }
      Navigator.of(context).pop(SignInResult(key: r.key));
    } else {
      final r = await widget.auth.checkSecondFactor(id, _password!.key!, text);
      if (!mounted) return;
      if (!r.ok) {
        return _fail(
          r.status == CheckStatus.locked
              ? _lockMessage(r.lockedUntil!)
              : 'Wrong code. A code works once: wait for the next one if you '
                    'just used it.',
        );
      }
      Navigator.of(context).pop(
        SignInResult(
          usedRecoveryCode: r.kind == SecondFactorKind.recoveryCode,
          key: _password!.key,
        ),
      );
    }
  }

  void _fail(String message) {
    _field.clear();
    setState(() {
      _busy = false;
      _error = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        _askCode ? 'Two-factor code' : (widget.title ?? widget.account.name),
      ),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_askCode)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  'Enter the 6-digit code from your authenticator app, or one '
                  'of your recovery codes.',
                ),
              ),
            TextField(
              key: ValueKey(_askCode ? 'account-code-field' : 'account-password-field'),
              controller: _field,
              autofocus: true,
              obscureText: !_askCode,
              enableSuggestions: false,
              autocorrect: false,
              keyboardType: _askCode ? TextInputType.visiblePassword : null,
              decoration: InputDecoration(
                labelText: _askCode ? 'Code' : 'Password',
                errorText: _error,
              ),
              onSubmitted: (_) => _submit(),
            ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: LinearProgressIndicator(),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('account-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: ValueKey(_askCode ? 'account-code-ok' : 'account-password-ok'),
          onPressed: _busy ? null : _submit,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

/// A name and an optional password; makes a local account (this device only).
class NewAccountDialog extends StatefulWidget {
  const NewAccountDialog({super.key, required this.registry, required this.auth});

  final AccountRegistry registry;
  final AccountAuth auth;

  @override
  State<NewAccountDialog> createState() => _NewAccountDialogState();
}

class _NewAccountDialogState extends State<NewAccountDialog> {
  final _name = TextEditingController();
  final _password = TextEditingController();
  final _repeat = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _password.dispose();
    _repeat.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_busy) return;
    final name = _name.text.trim();
    final pw = _password.text;
    if (name.isEmpty) return setState(() => _error = 'Give the account a name.');
    if (pw.isNotEmpty && pw.length < kMinPasswordLength) {
      return setState(
        () => _error = 'A password needs at least $kMinPasswordLength characters.',
      );
    }
    if (pw != _repeat.text) {
      return setState(() => _error = 'The two passwords differ.');
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final account = await widget.registry.create(name);
    if (pw.isNotEmpty) await widget.auth.setPassword(account.id, pw);
    if (!mounted) return;
    Navigator.of(context).pop(widget.registry.byId(account.id));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add account'),
      content: SizedBox(
        width: 340,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                key: const ValueKey('account-new-name'),
                controller: _name,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('account-new-password'),
                controller: _password,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Password (optional)',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('account-new-repeat'),
                controller: _repeat,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                decoration: const InputDecoration(labelText: 'Repeat password'),
                onSubmitted: (_) => _create(),
              ),
              const SizedBox(height: 8),
              Text(
                'Local to this device: it has its own actions, budget and '
                'settings. Sync with the hub is for the main account only, for '
                'now.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _error!,
                    key: const ValueKey('account-new-error'),
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: LinearProgressIndicator(),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('account-new-ok'),
          onPressed: _busy ? null : _create,
          child: const Text('Create'),
        ),
      ],
    );
  }
}

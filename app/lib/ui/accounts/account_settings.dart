import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../data/accounts/account_auth.dart';
import '../widgets/section_block.dart';
import 'account_picker.dart';
import 'account_session.dart';

/// The Account block of Settings: who is signed in, switching, a password, the
/// authenticator (2FA) with its recovery codes, rename and delete. Nothing shows
/// when the app runs without the account gate (tests).
class AccountSettingsSection extends StatelessWidget {
  const AccountSettingsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final session = AccountSessionScope.maybeOf(context);
    if (session == null) return const SizedBox.shrink();
    final account = session.account;
    final theme = Theme.of(context);

    Widget tile(
      String key,
      IconData icon,
      String label,
      VoidCallback onTap, {
      String? subtitle,
      Color? color,
    }) => ListTile(
      key: ValueKey(key),
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: color),
      title: Text(label, style: TextStyle(color: color)),
      subtitle: subtitle == null ? null : Text(subtitle),
      onTap: onTap,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
          child: Text('Account', style: theme.textTheme.titleMedium),
        ),
        SectionBlock(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          // ListTiles paint on the nearest Material: the block is a decorated
          // box, so they need a transparent one of their own.
          child: Material(
            type: MaterialType.transparency,
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListTile(
                key: const ValueKey('account-current'),
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  child: Text(
                    account.name.isEmpty
                        ? '?'
                        : account.name.characters.first.toUpperCase(),
                  ),
                ),
                title: Text(account.name),
                subtitle: Text(
                  account.isMain
                      ? 'Main account · syncs with your hub'
                      : 'This device only',
                ),
              ),
              tile(
                'account-switch',
                Icons.swap_horiz,
                'Switch account',
                session.signOut,
              ),
              tile(
                'account-rename',
                Icons.edit_outlined,
                'Rename',
                () => _rename(context, session),
              ),
              if (!account.hasPassword)
                tile(
                  'account-set-password',
                  Icons.lock_outline,
                  'Set a password',
                  () => _setPassword(context, session),
                  subtitle: 'Asked when this account is opened',
                )
              else ...[
                tile(
                  'account-change-password',
                  Icons.password,
                  'Change password',
                  () => _changePassword(context, session),
                ),
                tile(
                  'account-remove-password',
                  Icons.lock_open,
                  'Remove password',
                  () => _removePassword(context, session),
                  subtitle: account.hasTwoFactor
                      ? 'Also turns two-factor off'
                      : null,
                ),
                const Divider(height: 16),
                if (!account.hasTwoFactor)
                  tile(
                    'account-2fa-on',
                    Icons.verified_user_outlined,
                    'Turn on two-factor',
                    () => _enableTwoFactor(context, session),
                    subtitle:
                        'A 6-digit code from an authenticator app at sign-in',
                  )
                else ...[
                  tile(
                    'account-2fa-codes',
                    Icons.key,
                    'New recovery codes',
                    () => _newCodes(context, session),
                    subtitle:
                        '${session.auth.recoveryCodesLeft(account.id)} unused '
                        'codes left',
                  ),
                  tile(
                    'account-2fa-off',
                    Icons.remove_moderator_outlined,
                    'Turn off two-factor',
                    () => _disableTwoFactor(context, session),
                  ),
                ],
              ],
              if (!account.isMain) ...[
                const Divider(height: 16),
                tile(
                  'account-delete',
                  Icons.delete_outline,
                  'Delete this account',
                  () => _delete(context, session),
                  subtitle: 'Removes all of its data from this device',
                  color: theme.colorScheme.error,
                ),
              ],
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 4),
                child: Text(
                  'A password and two-factor keep other people who share this '
                  'computer out of your account. They do not encrypt the data '
                  'files on disk yet.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
          ),
        ),
      ],
    );
  }

  // ---- flows ---------------------------------------------------------------

  /// Asks for the password (and the second factor) again; the derived key, or
  /// null when cancelled.
  static Future<Uint8List?> _confirm(
    BuildContext context,
    AccountSession session,
  ) async {
    final r = await showDialog<SignInResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => SignInDialog(
        account: session.account,
        auth: session.auth,
        title: 'Confirm it is you',
        confirmLabel: 'Confirm',
      ),
    );
    return r?.key;
  }

  static Future<void> _rename(BuildContext context, AccountSession s) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _TextDialog(
        title: 'Rename account',
        label: 'Name',
        initial: s.account.name,
        fieldKey: 'account-rename-field',
        okKey: 'account-rename-ok',
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    await s.registry.update(s.account.copyWith(name: name.trim()));
    s.changed();
  }

  static Future<void> _setPassword(BuildContext context, AccountSession s) async {
    final pw = await showDialog<String>(
      context: context,
      builder: (_) => const _NewPasswordDialog(title: 'Set a password'),
    );
    if (pw == null) return;
    await s.auth.setPassword(s.account.id, pw);
    s.changed();
  }

  static Future<void> _changePassword(
    BuildContext context,
    AccountSession s,
  ) async {
    final key = await _confirm(context, s);
    if (key == null || !context.mounted) return;
    final pw = await showDialog<String>(
      context: context,
      builder: (_) => const _NewPasswordDialog(title: 'New password'),
    );
    if (pw == null) return;
    await s.auth.changePassword(s.account.id, key, pw);
    s.changed();
  }

  static Future<void> _removePassword(
    BuildContext context,
    AccountSession s,
  ) async {
    final key = await _confirm(context, s);
    if (key == null || !context.mounted) return;
    final ok = await _yesNo(
      context,
      'Remove the password?',
      s.account.hasTwoFactor
          ? 'Anyone can then open this account, and two-factor is turned off.'
          : 'Anyone can then open this account.',
      'Remove',
    );
    if (!ok) return;
    await s.auth.removePassword(s.account.id);
    s.changed();
  }

  static Future<void> _enableTwoFactor(
    BuildContext context,
    AccountSession s,
  ) async {
    final key = await _confirm(context, s);
    if (key == null || !context.mounted) return;
    final codes = await showDialog<List<String>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _EnrollDialog(session: s, aesKey: key),
    );
    if (codes == null || !context.mounted) return;
    s.changed();
    await _showCodes(context, codes);
  }

  static Future<void> _newCodes(BuildContext context, AccountSession s) async {
    final key = await _confirm(context, s);
    if (key == null || !context.mounted) return;
    final codes = await s.auth.regenerateRecoveryCodes(s.account.id);
    s.changed();
    if (!context.mounted) return;
    await _showCodes(context, codes);
  }

  static Future<void> _disableTwoFactor(
    BuildContext context,
    AccountSession s,
  ) async {
    final key = await _confirm(context, s);
    if (key == null || !context.mounted) return;
    final ok = await _yesNo(
      context,
      'Turn off two-factor?',
      'Signing in will need only the password.',
      'Turn off',
    );
    if (!ok) return;
    await s.auth.disableTwoFactor(s.account.id);
    s.changed();
  }

  static Future<void> _delete(BuildContext context, AccountSession s) async {
    final account = s.account;
    if (account.hasPassword) {
      final key = await _confirm(context, s);
      if (key == null || !context.mounted) return;
    }
    final typed = await showDialog<String>(
      context: context,
      builder: (_) => _TextDialog(
        title: 'Delete "${account.name}"?',
        label: 'Type the account name to confirm',
        hint: 'Everything in this account (actions, budget, settings, backups '
            'made on this device) is deleted from this device. This cannot be '
            'undone.',
        fieldKey: 'account-delete-field',
        okKey: 'account-delete-ok',
        okLabel: 'Delete',
      ),
    );
    if (typed == null || typed.trim() != account.name) return;
    final registry = s.registry;
    s.signOut();
    // Let the open account's database close before its folder goes.
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await registry.delete(account.id);
    s.changed();
  }

  static Future<bool> _yesNo(
    BuildContext context,
    String title,
    String body,
    String yes,
  ) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(c).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const ValueKey('account-yes'),
              onPressed: () => Navigator.of(c).pop(true),
              child: Text(yes),
            ),
          ],
        ),
      ) ??
      false;

  static Future<void> _showCodes(BuildContext context, List<String> codes) =>
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _RecoveryCodesDialog(codes: codes),
      );
}

/// One text box (rename, delete confirmation).
class _TextDialog extends StatefulWidget {
  const _TextDialog({
    required this.title,
    required this.label,
    required this.fieldKey,
    required this.okKey,
    this.initial = '',
    this.hint,
    this.okLabel = 'OK',
  });

  final String title;
  final String label;
  final String initial;
  final String? hint;
  final String fieldKey;
  final String okKey;
  final String okLabel;

  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  late final _c = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 340,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.hint != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(widget.hint!),
            ),
          TextField(
            key: ValueKey(widget.fieldKey),
            controller: _c,
            autofocus: true,
            decoration: InputDecoration(labelText: widget.label),
            onSubmitted: (v) => Navigator.of(context).pop(v),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: ValueKey(widget.okKey),
        onPressed: () => Navigator.of(context).pop(_c.text),
        child: Text(widget.okLabel),
      ),
    ],
  );
}

/// A new password typed twice (at least [kMinPasswordLength] characters).
class _NewPasswordDialog extends StatefulWidget {
  const _NewPasswordDialog({required this.title});

  final String title;

  @override
  State<_NewPasswordDialog> createState() => _NewPasswordDialogState();
}

class _NewPasswordDialogState extends State<_NewPasswordDialog> {
  final _a = TextEditingController();
  final _b = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _a.dispose();
    _b.dispose();
    super.dispose();
  }

  void _ok() {
    if (_a.text.length < kMinPasswordLength) {
      return setState(
        () => _error = 'At least $kMinPasswordLength characters.',
      );
    }
    if (_a.text != _b.text) {
      return setState(() => _error = 'The two passwords differ.');
    }
    Navigator.of(context).pop(_a.text);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 340,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const ValueKey('account-pw-new'),
            controller: _a,
            autofocus: true,
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            decoration: const InputDecoration(labelText: 'Password'),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('account-pw-repeat'),
            controller: _b,
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: 'Repeat password',
              errorText: _error,
            ),
            onSubmitted: (_) => _ok(),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const ValueKey('account-pw-ok'),
        onPressed: _ok,
        child: const Text('Save'),
      ),
    ],
  );
}

/// The QR code (and the typed key) for an authenticator app, then the first code
/// to prove it works. Pops the recovery codes when it does.
class _EnrollDialog extends StatefulWidget {
  const _EnrollDialog({required this.session, required this.aesKey});

  final AccountSession session;

  /// The password-derived key that seals the new secret.
  final Uint8List aesKey;

  @override
  State<_EnrollDialog> createState() => _EnrollDialogState();
}

class _EnrollDialogState extends State<_EnrollDialog> {
  late final TotpEnrollment _enrol = widget.session.auth.beginTwoFactor(
    widget.session.account.name,
  );
  final _code = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (_busy) return;
    setState(() => _busy = true);
    final codes = await widget.session.auth.enableTwoFactor(
      widget.session.account.id,
      widget.aesKey,
      _enrol,
      _code.text,
    );
    if (!mounted) return;
    if (codes == null) {
      _code.clear();
      return setState(() {
        _busy = false;
        _error = 'That code does not match. Check the time on your phone.';
      });
    }
    Navigator.of(context).pop(codes);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Set up two-factor'),
    content: SizedBox(
      width: 340,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Scan this with an authenticator app (Google Authenticator, '
              'Authy, 1Password...), or type the key into it.',
            ),
            const SizedBox(height: 12),
            Center(
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.all(8),
                child: QrImageView(
                  key: const ValueKey('account-2fa-qr'),
                  data: _enrol.uri,
                  size: 180,
                ),
              ),
            ),
            const SizedBox(height: 8),
            SelectableText(
              _enrol.typedKey,
              key: const ValueKey('account-2fa-key'),
              style: const TextStyle(fontFamily: 'Consolas', fontFamilyFallback: ['Menlo'], letterSpacing: 1),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('account-2fa-code'),
              controller: _code,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'The 6-digit code it shows now',
                errorText: _error,
              ),
              onSubmitted: (_) => _verify(),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const ValueKey('account-2fa-verify'),
        onPressed: _busy ? null : _verify,
        child: const Text('Turn on'),
      ),
    ],
  );
}

/// The recovery codes, shown ONCE: each opens the account a single time when the
/// authenticator is lost.
class _RecoveryCodesDialog extends StatelessWidget {
  const _RecoveryCodesDialog({required this.codes});

  final List<String> codes;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Your recovery codes'),
    content: SizedBox(
      width: 340,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Keep these somewhere safe. Each one works once if you lose your '
              'authenticator. They are shown only now.',
            ),
            const SizedBox(height: 12),
            SelectableText(
              codes.join('\n'),
              key: const ValueKey('account-recovery-codes'),
              style: const TextStyle(fontFamily: 'Consolas', fontFamilyFallback: ['Menlo'], height: 1.6),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton.icon(
        key: const ValueKey('account-recovery-copy'),
        icon: const Icon(Icons.copy, size: 18),
        label: const Text('Copy'),
        onPressed: () => Clipboard.setData(ClipboardData(text: codes.join('\n'))),
      ),
      FilledButton(
        key: const ValueKey('account-recovery-done'),
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('I saved them'),
      ),
    ],
  );
}

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// The root overlay, for toasts. Look it up BEFORE the first `await` of an
/// async helper (the calling widget may be gone afterwards); the overlay itself
/// belongs to the root navigator and outlives the page that triggered the toast.
OverlayState rootOverlayOf(BuildContext context) =>
    Overlay.of(context, rootOverlay: true);

class _ActiveToast {
  final OverlayEntry entry;
  final VoidCallback onClosed;
  bool closed = false;
  _ActiveToast(this.entry, this.onClosed);

  void close() {
    if (closed) return;
    closed = true;
    try {
      if (entry.mounted) entry.remove();
      entry.dispose();
    } catch (_) {
      // The overlay was already torn down.
    }
    onClosed();
  }
}

_ActiveToast? _active;

/// How tall the phone's bottom navigation bar is while it is on screen (0 on
/// Windows and in the phone's full-screen calendar). Set by the shell; a toast
/// sits above it so it never hides behind the bar.
final ValueNotifier<double> toastBottomInset = ValueNotifier<double>(0);

/// Removes the toast on screen, if any (e.g. its Undo was done by Ctrl+Z).
void dismissActiveToast() => _active?.close();

/// Shows a toast in the ROOT overlay, painted above every dialog and still
/// clickable. Text is `[leading][name][trailing]`; [name] is tappable when
/// [onNameTap] is given. [actionLabel]/[onAction] add a text button (Undo).
/// A new toast replaces the previous one; it disappears after [duration] or
/// when the overlay is disposed. [onClosed] runs once, whichever way it ends.
void showAppToast(
  OverlayState overlay, {
  required String leading,
  String? name,
  String trailing = '',
  VoidCallback? onNameTap,
  String? actionLabel,
  VoidCallback? onAction,
  VoidCallback? onClosed,
  Duration duration = const Duration(seconds: 5),
}) {
  _active?.close();
  late final _ActiveToast toast;
  final entry = OverlayEntry(
    builder: (_) => _ToastContent(
      leading: leading,
      name: name,
      trailing: trailing,
      onNameTap: onNameTap,
      actionLabel: actionLabel,
      onAction: onAction == null
          ? null
          : () {
              // Action first: closing may clear state the action reads.
              onAction();
              toast.close();
            },
      duration: duration,
      onExpired: () => toast.close(),
      onDisposed: () {
        // Overlay torn down without the toast ending normally.
        if (!toast.closed) {
          toast.closed = true;
          if (identical(_active, toast)) _active = null;
          // Not while the tree is being finalized.
          scheduleMicrotask(toast.onClosed);
        }
      },
    ),
  );
  toast = _ActiveToast(entry, onClosed ?? () {});
  _active = toast;
  overlay.insert(entry);
}

/// A toast with an "Undo" button. [onUndo] is the revert.
void showUndoToast(
  OverlayState overlay,
  String message, {
  required VoidCallback onUndo,
  VoidCallback? onClosed,
}) => showAppToast(
  overlay,
  leading: message,
  actionLabel: 'Undo',
  onAction: onUndo,
  onClosed: onClosed,
);

/// A plain toast; an optional tappable [name] sits between [leading] and
/// [trailing], e.g. `Created "` + name + `"`.
void showInfoToast(
  OverlayState overlay,
  String leading, {
  String? name,
  String trailing = '',
  VoidCallback? onNameTap,
}) => showAppToast(
  overlay,
  leading: leading,
  name: name,
  trailing: trailing,
  onNameTap: onNameTap,
);

class _ToastContent extends StatefulWidget {
  final String leading;
  final String? name;
  final String trailing;
  final VoidCallback? onNameTap;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Duration duration;
  final VoidCallback onExpired;
  final VoidCallback onDisposed;

  const _ToastContent({
    required this.leading,
    required this.name,
    required this.trailing,
    required this.onNameTap,
    required this.actionLabel,
    required this.onAction,
    required this.duration,
    required this.onExpired,
    required this.onDisposed,
  });

  @override
  State<_ToastContent> createState() => _ToastContentState();
}

class _ToastContentState extends State<_ToastContent> {
  late final Timer _timer;
  TapGestureRecognizer? _tap;

  void _onInset() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    toastBottomInset.addListener(_onInset);
    _timer = Timer(widget.duration, widget.onExpired);
    if (widget.onNameTap != null) {
      _tap = TapGestureRecognizer()..onTap = widget.onNameTap;
    }
  }

  @override
  void dispose() {
    toastBottomInset.removeListener(_onInset);
    _timer.cancel();
    _tap?.dispose();
    widget.onDisposed();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = scheme.onInverseSurface;
    final style = TextStyle(color: fg, fontSize: 14);
    // Above the on-screen keyboard AND above the bottom navigation bar (the
    // root overlay spans the whole screen, so neither is avoided for us).
    final media = MediaQuery.of(context);
    final nav = toastBottomInset.value;
    final lift = math.max(
      media.viewInsets.bottom,
      nav > 0 ? media.padding.bottom + nav : 0.0,
    );
    return Positioned(
      left: 16,
      right: 16,
      bottom: lift + (lift > 0 ? 12 : 24),
      child: Center(
        child: Material(
          color: scheme.inverseSurface,
          elevation: 6,
          borderRadius: BorderRadius.circular(12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Text.rich(
                        TextSpan(
                          style: style,
                          children: [
                            TextSpan(text: widget.leading),
                            if (widget.name != null)
                              TextSpan(
                                text: widget.name,
                                recognizer: _tap,
                                mouseCursor: _tap == null
                                    ? null
                                    : SystemMouseCursors.click,
                                style: _tap == null
                                    ? null
                                    : TextStyle(
                                        color: scheme.inversePrimary,
                                        decoration: TextDecoration.underline,
                                        decorationColor: scheme.inversePrimary,
                                      ),
                              ),
                            if (widget.trailing.isNotEmpty)
                              TextSpan(text: widget.trailing),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (widget.actionLabel != null) ...[
                    const SizedBox(width: 8),
                    TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: scheme.inversePrimary,
                      ),
                      onPressed: widget.onAction,
                      child: Text(widget.actionLabel!),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

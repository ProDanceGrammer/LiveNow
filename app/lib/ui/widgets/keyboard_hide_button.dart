import 'package:flutter/material.dart';

import '../../core/platform_info.dart';

/// On iOS, while the on-screen keyboard is open, a small round button floats
/// at the right edge just above it; a tap hides the keyboard (iOS keyboards,
/// number pads above all, have no key for that). Sits in `MaterialApp.builder`
/// so it is above pages, dialogs and toasts; that is outside the Navigator's
/// overlay, hence no Tooltip (a Semantics label instead).
class KeyboardHideLayer extends StatelessWidget {
  const KeyboardHideLayer({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    final show = isIOSPlatform && inset > 0;
    final scheme = Theme.of(context).colorScheme;
    // Always a Stack with [child] first: switching the tree's shape when the
    // keyboard opens would rebuild the whole app and drop the focused field.
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        if (show)
          Positioned(
            right: 8,
            bottom: inset + 6,
            child: Semantics(
              button: true,
              label: 'Hide keyboard',
              child: Material(
                key: const ValueKey('keyboard-hide'),
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.92),
                shape: const CircleBorder(),
                elevation: 2,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
                  child: Padding(
                    padding: const EdgeInsets.all(7),
                    child: Icon(Icons.keyboard_hide, size: 20, color: scheme.onSurface),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

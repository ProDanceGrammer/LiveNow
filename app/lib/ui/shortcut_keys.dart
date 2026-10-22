import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show SingleActivator;

import '../core/platform_info.dart';

/// The "primary" shortcut modifier: Command on a Mac, Control everywhere else.
/// Every Ctrl+key shortcut and Ctrl+wheel / Ctrl+click goes through these two,
/// so the app feels native on a Mac without a second set of bindings.
bool isPrimaryPressed() => isMacPlatform
    ? HardwareKeyboard.instance.isMetaPressed
    : HardwareKeyboard.instance.isControlPressed;

/// `Ctrl+[key]` (Cmd on a Mac), optionally with Shift.
SingleActivator primaryActivator(LogicalKeyboardKey key, {bool shift = false}) =>
    SingleActivator(key, control: !isMacPlatform, meta: isMacPlatform, shift: shift);

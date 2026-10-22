import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'device_prefs.dart';

/// Device preference (`ui_prefs.json`): keep Flutter's accessibility tree on so
/// other programs that find the focused text through Windows UI Automation (text
/// editing / dictation tools) can see LiveNow's fields. Off by default: building
/// the semantics tree costs frame time on the busy screens.
const kTextToolAccessKey = 'text_tool_access';

final textToolAccessProvider = Provider<bool>(
  (ref) => ref.watch(devicePrefBoolProvider((kTextToolAccessKey, false))),
);

/// Holds the [SemanticsHandle] that keeps the accessibility tree on while the
/// preference is set. [apply] is idempotent.
class TextToolAccess {
  SemanticsHandle? _handle;

  bool get isOn => _handle != null;

  void apply(bool on) {
    if (on && _handle == null) {
      _handle = SemanticsBinding.instance.ensureSemantics();
    } else if (!on && _handle != null) {
      _handle!.dispose();
      _handle = null;
    }
  }

  void dispose() => apply(false);
}

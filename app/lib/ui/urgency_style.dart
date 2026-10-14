import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'device_prefs.dart';
import 'urgency_colors.dart';

/// PREVIEW (round 19): the dark-theme colour style, saved on this device.
const kUrgencyStylePref = 'urgency_dark_style';

final urgencyStyleProvider = Provider<UrgencyDarkStyle>((ref) {
  final v = ref.watch(devicePrefsProvider.select((m) => m[kUrgencyStylePref]));
  return UrgencyDarkStyle.values.firstWhere(
    (s) => s.name == v,
    orElse: () => UrgencyDarkStyle.current,
  );
});

void setUrgencyStyle(WidgetRef ref, UrgencyDarkStyle s) =>
    ref.read(devicePrefsProvider.notifier).set(kUrgencyStylePref, s.name);

void _rebuildAll() {
  void visit(Element e) {
    e.markNeedsBuild();
    e.visitChildren(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visit);
}

/// Applies the saved style to [urgencyDarkStyle] (a plain global the colour
/// functions read) and rebuilds the whole tree once when it changes, so every
/// screen picks the new colours up without losing its state.
class UrgencyStyleScope extends ConsumerWidget {
  const UrgencyStyleScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = ref.watch(urgencyStyleProvider);
    if (style != urgencyDarkStyle) {
      urgencyDarkStyle = style;
      WidgetsBinding.instance.addPostFrameCallback((_) => _rebuildAll());
    }
    return child;
  }
}

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'device_prefs.dart';
import 'urgency_colors.dart';

/// PREVIEW (round 19): the light-theme colour style, saved on this device.
const kUrgencyStylePref = 'urgency_light_style';

final urgencyStyleProvider = Provider<UrgencyLightStyle>((ref) {
  final v = ref.watch(devicePrefsProvider.select((m) => m[kUrgencyStylePref]));
  return UrgencyLightStyle.values.firstWhere(
    (s) => s.name == v,
    orElse: () => UrgencyLightStyle.current,
  );
});

void setUrgencyStyle(WidgetRef ref, UrgencyLightStyle s) =>
    ref.read(devicePrefsProvider.notifier).set(kUrgencyStylePref, s.name);

void _rebuildAll() {
  void visit(Element e) {
    e.markNeedsBuild();
    e.visitChildren(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visit);
}

/// Applies the saved style to [urgencyLightStyle] (a plain global the colour
/// functions read) and rebuilds the whole tree once when it changes, so every
/// screen picks the new colours up without losing its state.
class UrgencyStyleScope extends ConsumerWidget {
  const UrgencyStyleScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = ref.watch(urgencyStyleProvider);
    if (style != urgencyLightStyle) {
      urgencyLightStyle = style;
      WidgetsBinding.instance.addPostFrameCallback((_) => _rebuildAll());
    }
    return child;
  }
}

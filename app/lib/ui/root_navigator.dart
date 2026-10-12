import 'package:flutter/material.dart';

/// The app's one Navigator, reachable without a BuildContext: a tapped
/// notification (which arrives from the operating system, not from a widget)
/// uses it to open an action's editor.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'root navigator',
);

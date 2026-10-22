import 'package:flutter/foundation.dart';

/// True on macOS. Reads [defaultTargetPlatform] (not `dart:io`) so a widget test
/// can run a platform variant.
bool get isMacPlatform => defaultTargetPlatform == TargetPlatform.macOS;

/// A desktop OS with a keyboard and a mouse (not iOS / Android).
bool get isDesktopPlatform =>
    defaultTargetPlatform == TargetPlatform.windows ||
    defaultTargetPlatform == TargetPlatform.linux ||
    defaultTargetPlatform == TargetPlatform.macOS;

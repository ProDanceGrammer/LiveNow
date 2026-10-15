import 'package:flutter/widgets.dart';

/// Below this width the app uses the phone layout (bottom navigation, one
/// column, touch gestures); at and above it the desktop layout (side rail,
/// menu bar, hover toolbars). It follows the window width, so a narrow
/// Windows window shows exactly what the phone shows.
const kPhoneBreakpoint = 900.0;

bool usePhoneLayout(BuildContext context) =>
    MediaQuery.sizeOf(context).width < kPhoneBreakpoint;

/// The content width of a dialog: [wide] on a desktop window, never more than
/// the screen minus the dialog's own insets (a fixed 640 overflowed a phone).
double dialogWidth(BuildContext context, double wide) {
  final room = MediaQuery.sizeOf(context).width - 64;
  return room < wide ? room : wide;
}

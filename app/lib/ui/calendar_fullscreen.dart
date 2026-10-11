import 'package:flutter_riverpod/legacy.dart' show StateProvider;

/// Phone: the Calendar takes the whole screen (no app bar, view tabs or
/// bottom navigation). True = full screen; the floating exit button sets it to
/// false, the Calendar header's full-screen button sets it back. Re-armed
/// each time the Calendar is opened.
final phoneCalendarFullProvider = StateProvider<bool>((ref) => true);

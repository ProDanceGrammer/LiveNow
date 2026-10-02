import 'package:flutter_riverpod/legacy.dart' show StateProvider;

/// Ids of the cards selected on the Current Actions board (multi-select by
/// Ctrl/Shift+click or by dragging a rectangle over empty space). Each card
/// watches only `contains(its id)`, so a change rebuilds just the cards whose
/// state flipped.
final currentSelectionProvider = StateProvider<Set<String>>((ref) => const {});

import 'shortcut_keys.dart';
import 'package:flutter/services.dart' show HardwareKeyboard;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart' show StateProvider;

import 'providers.dart' show calendarSelectedActionProvider;

/// The calendar events currently selected (Shift/Ctrl+click adds or removes
/// one, a plain click selects only that one). Insertion-ordered, so `.last` is
/// the most recently added.
///
/// [calendarSelectedActionProvider] stays the "last clicked" id (the hover
/// toolbar, `runUndoableDelete` and older code read it); every helper below
/// updates both so they never disagree.
final calendarSelectionProvider = StateProvider<Set<String>>(
  (ref) => const <String>{},
);

/// Whether the current click should add to / remove from the selection
/// instead of replacing it.
bool isAdditiveCalendarClick() =>
    HardwareKeyboard.instance.isShiftPressed ||
    isPrimaryPressed();

/// A plain click: [id] becomes the only selected event.
void selectOnlyCalendarEvent(WidgetRef ref, String id) {
  ref.read(calendarSelectionProvider.notifier).state = {id};
  ref.read(calendarSelectedActionProvider.notifier).state = id;
}

/// Shift/Ctrl+click: adds [id] if absent, removes it if present.
void toggleCalendarEvent(WidgetRef ref, String id) {
  final next = {...ref.read(calendarSelectionProvider)};
  if (!next.remove(id)) next.add(id);
  ref.read(calendarSelectionProvider.notifier).state = next;
  ref.read(calendarSelectedActionProvider.notifier).state = next.contains(id)
      ? id
      : (next.isEmpty ? null : next.last);
}

/// Replaces the selection with [ids] (Ctrl+A, or pruning after a refresh).
void setCalendarSelection(WidgetRef ref, Set<String> ids) {
  ref.read(calendarSelectionProvider.notifier).state = ids;
  final single = ref.read(calendarSelectedActionProvider.notifier);
  if (single.state != null && !ids.contains(single.state)) {
    single.state = ids.isEmpty ? null : ids.last;
  }
}

/// Removes [id] from the selection (it is being deleted or moved away).
void deselectCalendarEvent(WidgetRef ref, String id) {
  final sel = ref.read(calendarSelectionProvider);
  if (sel.contains(id)) setCalendarSelection(ref, {...sel}..remove(id));
  final single = ref.read(calendarSelectedActionProvider.notifier);
  if (single.state == id) single.state = null;
}

/// Empties the selection (click on empty space, Escape, range change).
void clearCalendarSelection(WidgetRef ref) {
  if (ref.read(calendarSelectionProvider).isNotEmpty) {
    ref.read(calendarSelectionProvider.notifier).state = const <String>{};
  }
  final single = ref.read(calendarSelectedActionProvider.notifier);
  if (single.state != null) single.state = null;
}

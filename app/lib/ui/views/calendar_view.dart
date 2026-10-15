import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart'
    show
        DragStartBehavior,
        GestureBinding,
        LongPressGestureRecognizer,
        PointerCancelEvent,
        PointerDeviceKind,
        PointerDownEvent,
        PointerEvent,
        PointerMoveEvent,
        PointerScrollEvent,
        PointerSignalEvent,
        PointerUpEvent,
        kPrimaryButton,
        kSecondaryButton;
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show
        HapticFeedback,
        HardwareKeyboard,
        KeyDownEvent,
        KeyEvent,
        LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart' show StateProvider;
import 'package:timezone/timezone.dart' as tz;

import '../../core/settings.dart';
import '../../data/queries.dart';
import '../../domain/action_service.dart';
import '../../domain/duration_rules.dart';
import '../../domain/plan_rules.dart' show planDateOf;
import '../../domain/postpone_rules.dart';
import '../calendar_fullscreen.dart';
import '../calendar_allday.dart';
import '../calendar_icons.dart';
import '../calendar_selection.dart';
import '../edit_action.dart';
import '../layout.dart';
import '../plan_providers.dart';
import '../providers.dart';
import '../undo.dart';
import '../theme/glass_theme.dart';
import '../urgency_colors.dart';
import '../widgets/round_check.dart';
import '../widgets/action_editor.dart';
import '../widgets/action_tile.dart';
import '../widgets/bulk_dialogs.dart' show runBulkSetDate, runBulkShift;
import '../widgets/direction_badge.dart';
import '../widgets/glass.dart';
import '../widgets/continue_icon.dart';
import '../widgets/glass_icon_tile.dart';
import '../widgets/plan_dialogs.dart';
import 'plan_ghost_layer.dart';
import 'calendar_layout.dart';

const double _kGutter = 56;

/// Dragging a block within this many px of the grid's left/right edge, for
/// [_kEdgeHold], turns the visible range by a day.
const double _kEdgeZone = 16;

/// The pointer must also have travelled this far (px) from where the drag began
/// before the edge can turn the page: grabbing a block that already sits at the
/// border must not flip days.
const double _kEdgeTravel = 30;
const Duration _kEdgeHold = Duration(milliseconds: 600);
const double _kHandle = 6;

/// A block is never drawn shorter than this, however far the grid is zoomed
/// out, so a 10-minute event stays easy to grab.
const double _kMinBlockHeight = 8;
// Hover toolbar: 5 icon tiles (24 px + 2 px hit slop), a 9 px divider, 2 px padding.
const double _kToolTile = 24;
const double _kToolHit = 2;
const double _kToolPad = 2;
const double _kToolbarWidth = 5 * (_kToolTile + _kToolHit) + 9 + 2 * _kToolPad;
const double _kToolbarHeight = _kToolTile + _kToolHit + 2 * _kToolPad;

/// The smallest hour height the grid is drawn with, so a tiny window at the
/// 24-hour zoom stays usable (the grid then scrolls a little).
const double _kMinHourHeight = 12;

const _dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// Build/layout counters so a test can prove that selection, hover, drag and
/// clock ticks only rebuild what they must.
@visibleForTesting
class CalendarPerfCounters {
  static int blockBuilds = 0;
  static int chipBuilds = 0;
  static int layoutRuns = 0;

  /// Direction badges built (block or all-day chip), and times a hover
  /// toolbar was actually shown.
  static int badgeBuilds = 0;
  static int toolbarShows = 0;

  /// `_Toolbar` builds (must not grow while the grid scrolls).
  static int toolbarBuilds = 0;

  static void reset() {
    toolbarBuilds = 0;
    blockBuilds = 0;
    chipBuilds = 0;
    layoutRuns = 0;
    badgeBuilds = 0;
    toolbarShows = 0;
  }
}

/// How long after the last scroll movement the badges come back.
const _kScrollSettle = Duration(milliseconds: 150);

/// Shows [child] only while [scrolling] is false. With [keepSpace] it stays
/// laid out (so a row does not jump) but is not painted; otherwise it is
/// removed. Only this subtree reacts when the flag flips - the block that
/// contains it is never rebuilt.
class _HideWhileScrolling extends StatelessWidget {
  final ValueListenable<bool> scrolling;
  final bool keepSpace;
  final Widget child;
  const _HideWhileScrolling({
    required this.scrolling,
    required this.child,
    this.keepSpace = false,
  });

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: scrolling,
    child: child,
    builder: (_, hide, child) => keepSpace
        ? Opacity(opacity: hide ? 0 : 1, child: child)
        : hide
        ? const SizedBox.shrink()
        : child!,
  );
}

/// [DirectionBadge] that counts its builds for the perf tests.
class _CountedBadge extends StatelessWidget {
  final String actionId;
  final String icons;
  final double? maxWidth;
  final int? maxCount;
  const _CountedBadge({
    super.key,
    required this.actionId,
    required this.icons,
    this.maxWidth,
    this.maxCount,
  });

  @override
  Widget build(BuildContext context) {
    CalendarPerfCounters.badgeBuilds++;
    return DirectionBadge(
      actionId: actionId,
      icons: icons,
      maxWidth: maxWidth,
      maxCount: maxCount,
    );
  }
}

/// Faint hour/day lines on the glass panel (derived from the scheme).
Color _softLine(BuildContext context) {
  final g = context.glass;
  return Theme.of(context).colorScheme.outlineVariant
      .withValues(alpha: g.dark ? 0.3 : 0.55);
}

tz.TZDateTime _local(DateTime utc) =>
    tz.TZDateTime.from(utc, tz.getLocation(AppSettings.timeZoneName));

String _hhmm(DateTime utc) {
  final l = _local(utc);
  return '${twoDigits(l.hour)}:${twoDigits(l.minute)}';
}

/// End of [a] as drawn: never shorter than the minimum block (10 min).
DateTime _effectiveEnd(ActionListItem a) {
  final start = a.startAt!;
  final d = computeActionDuration(
    startAt: start,
    endAt: a.endAt,
    legacyEstimatedMinutes: a.estimatedMinutes,
  );
  const min = Duration(minutes: kMinDurationMinutes);
  return start.add(d < min ? min : d);
}

/// End of [a] as the data says (the block may be drawn taller): what the
/// time label must show.
DateTime _realEnd(ActionListItem a) => a.startAt!.add(
  computeActionDuration(
    startAt: a.startAt!,
    endAt: a.endAt,
    legacyEstimatedMinutes: a.estimatedMinutes,
  ),
);

// Selection by pointer. A press is handled the moment the button goes down
// (the tap recognizers wait out the double-tap timeout, by which time Shift
// may be released): Shift/Ctrl toggles the event, a plain press on an
// unselected event selects only it. A plain press on an event that is already
// part of a multi-selection keeps the selection (so the group can be dragged)
// and collapses to that event only on release, if nothing was dragged. Only
// one pointer is ever pressed, so this lives in two top-level variables.
String? _pressCollapseId;
bool _pressDragged = false;

/// Kind of the last pressed pointer: a finger never selects by touching (a tap
/// opens the editor, or toggles once something is selected; a long-press
/// selects), unlike a mouse.
PointerDeviceKind _pressKind = PointerDeviceKind.mouse;

/// The pressed mouse button was the RIGHT one: a desktop drag started with it
/// follows other events' edges (the magnet); the left button moves in plain
/// 10-minute steps.
bool _pressSecondary = false;
bool get _touchPress =>
    _pressKind == PointerDeviceKind.touch ||
    _pressKind == PointerDeviceKind.stylus;

/// Touch: the plain long-press (500 ms) arms the move at once (a buzz, then the
/// block follows the finger); holding on WITHOUT moving for this much longer
/// (3 s in all) selects the event instead.
const Duration _kSelectAfterArm = Duration(milliseconds: 2500);

/// How long a touch holds an all-day chip to select it.
const Duration _kChipSelectHold = Duration(seconds: 3);

/// A finger that travelled further than this (px) after the long-press is
/// dragging, not holding: no selection comes out of it.
const double _kHoldSlop = 10;

/// A dragged block this close (px) to the grid's top / bottom scrolls the grid
/// ([_TimeGridState._scrollTurn]), [_kScrollStep] px every 30 ms.
const double _kScrollEdge = 36;
const double _kScrollStep = 9;

/// Phone tap on an event: with a selection (made by long-press) it adds or
/// removes the event, otherwise it opens the editor.
void _phoneTap(BuildContext context, WidgetRef ref, String id) {
  if (_touchPress && ref.read(calendarSelectionProvider).isNotEmpty) {
    toggleCalendarEvent(ref, id);
    return;
  }
  openActionEditor(context, ref, id);
}

/// Phone long-press: selects the event (adds to a selection already made); one
/// that is selected stays selected.
void _phoneSelect(WidgetRef ref, String id) {
  HapticFeedback.selectionClick();
  final sel = ref.read(calendarSelectionProvider);
  if (sel.contains(id)) {
    ref.read(calendarSelectedActionProvider.notifier).state = id;
  } else if (sel.isEmpty) {
    selectOnlyCalendarEvent(ref, id);
  } else {
    toggleCalendarEvent(ref, id);
  }
}

void _onPress(
  WidgetRef ref,
  String id,
  PointerDownEvent e, {
  bool phone = false,
}) {
  _pressCollapseId = null;
  _pressDragged = false;
  _pressKind = e.kind;
  _pressSecondary = (e.buttons & kSecondaryButton) != 0;
  // On a phone a touch only selects through the long-press (see
  // [_phoneSelect]); a wide window's clicks always select on press.
  if (phone && _touchPress) return;
  if ((e.buttons & kPrimaryButton) == 0) return;
  final sel = ref.read(calendarSelectionProvider);
  if (isAdditiveCalendarClick()) {
    toggleCalendarEvent(ref, id);
  } else if (!sel.contains(id)) {
    selectOnlyCalendarEvent(ref, id);
  } else if (sel.length > 1) {
    _pressCollapseId = id;
    ref.read(calendarSelectedActionProvider.notifier).state = id;
  } else {
    ref.read(calendarSelectedActionProvider.notifier).state = id;
  }
}

void _onRelease(WidgetRef ref, String id) {
  final collapse = _pressCollapseId == id && !_pressDragged;
  _pressCollapseId = null;
  if (collapse) selectOnlyCalendarEvent(ref, id);
}

/// An all-day chip being dragged towards the time grid: the chip's action and
/// where the pointer is (global coordinates).
typedef _ChipDrag = ({ActionListItem item, Offset pos});

/// Drag state shared by the all-day strip and the time grid (siblings under
/// [CalendarView]), so a chip can be dragged down into the grid and a timed
/// block up into the strip. Pointer moves only touch these notifiers, never
/// the 300 blocks.
class _CrossDrag {
  /// The all-day chip being dragged (null = none); the grid draws its ghost.
  final chip = ValueNotifier<_ChipDrag?>(null);

  /// Day column of the all-day strip a timed block is hovering over while it
  /// is dragged (null = not over the strip); the strip highlights that cell.
  final stripTarget = ValueNotifier<int?>(null);

  /// True while the time grid is scrolling (and for [_kScrollSettle] after).
  /// Written by the grid; read only by badge subtrees and hover toolbars, so
  /// flipping it rebuilds no event block.
  final scrolling = ValueNotifier<bool>(false);

  /// True while the grid has a block drag (move/resize) in progress; the
  /// touch swipe that turns pages stands down then.
  bool gridDragging = false;

  /// On the strip's root box, to hit-test it in global coordinates.
  final stripKey = GlobalKey(debugLabel: 'all-day strip');

  /// The strip's day geometry, assigned by the strip on every build so chip
  /// drags can hit-test it.
  double stripDayWidth = 0;
  int stripDayCount = 0;

  int? _stripDayAtPos(Offset global) => stripDayCount == 0
      ? null
      : stripDayAt(global, stripDayWidth, stripDayCount);

  /// Set by the grid: called with the chip and the global drop position.
  void Function(ActionListItem item, Offset pos)? onChipDrop;

  ActionListItem? _pressed;
  Offset? _pressPos;
  bool _routed = false;

  void dispose() {
    _unroute();
    chip.dispose();
    stripTarget.dispose();
    scrolling.dispose();
  }

  /// The strip day column under [global], or null when it is not over the
  /// strip's day cells.
  int? stripDayAt(Offset global, double dayWidth, int dayCount) {
    final box = stripKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    final local = box.globalToLocal(global);
    final x = local.dx - _kGutter;
    if (local.dy < 0 || local.dy > box.size.height) return null;
    if (x < 0 || x >= dayWidth * dayCount) return null;
    return (x / dayWidth).floor().clamp(0, dayCount - 1);
  }

  void press(ActionListItem item, PointerDownEvent e) {
    _pressed = null;
    if ((e.buttons & kPrimaryButton) == 0 || isAdditiveCalendarClick()) return;
    _pressed = item;
    _pressPos = e.position;
  }

  /// A press on a chip turns into a drag after a few pixels of movement.
  void move(Offset pos) {
    final item = _pressed;
    if (item == null || chip.value != null) return;
    if ((pos - _pressPos!).distance < 6) return;
    _pressed = null;
    _pressDragged = true;
    chip.value = (item: item, pos: pos);
    if (!_routed) {
      _routed = true;
      GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
    }
  }

  void release() => _pressed = null;

  void _unroute() {
    if (!_routed) return;
    _routed = false;
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
  }

  void _onPointer(PointerEvent e) {
    final d = chip.value;
    if (d == null) {
      _unroute();
      return;
    }
    if (e is PointerMoveEvent) {
      stripTarget.value = _stripDayAtPos(e.position);
      chip.value = (item: d.item, pos: e.position);
    } else if (e is PointerUpEvent) {
      _unroute();
      stripTarget.value = null;
      chip.value = null;
      onChipDrop?.call(d.item, e.position);
    } else if (e is PointerCancelEvent) {
      _unroute();
      stripTarget.value = null;
      chip.value = null;
    }
  }
}

final _crossDragProvider = Provider<_CrossDrag>((ref) {
  final c = _CrossDrag();
  ref.onDispose(c.dispose);
  return c;
});

/// The Google-Calendar-style time grid: a header (navigation + 2..7 day
/// selector), a day header row, an all-day strip and a scrolling 24 h grid
/// where timed actions can be dragged (move) and edge-dragged (resize).
class CalendarView extends ConsumerWidget {
  const CalendarView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final start = ref.watch(calendarRangeStartProvider);
    final dayCount = ref.watch(calendarDayCountProvider);
    final items = ref.watch(calendarRangeProvider).value;
    ref.watch(currentBoardNowProvider); // re-evaluate once a minute
    final nowUtc = DateTime.now().toUtc();
    final running = <String>{
      for (final a in items ?? const <ActionListItem>[])
        if (a.isRunningAt(nowUtc)) a.id,
    };

    final phone = usePhoneLayout(context);
    final allDay = ref.watch(calendarAllDayProvider);
    // Turned upright with 4+ days showing: a phone offers 1-3 there.
    if (phone &&
        dayCount > 3 &&
        MediaQuery.orientationOf(context) == Orientation.portrait) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted && ref.read(calendarDayCountProvider) > 3) {
          setCalendarDayCount(ref, 3);
        }
      });
    }

    return _CalendarInput(
      child: Column(
        children: [
          if (!phone) const _Header(),
          Expanded(
            // One large glass panel under the day header, the all-day strip
            // and the grid, so the background clouds show around it. No blur
            // window: it is too big for that to pay off.
            child: Padding(
              // A phone gives the panel almost the whole screen.
              padding: phone
                  ? const EdgeInsets.fromLTRB(4, 0, 4, 4)
                  : const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: GlassSurface(
                radius: GlassTheme.radiusPanel,
                blurWindow: false,
                child: Stack(
                  children: [
                    Padding(
                      // Keeps the grid lines out of the rounded corners.
                      padding: phone
                          ? const EdgeInsets.fromLTRB(4, 2, 4, 8)
                          : const EdgeInsets.fromLTRB(8, 4, 8, 12),
                      child: items == null
                          ? const Center(child: CircularProgressIndicator())
                          : LayoutBuilder(
                              builder: (context, box) {
                                final dayW =
                                    (box.maxWidth - _kGutter) / dayCount;
                                final content = Column(
                                  children: [
                                    _DayHeaderRow(
                                      start: start,
                                      dayCount: dayCount,
                                      dayWidth: dayW,
                                      // One day on a phone: centre the label
                                      // on the whole panel, not on the part
                                      // right of the time gutter.
                                      centerOnPanel: phone && dayCount == 1,
                                    ),
                                    if (allDay)
                                      _AllDayStrip(
                                        start: start,
                                        dayCount: dayCount,
                                        dayWidth: dayW,
                                        items: items,
                                        running: running,
                                      ),
                                    Expanded(
                                      child: _TimeGrid(
                                        start: start,
                                        dayCount: dayCount,
                                        dayWidth: dayW,
                                        items: items,
                                        running: running,
                                      ),
                                    ),
                                  ],
                                );
                                // A finger swipe turns the pages (phone).
                                return phone
                                    ? _SwipeDays(pageKey: start, child: content)
                                    : content;
                              },
                            ),
                    ),
                    // The selected events: set / shift their date, delete.
                    if (items != null)
                      Positioned(
                        bottom: 14,
                        left: 0,
                        right: 0,
                        child: Center(child: _CalendarBulkBar(items: items)),
                      ),
                    if (ref.watch(calendarPlanningProvider))
                      Positioned(
                        top: phone ? 44 : 6,
                        right: 14,
                        child: const _CalendarPlanBar(),
                      ),
                    if (phone)
                      // Over the time column: Now, full screen, options.
                      Positioned(
                        top: 4,
                        left: 8,
                        width: _kGutter,
                        height: 38,
                        child: Builder(
                          builder: (context) {
                            final full = ref.watch(phoneCalendarFullProvider);
                            Widget small(Widget child) =>
                                SizedBox(width: 18, child: child);
                            return Row(
                              children: [
                                small(
                                  IconButton(
                                    key: const ValueKey('calendar-now-phone'),
                                    padding: EdgeInsets.zero,
                                    iconSize: 17,
                                    tooltip: 'Now',
                                    icon: const Icon(Icons.access_time_rounded),
                                    onPressed: () => goToCalendarToday(ref),
                                  ),
                                ),
                                small(
                                  IconButton(
                                    key: const ValueKey('calendar-full-toggle'),
                                    padding: EdgeInsets.zero,
                                    iconSize: 17,
                                    tooltip: full
                                        ? 'Show app menus'
                                        : 'Full screen',
                                    icon: Icon(
                                      full
                                          ? Icons.fullscreen_exit
                                          : Icons.fullscreen,
                                    ),
                                    onPressed: () =>
                                        ref
                                                .read(
                                                  phoneCalendarFullProvider
                                                      .notifier,
                                                )
                                                .state =
                                            !full,
                                  ),
                                ),
                                small(const _CalendarMenu()),
                              ],
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Touch swipe over the calendar: a clear horizontal drag turns the page like
/// the Windows ‹ › buttons (finger left = next, right = previous). Raw
/// pointers, no gesture recognizer, so a vertical scroll, a block's
/// long-press-drag and the pinch (two fingers cancel the swipe) behave as
/// before. The direction locks after a short slop, so a mostly-vertical scroll
/// that wobbles sideways never changes the day.
class _SwipeDays extends ConsumerStatefulWidget {
  final Widget child;

  /// The first day shown: when it changes the page fades in.
  final DateTime pageKey;
  const _SwipeDays({required this.child, required this.pageKey});

  @override
  ConsumerState<_SwipeDays> createState() => _SwipeDaysState();
}

class _SwipeDaysState extends ConsumerState<_SwipeDays>
    with SingleTickerProviderStateMixin {
  // A new page fades in (opacity only: the grid and its scroll state stay).
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 160),
    value: 1,
  );

  @override
  void didUpdateWidget(_SwipeDays old) {
    super.didUpdateWidget(old);
    if (old.pageKey != widget.pageKey) _fade.forward(from: 0.35);
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  static const _slop = 24.0;
  static const _commit = 64.0;

  final _down = <int, Offset>{};
  int? _tracked;
  Offset _delta = Offset.zero;
  bool _locked = false; // horizontal swipe confirmed
  bool _dead = false; // vertical scroll or multi-touch: ignore until up

  void _reset() {
    _tracked = null;
    _delta = Offset.zero;
    _locked = false;
    _dead = false;
  }

  void _onDown(PointerDownEvent e) {
    if (e.kind != PointerDeviceKind.touch) return;
    _down[e.pointer] = e.position;
    if (_down.length > 1) {
      _dead = true; // pinch or a second finger
    } else {
      _reset();
      _tracked = e.pointer;
    }
  }

  void _onMove(PointerMoveEvent e) {
    if (e.pointer != _tracked || _dead) return;
    final cross = ref.read(_crossDragProvider);
    if (cross.gridDragging || cross.chip.value != null) {
      _dead = true;
      return;
    }
    _delta += e.delta;
    if (!_locked && _delta.distance > _slop) {
      if (_delta.dx.abs() > _delta.dy.abs() * 1.5) {
        _locked = true;
      } else {
        _dead = true;
      }
    }
  }

  void _onUp(PointerEvent e) {
    final wasTracked = e.pointer == _tracked;
    _down.remove(e.pointer);
    if (!wasTracked) return;
    final swipe = _locked && !_dead && _delta.dx.abs() >= _commit;
    final dx = _delta.dx;
    _reset();
    if (e is PointerUpEvent && swipe) {
      shiftCalendarRange(ref, dx < 0 ? 1 : -1);
    }
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: _onDown,
    onPointerMove: _onMove,
    onPointerUp: _onUp,
    onPointerCancel: _onUp,
    child: FadeTransition(opacity: _fade, child: widget.child),
  );
}

/// Keyboard and wheel navigation for the whole calendar: Left/Right arrows
/// and Shift+scroll move the range one day at a time, Delete removes the
/// selected event (after confirming). The wrapper owns focus, and takes it
/// back on any click inside the calendar so the keys keep working after a
/// dialog or a header button had it.
class _CalendarInput extends ConsumerStatefulWidget {
  final Widget child;

  const _CalendarInput({required this.child});

  @override
  ConsumerState<_CalendarInput> createState() => _CalendarInputState();
}

/// Bumped whenever the Calendar becomes the shown view (first show, switching
/// back to it, re-selecting the Actions section) so [_CalendarInput] takes
/// keyboard focus without a click.
final calendarFocusRequestProvider = StateProvider<int>((ref) => 0);

const _digitKeys = [
  LogicalKeyboardKey.digit1,
  LogicalKeyboardKey.digit2,
  LogicalKeyboardKey.digit3,
  LogicalKeyboardKey.digit4,
  LogicalKeyboardKey.digit5,
  LogicalKeyboardKey.digit6,
  LogicalKeyboardKey.digit7,
];
const _numpadKeys = [
  LogicalKeyboardKey.numpad1,
  LogicalKeyboardKey.numpad2,
  LogicalKeyboardKey.numpad3,
  LogicalKeyboardKey.numpad4,
  LogicalKeyboardKey.numpad5,
  LogicalKeyboardKey.numpad6,
  LogicalKeyboardKey.numpad7,
];

class _CalendarInputState extends ConsumerState<_CalendarInput> {
  /// Scroll distance that counts as one day: one mouse-wheel notch reports
  /// 100, a touchpad sends many small deltas that accumulate to the same step.
  static const _pixelsPerDay = 100.0;

  final _focus = FocusNode(debugLabel: 'calendar');
  double _scrollAccumulated = 0;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent ||
        !HardwareKeyboard.instance.isShiftPressed) {
      return;
    }
    // Some mice report Shift+wheel on the horizontal axis instead.
    final delta = event.scrollDelta.dy != 0
        ? event.scrollDelta.dy
        : event.scrollDelta.dx;
    _scrollAccumulated += delta;
    final days = (_scrollAccumulated / _pixelsPerDay).truncate();
    if (days == 0) return;
    _scrollAccumulated -= days * _pixelsPerDay;
    shiftCalendarDays(ref, days);
  }

  /// Deletes every selected event (one Undo brings them all back). Only ids
  /// that are in the current data count, so nothing invisible is deleted.
  void _deleteSelected() {
    final ids = {...ref.read(calendarSelectionProvider)};
    final single = ref.read(calendarSelectedActionProvider);
    if (ids.isEmpty && single != null) ids.add(single);
    final visible = ref.read(calendarRangeProvider).value;
    if (visible != null) {
      final inView = {for (final a in visible) a.id};
      ids.retainAll(inView);
    }
    if (ids.isEmpty) return;
    clearCalendarSelection(ref);
    runUndoableDeleteMany(context, ref, ids);
  }

  void _selectAll() {
    final items = ref.read(calendarRangeProvider).value;
    if (items == null) return;
    setCalendarSelection(ref, {for (final a in items) a.id});
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(calendarFocusRequestProvider, (_, _) {
      if (mounted && !_focus.hasFocus) _focus.requestFocus();
    });
    return Listener(
      onPointerDown: (_) {
        if (!_focus.hasFocus) _focus.requestFocus();
      },
      onPointerSignal: _onPointerSignal,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
              shiftCalendarDays(ref, -1),
          const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
              shiftCalendarDays(ref, 1),
          // 1..7 (also on the numpad) set the number of day columns.
          for (var n = 1; n <= 7; n++) ...{
            SingleActivator(_digitKeys[n - 1]): () =>
                setCalendarDayCount(ref, n),
            SingleActivator(_numpadKeys[n - 1]): () =>
                setCalendarDayCount(ref, n),
          },
          const SingleActivator(LogicalKeyboardKey.delete): _deleteSelected,
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              clearCalendarSelection(ref),
          const SingleActivator(LogicalKeyboardKey.keyA, control: true):
              _selectAll,
          // Ctrl + "+" is Ctrl+= on most layouts (with or without Shift),
          // plus the numpad keys.
          const SingleActivator(LogicalKeyboardKey.equal, control: true): () =>
              zoomCalendar(ref, 1),
          const SingleActivator(
            LogicalKeyboardKey.equal,
            control: true,
            shift: true,
          ): () =>
              zoomCalendar(ref, 1),
          const SingleActivator(
            LogicalKeyboardKey.numpadAdd,
            control: true,
          ): () =>
              zoomCalendar(ref, 1),
          const SingleActivator(LogicalKeyboardKey.minus, control: true): () =>
              zoomCalendar(ref, -1),
          const SingleActivator(
            LogicalKeyboardKey.numpadSubtract,
            control: true,
          ): () =>
              zoomCalendar(ref, -1),
        },
        child: Focus(focusNode: _focus, autofocus: true, child: widget.child),
      ),
    );
  }
}

// ---- header ---------------------------------------------------------------

class _Header extends ConsumerWidget {
  const _Header();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final g = context.glass;
    final scheme = theme.colorScheme;
    final dayCount = ref.watch(calendarDayCountProvider);
    // Each group of controls sits in a soft glass pill.
    Widget pill(Widget child) => GlassSurface(
      radius: 20,
      shadow: false,
      blurWindow: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: child,
      ),
    );
    Widget toggle(
      Key key,
      bool on,
      IconData icon,
      String showTip,
      String hideTip,
      VoidCallback onTap,
    ) => pill(
      IconButton(
        key: key,
        isSelected: on,
        icon: Icon(icon),
        tooltip: on ? hideTip : showTip,
        style: IconButton.styleFrom(
          backgroundColor: on ? scheme.primaryContainer : null,
          foregroundColor: on ? scheme.onPrimaryContainer : null,
        ),
        onPressed: onTap,
      ),
    );
    final iconsOn = ref.watch(calendarIconsProvider);
    final allDayOn = ref.watch(calendarAllDayProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          pill(
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  tooltip: 'Previous',
                  onPressed: () => shiftCalendarRange(ref, -1),
                ),
                OutlinedButton(
                  key: const ValueKey('calendar-now'),
                  onPressed: () => goToCalendarToday(ref),
                  child: const Text('Now'),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  tooltip: 'Next',
                  onPressed: () => shiftCalendarRange(ref, 1),
                ),
              ],
            ),
          ),
          const Spacer(),
          // Zoom: how many hours of a day are visible at once.
          pill(
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.zoom_out),
                  tooltip: 'Show more hours (Ctrl+−)',
                  onPressed: () => zoomCalendar(ref, -1),
                ),
                Text(
                  '${ref.watch(calendarVisibleHoursProvider)} h',
                  key: const ValueKey('zoom-label'),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: g.textSecondary,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.zoom_in),
                  tooltip: 'Show fewer hours (Ctrl++)',
                  onPressed: () => zoomCalendar(ref, 1),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          toggle(
            const ValueKey('calendar-planning-toggle'),
            ref.watch(calendarPlanningProvider),
            Icons.event_repeat,
            'Plan ahead',
            'Leave planning',
            () => ref.read(calendarPlanningProvider.notifier).state =
                !ref.read(calendarPlanningProvider),
          ),
          const SizedBox(width: 12),
          // The same icon as the 'Growth directions' item in the rail.
          toggle(
            const ValueKey('calendar-icons-toggle'),
            iconsOn,
            Icons.insights,
            'Show growth direction icons',
            'Hide growth direction icons',
            () => ref.read(calendarIconsProvider.notifier).toggle(),
          ),
          const SizedBox(width: 12),
          toggle(
            const ValueKey('calendar-allday-toggle'),
            allDayOn,
            Icons.view_day_outlined,
            'Show all-day actions',
            'Hide all-day actions',
            () => ref.read(calendarAllDayProvider.notifier).toggle(),
          ),
          const SizedBox(width: 12),
          pill(
            SegmentedButton<int>(
              showSelectedIcon: false,
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
                side: const WidgetStatePropertyAll(BorderSide.none),
                backgroundColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.selected)
                      ? scheme.primaryContainer
                      : Colors.transparent,
                ),
                foregroundColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.selected)
                      ? scheme.onPrimaryContainer
                      : g.textSecondary,
                ),
              ),
              segments: [
                for (var n = 1; n <= 7; n++)
                  ButtonSegment(
                    value: n,
                    label: Text('$n'),
                    tooltip: n == 1 ? '1 day' : '$n days',
                  ),
              ],
              selected: {dayCount},
              onSelectionChanged: (s) => setCalendarDayCount(ref, s.first),
            ),
          ),
        ],
      ),
    );
  }
}

/// Phone: the calendar's only control, a small three-dots menu floating over
/// the panel's top-right corner (the calendar itself fills the screen): Now,
/// the day count (1-3 upright, 1-7 sideways), all-day on/off, direction icons
/// and leaving full screen. Zoom is by pinch, days by swiping.
class _CalendarMenu extends ConsumerWidget {
  const _CalendarMenu();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dayCount = ref.watch(calendarDayCountProvider);
    final maxDays = MediaQuery.orientationOf(context) == Orientation.landscape
        ? 7
        : 3;
    final iconsOn = ref.watch(calendarIconsProvider);
    final allDayOn = ref.watch(calendarAllDayProvider);
    return PopupMenuButton<String>(
      key: const ValueKey('calendar-menu'),
      tooltip: 'Calendar options',
      icon: const Icon(Icons.more_vert),
      padding: EdgeInsets.zero,
      iconSize: 17,
      onSelected: (v) {
        if (v.startsWith('days:')) {
          setCalendarDayCount(ref, int.parse(v.substring(5)));
        } else if (v == 'allday') {
          ref.read(calendarAllDayProvider.notifier).toggle();
        } else if (v == 'icons') {
          ref.read(calendarIconsProvider.notifier).toggle();
        } else if (v == 'planning') {
          ref.read(calendarPlanningProvider.notifier).state = !ref.read(
            calendarPlanningProvider,
          );
        }
      },
      itemBuilder: (_) => [
        for (var n = 1; n <= maxDays; n++)
          CheckedPopupMenuItem(
            key: ValueKey('calendar-menu-days-$n'),
            value: 'days:$n',
            checked: n == dayCount,
            child: Text(n == 1 ? '1 day' : '$n days'),
          ),
        const PopupMenuDivider(),
        CheckedPopupMenuItem(
          key: const ValueKey('calendar-menu-allday'),
          value: 'allday',
          checked: allDayOn,
          child: const Text('All-day actions'),
        ),
        CheckedPopupMenuItem(
          key: const ValueKey('calendar-menu-icons'),
          value: 'icons',
          checked: iconsOn,
          child: const Text('Growth direction icons'),
        ),
        CheckedPopupMenuItem(
          key: const ValueKey('calendar-menu-planning'),
          value: 'planning',
          checked: ref.read(calendarPlanningProvider),
          child: const Text('Planning'),
        ),
      ],
    );
  }
}

/// Planning mode's floating bar: confirm the plan (turn it into real actions)
/// and the list of plan items.
class _CalendarPlanBar extends ConsumerWidget {
  const _CalendarPlanBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = context.glass;
    final phone = usePhoneLayout(context);
    final hidden = [
      for (final c in ref.watch(planCollectionsProvider).value ?? const [])
        if (!c.visible) c,
    ].length;
    Widget action(String key, IconData icon, String label, VoidCallback onTap) =>
        phone
        ? IconButton(
            key: ValueKey(key),
            tooltip: label,
            icon: Icon(icon),
            onPressed: onTap,
          )
        : TextButton.icon(
            key: ValueKey(key),
            icon: Icon(icon, size: 18),
            label: Text(label),
            onPressed: onTap,
          );
    return Material(
      key: const ValueKey('calendar-plan-bar'),
      color: g.fillDialog,
      elevation: 6,
      shadowColor: Colors.black54,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: g.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            action(
              'plan-bar-add',
              Icons.add,
              'New plan item',
              () => PlanItemEditorDialog.show(context),
            ),
            action(
              'plan-bar-collections',
              Icons.folder_copy_outlined,
              hidden == 0 ? 'Collections' : 'Collections ($hidden hidden)',
              () => PlanCollectionsDialog.show(context),
            ),
            action(
              'plan-bar-items',
              Icons.list_alt,
              'Plan items',
              () => PlanItemsDialog.show(context),
            ),
            action(
              'plan-bar-confirm',
              Icons.check_circle_outline,
              'Confirm plan...',
              () => PlanConfirmDialog.show(context),
            ),
          ],
        ),
      ),
    );
  }
}

/// A floating bar over the grid while events are selected (Shift/Ctrl+click or
/// the marquee): Set date (the earliest one starts at the picked moment, the
/// others keep their distance), Shift by (everything moves the same amount),
/// Delete, Clear. Each is one transaction with ONE Undo.
class _CalendarBulkBar extends ConsumerWidget {
  const _CalendarBulkBar({required this.items});

  final List<ActionListItem> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sel = ref.watch(calendarSelectionProvider);
    final chosen = [
      for (final a in items)
        if (sel.contains(a.id)) a,
    ];
    if (chosen.isEmpty) return const SizedBox.shrink();
    final phone = usePhoneLayout(context);
    final error = Theme.of(context).colorScheme.error;

    Widget action(
      String key,
      IconData icon,
      String label,
      VoidCallback onPressed, {
      Color? color,
    }) => phone
        ? IconButton(
            key: ValueKey(key),
            tooltip: label,
            icon: Icon(icon, color: color),
            onPressed: onPressed,
          )
        : TextButton.icon(
            key: ValueKey(key),
            icon: Icon(icon, size: 18, color: color),
            label: Text(label, style: TextStyle(color: color)),
            onPressed: onPressed,
          );

    final g = context.glass;
    // OPAQUE: the glass fill is translucent, and the event text behind the bar
    // showed through it.
    return Material(
      key: const ValueKey('calendar-bulk-bar'),
      color: g.fillDialog,
      elevation: 6,
      shadowColor: Colors.black54,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: g.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${chosen.length} selected'),
            const SizedBox(width: 6),
            action(
              'cal-bulk-set-date',
              Icons.event,
              'Set date',
              () => runBulkSetDate(context, ref, chosen),
            ),
            action(
              'cal-bulk-shift',
              Icons.swap_horiz_rounded,
              'Shift by',
              () => runBulkShift(context, ref, chosen),
            ),
            action('cal-bulk-delete', Icons.delete_outline, 'Delete', () {
              final ids = [for (final a in chosen) a.id];
              setCalendarSelection(ref, const {});
              runUndoableDeleteMany(context, ref, ids);
            }, color: error),
            IconButton(
              key: const ValueKey('cal-bulk-clear'),
              tooltip: 'Clear selection',
              icon: const Icon(Icons.close),
              onPressed: () => setCalendarSelection(ref, const {}),
            ),
          ],
        ),
      ),
    );
  }
}

class _DayHeaderRow extends StatelessWidget {
  final DateTime start;
  final int dayCount;
  final double dayWidth;
  final bool centerOnPanel;

  const _DayHeaderRow({
    required this.start,
    required this.dayCount,
    required this.dayWidth,
    this.centerOnPanel = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final g = context.glass;
    final today = dayIndexOf(DateTime.now().toUtc(), start);
    return Container(
      height: 44,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: _softLine(context))),
      ),
      child: Row(
        children: [
          const SizedBox(width: _kGutter),
          for (var i = 0; i < dayCount; i++)
            Builder(
              builder: (context) {
                final l = _local(calendarAddDays(start, i));
                final isToday = i == today;
                // Narrow columns (a phone showing several days) get a one-letter
                // weekday and tighter padding so the header never overflows.
                final narrow = dayWidth < 72;
                return SizedBox(
                  key: ValueKey('day-header-$i'),
                  width: dayWidth,
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: centerOnPanel ? _kGutter : 0,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          narrow
                              ? _dayNames[l.weekday - 1].substring(0, 1)
                              : _dayNames[l.weekday - 1],
                          style: TextStyle(
                            color: isToday ? scheme.primary : g.textSecondary,
                            fontWeight: isToday ? FontWeight.w600 : null,
                          ),
                        ),
                        SizedBox(width: narrow ? 2 : 6),
                        Container(
                          constraints: const BoxConstraints(minWidth: 26),
                          padding: EdgeInsets.symmetric(
                            horizontal: narrow ? 3 : 6,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: isToday ? scheme.primary : null,
                            borderRadius: BorderRadius.circular(13),
                          ),
                          child: Text(
                            '${l.day}',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: isToday ? scheme.onPrimary : g.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

// ---- all-day strip --------------------------------------------------------

class _AllDayStrip extends ConsumerStatefulWidget {
  final DateTime start;
  final int dayCount;
  final double dayWidth;
  final List<ActionListItem> items;
  final Set<String> running;

  const _AllDayStrip({
    required this.start,
    required this.dayCount,
    required this.dayWidth,
    required this.items,
    required this.running,
  });

  @override
  ConsumerState<_AllDayStrip> createState() => _AllDayStripState();
}

class _AllDayStripState extends ConsumerState<_AllDayStrip> {
  /// Shift/Ctrl+drag on empty strip space draws a rubber band (global
  /// coordinates) and selects the chips it touches on release. Chips are
  /// found by scanning the keyed `allday-*` elements, like the Current board.
  Offset? _origin;
  bool _moved = false;
  final _marquee = ValueNotifier<Rect?>(null);

  @override
  void dispose() {
    _marquee.dispose();
    super.dispose();
  }

  Map<String, Rect> _chipRects() {
    final rects = <String, Rect>{};
    void visit(Element e) {
      final k = e.widget.key;
      if (k is ValueKey<String> && k.value.startsWith('allday-')) {
        final box = e.renderObject;
        if (box is RenderBox && box.attached && box.hasSize) {
          rects[k.value.substring(7)] =
              box.localToGlobal(Offset.zero) & box.size;
        }
        return;
      }
      e.visitChildren(visit);
    }

    (context as Element).visitChildren(visit);
    return rects;
  }

  void _down(PointerDownEvent e) {
    _origin = null;
    _marquee.value = null;
    if ((e.buttons & kPrimaryButton) == 0 || !isAdditiveCalendarClick()) return;
    // Only from empty space: a press on a chip toggles that chip instead.
    if (_chipRects().values.any((r) => r.contains(e.position))) return;
    _origin = e.position;
    _moved = false;
  }

  void _move(PointerMoveEvent e) {
    final o = _origin;
    if (o == null) return;
    if (!_moved && (e.position - o).distance < 4) return;
    _moved = true;
    _marquee.value = Rect.fromPoints(o, e.position);
  }

  void _up(PointerEvent e) {
    final rect = _marquee.value;
    final o = _origin;
    _origin = null;
    _marquee.value = null;
    if (o == null || rect == null || e is PointerCancelEvent) return;
    final hit = {
      for (final c in _chipRects().entries)
        if (c.value.overlaps(rect)) c.key,
    };
    if (hit.isEmpty) return;
    setCalendarSelection(ref, {...ref.read(calendarSelectionProvider), ...hit});
  }

  @override
  Widget build(BuildContext context) {
    final start = widget.start;
    final dayCount = widget.dayCount;
    final dayWidth = widget.dayWidth;
    final items = widget.items;
    final running = widget.running;
    final g = context.glass;
    final line = _softLine(context);
    final byDay = <int, List<ActionListItem>>{};
    for (final a in items) {
      if (!a.isAllDay || a.startAt == null) continue;
      final d = dayIndexOf(a.startAt!, start);
      if (d >= 0 && d < dayCount) byDay.putIfAbsent(d, () => []).add(a);
    }
    final cross = ref.read(_crossDragProvider)
      ..stripDayWidth = dayWidth
      ..stripDayCount = dayCount;
    final showIcons = ref.watch(calendarIconsProvider);
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      key: cross.stripKey,
      constraints: const BoxConstraints(minHeight: 30, maxHeight: 96),
      decoration: BoxDecoration(
        // A slightly tinted translucent band.
        color: g.border.withValues(alpha: g.dark ? 0.06 : 0.35),
        border: Border(bottom: BorderSide(color: line)),
      ),
      child: SingleChildScrollView(
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: _down,
          onPointerMove: _move,
          onPointerUp: _up,
          onPointerCancel: _up,
          child: Stack(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: _kGutter,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8, left: 6),
                      child: Text(
                        'all-day',
                        style: TextStyle(fontSize: 10, color: g.textSecondary),
                      ),
                    ),
                  ),
                  for (var i = 0; i < dayCount; i++)
                    // Only the cell's tint listens to the drag target; the
                    // chips are passed as a prebuilt child.
                    ValueListenableBuilder<int?>(
                      valueListenable: cross.stripTarget,
                      child: Column(
                        children: [
                          for (final a in byDay[i] ?? const <ActionListItem>[])
                            _AllDayChip(
                              key: ValueKey('allday-${a.id}'),
                              item: a,
                              running: running.contains(a.id),
                              showIcons: showIcons,
                            ),
                        ],
                      ),
                      builder: (context, target, chips) => Container(
                        key: ValueKey('strip-cell-$i'),
                        width: dayWidth,
                        constraints: const BoxConstraints(minHeight: 30),
                        padding: const EdgeInsets.fromLTRB(2, 3, 2, 3),
                        decoration: BoxDecoration(
                          color: target == i
                              ? primary.withValues(alpha: 0.22)
                              : null,
                        ),
                        child: chips,
                      ),
                    ),
                ],
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: ListenableBuilder(
                    listenable: _marquee,
                    builder: (context, _) {
                      final r = _marquee.value;
                      if (r == null) return const SizedBox.shrink();
                      final box = context.findRenderObject() as RenderBox;
                      final primary = Theme.of(context).colorScheme.primary;
                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned.fromRect(
                            key: const ValueKey('marquee-allday'),
                            rect: Rect.fromPoints(
                              box.globalToLocal(r.topLeft),
                              box.globalToLocal(r.bottomRight),
                            ),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: primary.withValues(alpha: 0.15),
                                border: Border.all(
                                  color: primary.withValues(alpha: 0.8),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Chip padding (2 px each side) and the badge's 2 px right offset.
const _kBadgeChrome = 6.0;

/// The most a block's badge may take: its width minus the label padding, and
/// for a one-line label only half of it (the name needs the rest).
double _badgeMaxWidth(double blockWidth, double blockHeight) {
  final room = math.max(0.0, blockWidth - 12 - _kBadgeChrome);
  return blockHeight < 26 ? room * 0.5 : room;
}

/// The small translucent chip behind a badge so it stays readable over text.
class _DirectionChip extends StatelessWidget {
  final Color color;
  final Widget child;
  const _DirectionChip({required this.color, required this.child});

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.85),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: child,
    ),
  );
}

class _AllDayChip extends ConsumerWidget {
  final ActionListItem item;
  final bool running;
  final bool showIcons;

  const _AllDayChip({
    super.key,
    required this.item,
    required this.running,
    required this.showIcons,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    CalendarPerfCounters.chipBuilds++;
    final scheme = Theme.of(context).colorScheme;
    final done = item.isDoneBefore;
    // Only the quantised colour position matters, so the once-a-minute urgency
    // refresh rebuilds a chip only when its colour visibly changes.
    final key = running
        ? null
        : ref.watch(
            actionUrgencyProvider.select(
              (m) => m[item.id] == null ? null : urgencyKey(m[item.id]!),
            ),
          );
    final dark = Theme.of(context).brightness == Brightness.dark;
    final rc = runningColors(dark: dark);
    // No growth direction: white, "fill me in" (running keeps its colour).
    final unlinked =
        !running &&
        ref.watch(
          actionsWithDirectionsProvider.select(
            (s) => s != null && !s.contains(item.id),
          ),
        );
    final ec = unlinked ? emptyColors(dark: dark, done: done) : null;
    // Done chips keep their colour, muted.
    final uc = key == null
        ? null
        : done
        ? urgencyColorsMutedForKey(key, dark: dark)
        : urgencyColorsForKey(key, dark: dark);
    final bg = running
        ? rc.bg
        : ec?.bg ??
              uc?.bg ??
              (done
                  ? scheme.surfaceContainerHighest
                  : scheme.tertiaryContainer);
    final fg = running
        ? rc.fg
        : ec?.fg ??
              uc?.fg ??
              (done ? scheme.onSurfaceVariant : scheme.onTertiaryContainer);
    final selected = ref.watch(
      calendarSelectionProvider.select((s) => s.contains(item.id)),
    );
    final cross = ref.read(_crossDragProvider);
    final icons = showIcons
        ? ref.watch(actionDirectionIconsProvider.select((m) => m[item.id]))
        : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: _HoverToolbarHost(
        actionId: item.id,
        scrolling: cross.scrolling,
        child: Listener(
          onPointerDown: (e) {
            _onPress(ref, item.id, e, phone: usePhoneLayout(context));
            cross.press(item, e);
          },
          // A press that travels becomes a drag towards the time grid.
          onPointerMove: (e) => cross.move(e.position),
          onPointerUp: (_) {
            cross.release();
            _onRelease(ref, item.id);
          },
          child: Material(
            color: bg,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: selected
                  ? BorderSide(color: scheme.onSurface, width: 2)
                  : BorderSide(color: urgencyOutline(bg, dark: dark)),
            ),
            child: _HoldToSelect(
              enabled: usePhoneLayout(context),
              onSelect: () => _phoneSelect(ref, item.id),
              child: InkWell(
              borderRadius: BorderRadius.circular(10),
              // Selection happens on press (see [_onPress]); double-click edits.
              // On a phone a tap opens the editor.
              onTap: usePhoneLayout(context)
                  ? () => _phoneTap(context, ref, item.id)
                  : () {},
              onDoubleTap: usePhoneLayout(context)
                  ? null
                  : () => openActionEditor(context, ref, item.id),
              child: Container(
                height: 18,
                width: double.infinity,
                padding: const EdgeInsets.only(left: 2, right: 6),
                alignment: Alignment.centerLeft,
                child: Row(
                  children: [
                    RoundCheck(
                      key: ValueKey('chip-check-${item.id}'),
                      value: done,
                      color: fg,
                      checkColor: bg,
                      onTap: () => runUndoableToggleDone(context, ref, item.id),
                    ),
                    const SizedBox(width: 2),
                    Expanded(
                      child: Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          color: fg,
                          decoration: done ? TextDecoration.lineThrough : null,
                        ),
                      ),
                    ),
                    if (icons != null) ...[
                      const SizedBox(width: 3),
                      _HideWhileScrolling(
                        scrolling: cross.scrolling,
                        keepSpace: true,
                        child: _CountedBadge(
                          actionId: item.id,
                          icons: icons,
                          maxCount: 4, // the chip's width is shared with its name
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---- hover toolbar --------------------------------------------------------

/// Wraps [child] so hovering it shows a Start / Finish / +7 days toolbar in
/// the root overlay (so it can overflow a tiny block and is never clipped by
/// the scroll view). The toolbar overlaps the child by a few px and hover is
/// the OR of "over child" and "over toolbar", so moving between the two does
/// not flicker.
class _HoverToolbarHost extends ConsumerStatefulWidget {
  final String actionId;
  final bool suppressed;
  final Widget child;

  /// While true the toolbar is neither shown nor hidden (a parked pointer
  /// under a scrolling grid keeps entering/leaving blocks); it re-syncs to
  /// the real hover state when this turns false.
  final ValueListenable<bool>? scrolling;

  const _HoverToolbarHost({
    required this.actionId,
    required this.child,
    this.suppressed = false,
    this.scrolling,
  });

  @override
  ConsumerState<_HoverToolbarHost> createState() => _HoverToolbarHostState();
}

class _HoverToolbarHostState extends ConsumerState<_HoverToolbarHost> {
  final _portal = OverlayPortalController();
  bool _overChild = false;
  bool _overBar = false;

  void _sync() {
    if (!mounted) return;
    if (widget.scrolling?.value ?? false) return; // re-synced when it ends
    final show = _overChild || _overBar;
    if (show && !_portal.isShowing) {
      CalendarPerfCounters.toolbarShows++;
      _portal.show();
    } else if (!show && _portal.isShowing) {
      _portal.hide();
    }
  }

  void _scrollingChanged() {
    if (!mounted) return;
    if (widget.scrolling?.value ?? false) {
      // Scroll start: hide the bar (it is not repositioned per tick); it comes
      // back through _sync once the scroll settles.
      _overBar = false;
      if (_portal.isShowing) _portal.hide();
    } else {
      _sync();
    }
  }

  @override
  void initState() {
    super.initState();
    widget.scrolling?.addListener(_scrollingChanged);
  }

  @override
  void dispose() {
    widget.scrolling?.removeListener(_scrollingChanged);
    super.dispose();
  }

  @override
  void didUpdateWidget(_HoverToolbarHost old) {
    super.didUpdateWidget(old);
    if (old.scrolling != widget.scrolling) {
      old.scrolling?.removeListener(_scrollingChanged);
      widget.scrolling?.addListener(_scrollingChanged);
    }
    if (widget.suppressed) _overBar = false; // its region is being removed
  }

  Future<void> _run(
    String description,
    Future<void> Function(ActionService) op,
  ) => runUndoable(
    context,
    ref,
    widget.actionId,
    description,
    () => op(ref.read(actionServiceProvider)),
  );

  /// The trash deletes the whole selection when this event is part of a
  /// multi-selection, else just this event.
  void _delete() {
    final sel = ref.read(calendarSelectionProvider);
    if (sel.length > 1 && sel.contains(widget.actionId)) {
      final ids = {...sel};
      clearCalendarSelection(ref);
      runUndoableDeleteMany(context, ref, ids);
    } else {
      deselectCalendarEvent(ref, widget.actionId);
      runUndoableDelete(context, ref, widget.actionId);
    }
  }

  /// The child's top-right corner in overlay coordinates, read fresh from the
  /// render tree (a scroll moves the child without a new layout callback), or
  /// null while it is off-screen: its top edge above the enclosing scroll
  /// viewport (the bar would otherwise be pinned over the header), or the
  /// whole child below the viewport.
  Offset? _cornerIfVisible(Size childSize) {
    final box = context.findRenderObject();
    final overlay = Overlay.maybeOf(context)?.context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    final ancestor = overlay is RenderBox ? overlay : null;
    final corner = box.localToGlobal(
      Offset(childSize.width, 0),
      ancestor: ancestor,
    );
    final viewport = Scrollable.maybeOf(context)?.context.findRenderObject();
    if (viewport is RenderBox && viewport.attached && viewport.hasSize) {
      final top = viewport.localToGlobal(Offset.zero, ancestor: ancestor).dy;
      final bottom = top + viewport.size.height;
      if (corner.dy < top || corner.dy > bottom) return null;
    }
    return corner;
  }

  @override
  Widget build(BuildContext context) {
    return OverlayPortal.overlayChildLayoutBuilder(
      controller: _portal,
      overlayChildBuilder: (_, info) {
        if (widget.suppressed) return const SizedBox.shrink();
        // Positioned (and the top-edge rule checked) when it is built, i.e.
        // at show time; a scroll hides it instead of moving it.
        return _positioned(info.childSize);
      },
      child: MouseRegion(
        onEnter: (_) {
          _overChild = true;
          _sync();
        },
        onExit: (_) {
          _overChild = false;
          _sync();
        },
        child: widget.child,
      ),
    );
  }

  Widget _positioned(Size childSize) {
    // Above the child's top-right corner, overlapping it by 3 px so the
    // pointer never crosses a gap between child and toolbar.
    final corner = _cornerIfVisible(childSize);
    if (corner == null) return const SizedBox.shrink();
    return Positioned(
      left: math.max(0, corner.dx - _kToolbarWidth),
      top: math.max(0, corner.dy - _kToolbarHeight + 3),
      child: MouseRegion(
        onEnter: (_) {
          _overBar = true;
          _sync();
        },
        onExit: (_) {
          _overBar = false;
          _sync();
        },
        child: _Toolbar(
          onStart: () => _run('Started', (s) => s.start(widget.actionId)),
          onFinish: () => _run('Finished', (s) => s.finish(widget.actionId)),
          onContinue: () => runUndoableContinue(context, ref, widget.actionId),
          onWeek: () => _run(
            'Postponed to next week',
            (s) => s.postpone(widget.actionId, PostponeRule.nextWeek),
          ),
          onDelete: _delete,
        ),
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  final VoidCallback onStart;
  final VoidCallback onFinish;
  final VoidCallback onContinue;
  final VoidCallback onWeek;
  final VoidCallback onDelete;

  const _Toolbar({
    required this.onStart,
    required this.onFinish,
    required this.onContinue,
    required this.onWeek,
    required this.onDelete,
  });

  Widget _tile(
    IconData icon,
    GlassHue hue,
    String tooltip,
    VoidCallback onTap,
  ) => GlassIconTile(
    icon: icon,
    hue: hue,
    tooltip: tooltip,
    onTap: onTap,
    size: _kToolTile,
    iconSize: 18,
    hitExtra: _kToolHit,
  );

  @override
  Widget build(BuildContext context) {
    CalendarPerfCounters.toolbarBuilds++;
    // A small static glass pill; the transparent Material is only there so
    // the buttons' ink has something to paint on.
    return GlassSurface(
      strength: 1.6,
      radius: 14,
      child: Material(
        type: MaterialType.transparency,
        child: Padding(
          padding: const EdgeInsets.all(_kToolPad),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _tile(Icons.play_arrow_rounded, GlassHue.blue, 'Start', onStart),
              _tile(Icons.stop_rounded, GlassHue.pink, 'Finish', onFinish),
              _tile(
                continueIconData,
                GlassHue.green,
                'Continue with same action',
                onContinue,
              ),
              _tile(
                Icons.calendar_view_week_rounded,
                GlassHue.blue,
                'Postpone +7 days',
                onWeek,
              ),
              // Kept apart from the everyday buttons so it isn't hit by accident.
              Container(
                width: 1,
                height: 16,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                color: _softLine(context),
              ),
              _tile(
                Icons.delete_outline_rounded,
                GlassHue.error,
                'Delete',
                onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---- time grid ------------------------------------------------------------

/// One drawn piece of a timed action on one day column (an action crossing
/// midnight has one segment per day).
class _Seg {
  final ActionListItem item;
  final int day;
  final DateTime start;
  final DateTime end;
  final bool isStart;
  final bool isEnd;

  /// The action's own "HH:mm–HH:mm" (not this day-slice's), formatted once
  /// per layout instead of on every block build.
  final String timeRange;

  /// Minutes from the day column's top to [start], and the slice's length.
  final double topMin;
  final double lenMin;

  const _Seg(
    this.item,
    this.day,
    this.start,
    this.end,
    this.isStart,
    this.isEnd,
    this.timeRange,
    this.topMin,
    this.lenMin,
  );
}

/// The ids of the events being dragged (null = no drag). Changes only when a
/// drag starts or ends, so the 300 other blocks never hear about drag updates.
typedef _DragFlag = ValueNotifier<Set<String>?>;

/// Rebuilds only when "is [id] among the dragged events" flips. Keyed by id,
/// not by layout object, so it stays right when the layout is recomputed
/// mid-drag (Shift+scroll shifting the range).
class _DragScoped extends StatefulWidget {
  final ValueListenable<Set<String>?> dragged;
  final String id;
  final Widget Function(bool dragging) builder;

  const _DragScoped({
    required this.dragged,
    required this.id,
    required this.builder,
  });

  @override
  State<_DragScoped> createState() => _DragScopedState();
}

class _DragScopedState extends State<_DragScoped> {
  late bool _dragging = _isDragged();

  bool _isDragged() => widget.dragged.value?.contains(widget.id) ?? false;

  @override
  void initState() {
    super.initState();
    widget.dragged.addListener(_changed);
  }

  @override
  void didUpdateWidget(_DragScoped old) {
    super.didUpdateWidget(old);
    if (old.dragged != widget.dragged) {
      old.dragged.removeListener(_changed);
      widget.dragged.addListener(_changed);
    }
    _dragging = _isDragged();
  }

  @override
  void dispose() {
    widget.dragged.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    final now = _isDragged();
    if (now != _dragging) setState(() => _dragging = now);
  }

  @override
  Widget build(BuildContext context) => widget.builder(_dragging);
}

/// A built block and the inputs it was built from; reused while they match.
class _BlockEntry {
  final Widget widget;
  final double hourHeight;
  final double dayWidth;
  final bool running;
  final bool done;
  final bool showIcons;

  const _BlockEntry(
    this.widget,
    this.hourHeight,
    this.dayWidth,
    this.running,
    this.done,
    this.showIcons,
  );
}

typedef _Placed = LaneAssignment<_Seg>;

enum _DragKind { move, resizeTop, resizeBottom }

/// A drag in progress. Everything it needs is a snapshot taken when it
/// started (the items, the range it started in), never a reference to a
/// widget or a layout object: Shift+scroll shifts the range mid-drag, which
/// rebuilds the layout and can unmount the block that was grabbed.
class _Drag {
  /// The event under the pointer; it drives the deltas.
  final ActionListItem grabbed;

  /// The screen column [grabbed]'s segment was in, and its lane there.
  final int grabbedColumn;
  final int lane;
  final int laneCount;
  final int span;
  final _DragKind kind;

  /// Everything that moves: [grabbed] first, then (for a move of one of
  /// several selected events) the other selected ones. Resizes act on
  /// [grabbed] alone.
  final List<ActionListItem> members;

  /// The range start when the drag began; the days scrolled since are
  /// `widget.start - originRangeStart`.
  final DateTime originRangeStart;
  final Offset origin;
  final Offset current;

  /// The grid's scroll offset when the drag began (see [dragMinuteDelta]).
  final double originScroll;

  /// True when the grabbed slice is the event's FIRST slice. Only then may an
  /// upward move over the all-day strip turn it into an all-day event: pulling
  /// the second-day slice of a block that started yesterday upwards moves the
  /// block, it must never be converted.
  final bool grabbedIsStart;

  /// The start / end instants of every OTHER timed event, ascending: what the
  /// magnet locks onto ([snapToNeighbours]). A snapshot taken at drag start.
  final List<DateTime> neighbours;

  const _Drag({
    required this.grabbed,
    required this.grabbedColumn,
    required this.lane,
    required this.laneCount,
    required this.span,
    required this.kind,
    required this.members,
    required this.originRangeStart,
    required this.origin,
    required this.current,
    required this.originScroll,
    required this.grabbedIsStart,
    required this.neighbours,
  });

  _Drag at(Offset p) => _Drag(
    grabbed: grabbed,
    grabbedColumn: grabbedColumn,
    lane: lane,
    laneCount: laneCount,
    span: span,
    kind: kind,
    members: members,
    originRangeStart: originRangeStart,
    origin: origin,
    current: p,
    originScroll: originScroll,
    grabbedIsStart: grabbedIsStart,
    neighbours: neighbours,
  );
}

/// One dragged event and the schedule the drag would give it.
typedef _Moved = ({ActionListItem item, CalendarSchedule schedule});

class _TimeGrid extends ConsumerStatefulWidget {
  final DateTime start;
  final int dayCount;
  final double dayWidth;
  final List<ActionListItem> items;
  final Set<String> running;

  const _TimeGrid({
    required this.start,
    required this.dayCount,
    required this.dayWidth,
    required this.items,
    required this.running,
  });

  @override
  ConsumerState<_TimeGrid> createState() => _TimeGridState();
}

class _TimeGridState extends ConsumerState<_TimeGrid> {
  /// Created on the first build, once the viewport height (and so the hour
  /// height) is known, so the initial "an hour before now" offset is right.
  ScrollController? _scrollController;
  ScrollController get _scroll => _scrollController!;
  Timer? _tick;

  /// Drag / drag-to-create state lives in notifiers so a pointer move updates
  /// only the ghost layer, not the grid's 300 blocks.
  final _dragN = ValueNotifier<_Drag?>(null);
  final _newRangeN = ValueNotifier<_NewRange?>(null);
  final _DragFlag _draggedIds = ValueNotifier<Set<String>?>(null);

  /// True from release until the move is written: the drag (and its ghosts)
  /// stay up meanwhile, and range changes must not clear the selection.
  bool _committing = false;
  _Drag? get _drag => _dragN.value;
  _NewRange? get _newRange => _newRangeN.value;

  // Memoized layout (see [_ensureLayout]) and the widgets built from it.
  List<ActionListItem>? _layoutItems;
  DateTime? _layoutStart;
  int _layoutDayCount = 0;
  List<DateTime> _dayStartsMemo = const [];
  List<List<_Placed>> _placedByDay = const [];
  final Map<_Placed, _BlockEntry> _blockCache = {};
  final Map<int, (List<Widget>, Widget)> _columnCache = {};
  Widget? _gutterCache;
  double _gutterHeight = -1;
  Color? _gutterColor;

  /// Pixels per hour at the current zoom: viewport height / visible hours.
  /// Refreshed on every build; everything vertical is measured with it.
  double _hourHeight = kHourHeight;
  double _viewportHeight = 0;

  /// The minute shown at the top of the viewport, as the USER left it. The
  /// grid's hour height follows the viewport height (a keyboard under a dialog
  /// shrinks it), so scroll PIXELS alone would mean another time after the
  /// height returns; this time is what gets restored. Only user scrolling and
  /// zoom update it, never our own restore.
  double? _anchorMinute;
  bool _restoring = false;
  double _lastViewportHeight = 0;
  double get _pxPerMinute => _hourHeight / 60;
  double _px(num minutes) => minutesToPx(minutes, pxPerMinute: _pxPerMinute);

  /// The viewport y that stays put while zooming (the pointer for Ctrl+wheel);
  /// null means the viewport's centre.
  double? _zoomFocal;

  /// Ctrl+wheel distance not yet worth a zoom step (see [_onWheel]).
  double _wheelAccumulated = 0;

  @override
  void initState() {
    super.initState();
    _cross = ref.read(_crossDragProvider)..onChipDrop = _chipDrop;
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  late final _CrossDrag _cross;

  @override
  void dispose() {
    _cross.onChipDrop = null;
    _cross.stripTarget.value = null;
    _stopEdgeTurn();
    _stopScrollTurn();
    _tick?.cancel();
    _settle?.cancel();
    _endMarquee();
    _marqueeN.dispose();
    _dragN.dispose();
    _newRangeN.dispose();
    _unroutePointer();
    _draggedIds.dispose();
    _scrollController?.dispose();
    super.dispose();
  }

  /// Called just before the zoom level changes (so [_hourHeight] is still the
  /// old one): remembers which time sits at the focal point, then after the
  /// next layout scrolls so the same time is still there.
  void _anchorZoom() {
    // A zoom change mid-drag alters px-per-minute under the drag's snapshot:
    // drop the drag instead of moving the block to a wrong time.
    if (_drag != null && !_committing) {
      _unroutePointer();
      _dragCancel();
    }
    final controller = _scrollController;
    if (controller == null || !controller.hasClients) return;
    final focal = (_zoomFocal ?? _viewportHeight / 2).clamp(
      0.0,
      _viewportHeight,
    );
    _zoomFocal = null;
    final minuteAtFocal = (controller.offset + focal) / _pxPerMinute;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !controller.hasClients) return;
      final target = minuteAtFocal * _pxPerMinute - focal;
      controller.jumpTo(target.clamp(0.0, controller.position.maxScrollExtent));
    });
  }

  /// "Today": after the range has re-anchored, scrolls so the now-line sits
  /// at the viewport's vertical centre (clamped, so near midnight it pins to
  /// the top/bottom edge).
  void _scrollToNow() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final controller = _scrollController;
      if (!mounted || controller == null || !controller.hasClients) return;
      final target = _px(_minutesNow()) - _viewportHeight / 2;
      controller.jumpTo(target.clamp(0.0, controller.position.maxScrollExtent));
    });
  }

  /// Ctrl+wheel zooms (wheel up = in). Registered with the pointer-signal
  /// resolver from *inside* the scroll view, so it wins over the scrollable's
  /// own claim on the same event and the grid doesn't also scroll.
  void _onWheel(PointerSignalEvent event) {
    if (event is! PointerScrollEvent ||
        !HardwareKeyboard.instance.isControlPressed) {
      return;
    }
    final focalInViewport = event.localPosition.dy - _scroll.offset;
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      _wheelAccumulated += event.scrollDelta.dy;
      final steps = (_wheelAccumulated / _wheelPixelsPerStep).truncate();
      if (steps == 0) return;
      _wheelAccumulated -= steps * _wheelPixelsPerStep;
      for (var i = 0; i < steps.abs(); i++) {
        _zoomFocal = focalInViewport;
        zoomCalendar(ref, steps < 0 ? 1 : -1);
      }
    });
  }

  /// One mouse-wheel notch reports 100; a touchpad's small deltas add up.
  static const _wheelPixelsPerStep = 100.0;

  // ---- two-finger pinch (touch) -------------------------------------------
  // Raw pointers (no gesture recognizer, so one finger still scrolls and
  // long-press-drags exactly as before). Each time the fingers have moved
  // apart / together by ~30% the zoom steps one level and the baseline resets.
  final _pinchPointers = <int, Offset>{};
  double _pinchBase = 0;
  bool _pinching = false;

  double _pinchDistance() {
    final p = _pinchPointers.values.toList();
    return (p[0] - p[1]).distance;
  }

  void _pinchDown(PointerDownEvent e) {
    if (e.kind != PointerDeviceKind.touch) return;
    _pinchPointers[e.pointer] = e.localPosition;
    if (_pinchPointers.length == 2) {
      _pinchBase = _pinchDistance();
      if (!_pinching) setState(() => _pinching = true);
    }
  }

  void _pinchMove(PointerMoveEvent e) {
    if (!_pinchPointers.containsKey(e.pointer)) return;
    _pinchPointers[e.pointer] = e.localPosition;
    if (_pinchPointers.length != 2 || _pinchBase < 24) return;
    final ratio = _pinchDistance() / _pinchBase;
    if (ratio > 1.3 || ratio < 0.77) {
      final p = _pinchPointers.values.toList();
      _zoomFocal = (p[0].dy + p[1].dy) / 2 - _scroll.offset;
      zoomCalendar(ref, ratio > 1 ? 1 : -1);
      _pinchBase = _pinchDistance();
    }
  }

  void _pinchEnd(PointerEvent e) {
    if (_pinchPointers.remove(e.pointer) == null) return;
    if (_pinchPointers.length < 2 && _pinching) {
      setState(() => _pinching = false);
    }
  }

  /// Day segments + lane packing, recomputed only when the items list
  /// instance, the range start or the day count change - never on selection,
  /// hover, drag, zoom or clock ticks.
  void _ensureLayout() {
    if (identical(_layoutItems, widget.items) &&
        _layoutStart == widget.start &&
        _layoutDayCount == widget.dayCount) {
      return;
    }
    _layoutItems = widget.items;
    _layoutStart = widget.start;
    _layoutDayCount = widget.dayCount;
    _dayStartsMemo = [
      for (var i = 0; i <= widget.dayCount; i++)
        calendarAddDays(widget.start, i),
    ];
    final placed = _layout(_dayStartsMemo);
    _placedByDay = [for (var d = 0; d < widget.dayCount; d++) <_Placed>[]];
    for (final p in placed) {
      _placedByDay[p.event.day].add(p);
    }
    _blockCache.clear();
    _columnCache.clear();
  }

  List<_Placed> _layout(List<DateTime> dayStarts) {
    CalendarPerfCounters.layoutRuns++;
    final byDay = <int, List<_Seg>>{};
    for (final a in widget.items) {
      if (a.isAllDay || a.startAt == null) continue;
      final s = a.startAt!;
      final e = _effectiveEnd(a);
      final range = '${_hhmm(s)}–${_hhmm(_realEnd(a))}';
      for (var d = 0; d < widget.dayCount; d++) {
        final ds = dayStarts[d];
        final de = dayStarts[d + 1];
        if (!s.isBefore(de) || !e.isAfter(ds)) continue;
        final segStart = s.isAfter(ds) ? s : ds;
        final segEnd = e.isBefore(de) ? e : de;
        byDay
            .putIfAbsent(d, () => [])
            .add(
              _Seg(
                a,
                d,
                segStart,
                segEnd,
                !s.isBefore(ds),
                !e.isAfter(de),
                range,
                segStart.difference(ds).inSeconds / 60,
                segEnd.difference(segStart).inSeconds / 60,
              ),
            );
      }
    }
    return [
      for (final segs in byDay.values)
        ...packLanes<_Seg>(segs, startOf: (s) => s.start, endOf: (s) => s.end),
    ];
  }

  // -- drag handling --
  //
  // Once a drag has started it no longer depends on the block that was
  // grabbed: that block's widgets can be rebuilt or unmounted when Shift+scroll
  // shifts the range mid-drag, which would cancel its gesture recognizer. So
  // moves, release and cancel come from a global pointer route registered at
  // the start, and the block only starts the drag.

  bool _routed = false;

  void _routePointer() {
    if (_routed) return;
    _routed = true;
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
  }

  void _unroutePointer() {
    if (!_routed) return;
    _routed = false;
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
  }

  void _onPointer(PointerEvent e) {
    if (e is PointerMoveEvent) {
      _dragUpdate(e.position);
    } else if (e is PointerUpEvent) {
      _unroutePointer();
      _dragEnd();
    } else if (e is PointerCancelEvent) {
      _unroutePointer();
      _dragCancel();
    }
  }

  void _dragStart(_Placed p, _DragKind kind, Offset pos) {
    if (_drag != null) return;
    _pressDragged = true;
    final grabbed = p.event.item;
    final members = <ActionListItem>[grabbed];
    if (kind == _DragKind.move) {
      // Dragging one of several selected events moves them all.
      final sel = ref.read(calendarSelectionProvider);
      if (sel.length > 1 && sel.contains(grabbed.id)) {
        for (final a in widget.items) {
          if (a.id != grabbed.id && sel.contains(a.id) && a.startAt != null) {
            members.add(a);
          }
        }
      }
    }
    _draggedIds.value = {for (final m in members) m.id};
    // The edges of every other timed event, for the magnet.
    final memberIds = {for (final m in members) m.id};
    // The magnet: a phone always has it, a desktop only for a RIGHT-button drag
    // (the left button moves in plain 10-minute steps).
    final magnetOn = usePhoneLayout(context) || _pressSecondary;
    final edges = <DateTime>{};
    for (final a in widget.items) {
      if (!magnetOn) break;
      if (a.isAllDay || a.startAt == null || memberIds.contains(a.id)) continue;
      edges
        ..add(a.startAt!)
        ..add(_effectiveEnd(a));
    }
    final sortedEdges = edges.toList()..sort();
    _dragN.value = _Drag(
      grabbed: grabbed,
      grabbedColumn: p.event.day,
      lane: p.lane,
      laneCount: p.laneCount,
      span: p.span,
      kind: kind,
      members: members,
      originRangeStart: widget.start,
      origin: pos,
      current: pos,
      originScroll: _scrollOffsetNow,
      grabbedIsStart: p.event.isStart,
      neighbours: sortedEdges,
    );
    _cross.gridDragging = true;
    _routePointer();
  }

  Timer? _edgeTimer;
  int _edgeDir = 0;

  /// Holding the dragged block near the left/right edge turns the visible range
  /// one day after a short hold, again and again while it stays there (so a
  /// block can be carried further than the 1-7 days on screen, also on a phone).
  void _edgeTurn(Offset pos) {
    final box = context.findRenderObject();
    var dir = 0;
    final d = _drag;
    final travelled = d != null && (pos - d.origin).distance >= _kEdgeTravel;
    if (travelled && box is RenderBox && box.attached && box.hasSize) {
      final x = box.globalToLocal(pos).dx;
      if (x < _kGutter + _kEdgeZone) {
        dir = -1;
      } else if (x > box.size.width - _kEdgeZone) {
        dir = 1;
      }
    }
    if (dir == _edgeDir) return;
    _edgeDir = dir;
    _edgeTimer?.cancel();
    _edgeTimer = null;
    if (dir == 0) return;
    _edgeTimer = Timer(_kEdgeHold, () {
      if (!mounted || _drag == null) return;
      shiftCalendarDays(ref, dir);
      _edgeTimer = Timer.periodic(_kEdgeHold, (_) {
        if (!mounted || _drag == null) {
          _edgeTimer?.cancel();
          return;
        }
        shiftCalendarDays(ref, dir);
      });
    });
  }

  void _stopEdgeTurn() {
    _edgeTimer?.cancel();
    _edgeTimer = null;
    _edgeDir = 0;
  }

  Timer? _scrollTimer;
  int _scrollDir = 0;

  /// Holding a dragged block within [_kScrollEdge] px of the grid's top or
  /// bottom scrolls the grid, so a block can be carried (or its edge pulled)
  /// across midnight and further than the screen shows. The preview already
  /// adds the grid's scroll since the drag began, and [_onScrolled] re-derives
  /// it, so nothing else is needed.
  void _scrollTurn(Offset pos) {
    final box = context.findRenderObject();
    var dir = 0;
    if (box is RenderBox && box.attached && box.hasSize) {
      final y = box.globalToLocal(pos).dy;
      if (y < _kScrollEdge) {
        dir = -1;
      } else if (y > box.size.height - _kScrollEdge) {
        dir = 1;
      }
    }
    if (dir == _scrollDir) return;
    _scrollDir = dir;
    _scrollTimer?.cancel();
    _scrollTimer = null;
    if (dir == 0) return;
    _scrollTimer = Timer.periodic(const Duration(milliseconds: 30), (t) {
      if (!mounted || _drag == null || _scrollController?.hasClients != true) {
        t.cancel();
        return;
      }
      final p = _scroll.position;
      final next = (p.pixels + dir * _kScrollStep).clamp(
        p.minScrollExtent,
        p.maxScrollExtent,
      );
      if (next != p.pixels) _scroll.jumpTo(next);
    });
  }

  void _stopScrollTurn() {
    _scrollTimer?.cancel();
    _scrollTimer = null;
    _scrollDir = 0;
  }

  /// The neighbour edge the preview locked onto (drawn as a guide line).
  DateTime? _snapAt;

  void _dragUpdate(Offset pos) {
    final d = _drag;
    if (d == null || _committing) return;
    _edgeTurn(pos);
    _scrollTurn(pos);
    // A timed block dragged up over the all-day strip highlights that day
    // (only for the event's first slice, see [_Drag.grabbedIsStart]).
    if (d.kind == _DragKind.move && d.grabbedIsStart) {
      _cross.stripTarget.value = _cross.stripDayAt(
        pos,
        widget.dayWidth,
        widget.dayCount,
      );
    }
    _dragN.value = d.at(pos);
  }

  /// The grid cell under a global [pos]: (day column, snapped minute of day),
  /// or null outside the grid's viewport / day columns. Uses the scroll offset
  /// and [_pxPerMinute], so it is right at any zoom and scroll.
  (int, int)? _gridCellAt(Offset pos) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    final local = box.globalToLocal(pos);
    final x = local.dx - _kGutter;
    if (local.dy < 0 || local.dy > box.size.height) return null;
    if (x < 0 || x >= widget.dayWidth * widget.dayCount) return null;
    final day = (x / widget.dayWidth).floor().clamp(0, widget.dayCount - 1);
    final minutes = pxToMinutes(
      local.dy + _scrollOffsetNow,
      pxPerMinute: _pxPerMinute,
    );
    final snapped = ((minutes / kSnapMinutes).round() * kSnapMinutes).clamp(
      0,
      1440 - kSnapMinutes,
    );
    return (day, snapped);
  }

  /// An all-day chip was dropped: over a grid cell it becomes a timed action
  /// starting there (duration predicted, else 1 h - the service decides).
  void _chipDrop(ActionListItem item, Offset pos) {
    final stripDay = _cross.stripDayAt(pos, widget.dayWidth, widget.dayCount);
    if (stripDay != null) {
      _chipDropOnStrip(item, stripDay);
      return;
    }
    final cell = _gridCellAt(pos);
    if (cell == null) return;
    final start = calendarAddDays(
      widget.start,
      cell.$1,
    ).add(Duration(minutes: cell.$2));
    runUndoableScheduleAllDayAt(context, ref, item.id, start);
  }

  /// An all-day chip dropped on another day's strip cell: it (and the rest of
  /// the selection, when it is part of one) moves by whole days; all-day
  /// members keep having no end, timed ones keep their time of day. The done
  /// flag and all-day flag are untouched. One Undo restores everything.
  void _chipDropOnStrip(ActionListItem item, int day) {
    final from = item.startAt == null
        ? null
        : dayIndexOf(item.startAt!, widget.start);
    if (from == null || from == day) return;
    final dayDelta = day - from;
    final members = <ActionListItem>[item];
    final sel = ref.read(calendarSelectionProvider);
    if (sel.length > 1 && sel.contains(item.id)) {
      for (final a in widget.items) {
        if (a.id != item.id && sel.contains(a.id) && a.startAt != null) {
          members.add(a);
        }
      }
    }
    final changes = <ScheduleChange>[];
    for (final m in members) {
      final s = movedSchedule(
        startAt: m.startAt!,
        endAt: m.endAt,
        dayDelta: dayDelta,
        minuteDelta: 0,
        legacyEstimatedMinutes: m.estimatedMinutes,
      );
      final endAt = m.isAllDay && m.endAt == null ? null : s.endAt;
      changes.add(ScheduleChange(m.id, startAt: s.startAt, endAt: endAt));
    }
    runUndoableMoveMany(
      context,
      ref,
      changes,
      description: changes.length == 1
          ? 'Moved'
          : 'Moved ${changes.length} events',
    );
  }

  void _clearDrag() {
    _stopEdgeTurn();
    _stopScrollTurn();
    _snapAt = null;
    _cross.gridDragging = false;
    _cross.stripTarget.value = null;
    _dragN.value = null;
    _draggedIds.value = null;
    _committing = false;
  }

  void _dragCancel() => _clearDrag();

  /// The schedules the pending drag would produce: the grabbed event drives
  /// the deltas (10-minute snap vertically, whole days horizontally) and every
  /// other member gets the same ones. The day delta counts the days scrolled
  /// since the drag began, so it is the date under the pointer that decides.
  List<_Moved> _preview(_Drag d) {
    final item = d.grabbed;
    final start = item.startAt!;
    final dx = d.current.dx - d.origin.dx;
    // Pointer travel + the grid's own scroll since the drag began: a wheel
    // turning mid-drag must carry the block along.
    final latticeMinutes = dragMinuteDelta(
      d.current.dy - d.origin.dy,
      _scrollOffsetNow - d.originScroll,
      pxPerMinute: _pxPerMinute,
    );
    // Where the pointer really is (the magnet looks at this, not the lattice).
    final rawMinutes = rawMinuteDelta(
      d.current.dy - d.origin.dy,
      _scrollOffsetNow - d.originScroll,
      pxPerMinute: _pxPerMinute,
    );

    final scrolled = dayIndexOf(widget.start, d.originRangeStart);
    final column = (d.grabbedColumn + (dx / widget.dayWidth).round()).clamp(
      0,
      widget.dayCount - 1,
    );
    final dayDelta = scrolled + column - d.grabbedColumn;

    // The magnet works only when the drag has neighbour edges (see _dragStart).
    const magnet = true;
    // A one-day block normally stays inside its day; once the grid has been
    // scrolled by an hour or more during the drag (held at the edge) it may be
    // carried across midnight.
    final carried =
        (_scrollOffsetNow - d.originScroll).abs() >= _pxPerMinute * 60;
    _snapAt = null;

    // The schedules for a vertical travel of [minutes]; [useMagnet] lets the
    // result lock onto another event's edge.
    List<_Moved> build(int minutes, bool useMagnet) {
      switch (d.kind) {
        case _DragKind.move:
          // Each member has its OWN limit: a block that fits inside one day stays
          // inside it (the day itself is changed sideways), but one that crosses
          // midnight (a sleep, 23:00 -> 07:00) moves freely, so it can be
          // dragged up and down too; its end may land later on the next day.
          int minutesFor(ActionListItem m) {
            if (m.isAllDay) return 0;
            final s = m.startAt!;
            final dur = _effectiveEnd(m).difference(s).inMinutes;
            final sm = minutesOfDay(s);
            if (carried || dur > 1440 - sm) return minutes; // crosses midnight
            return minutes.clamp(-sm, 1440 - sm - dur);
          }

          final moved = [
            for (final m in d.members)
              (
                item: m,
                schedule: movedSchedule(
                  startAt: m.startAt!,
                  endAt: m.endAt,
                  dayDelta: dayDelta,
                  // All-day chips follow the day delta only.
                  minuteDelta: minutesFor(m),
                  legacyEstimatedMinutes: m.estimatedMinutes,
                ),
              ),
          ];
          if (!useMagnet || item.isAllDay || d.neighbours.isEmpty) return moved;
          // The grabbed block drives the magnet; the others shift with it.
          final snap = snapToNeighbours(
            schedule: moved.first.schedule,
            moveWhole: true,
            neighbourEdges: d.neighbours,
            pxPerMinute: _pxPerMinute,
          );
          if (snap.snappedTo == null) return moved;
          _snapAt = snap.snappedTo;
          final shift = snap.schedule.startAt.difference(
            moved.first.schedule.startAt,
          );
          return [
            for (final m in moved)
              m.item.isAllDay
                  ? m
                  : (
                      item: m.item,
                      schedule: (
                        startAt: m.schedule.startAt.add(shift),
                        endAt: m.schedule.endAt.add(shift),
                      ),
                    ),
          ];
        case _DragKind.resizeTop:
        case _DragKind.resizeBottom:
          // The edge may cross days: the horizontal distance picks the day, the
          // vertical one the minutes; the 10-minute floor is in resizedSchedule.
          var resized = resizedSchedule(
            startAt: start,
            endAt: item.endAt,
            fromTop: d.kind == _DragKind.resizeTop,
            dayDelta: dayDelta,
            minuteDelta: minutes,
            legacyEstimatedMinutes: item.estimatedMinutes,
          );
          if (useMagnet && d.neighbours.isNotEmpty) {
            final snap = snapToNeighbours(
              schedule: resized,
              moveWhole: false,
              movedEdgeIsStart: d.kind == _DragKind.resizeTop,
              neighbourEdges: d.neighbours,
              pxPerMinute: _pxPerMinute,
            );
            resized = snap.schedule;
            _snapAt = snap.snappedTo;
          }
          return [(item: item, schedule: resized)];
      }
    }

    if (magnet && d.neighbours.isNotEmpty) {
      final snapped = build(rawMinutes, true);
      if (_snapAt != null) return snapped;
    }
    return build(latticeMinutes, false);
  }

  Future<void> _dragEnd() async {
    final d = _drag;
    if (d == null || _committing) return;
    final stripDay = d.kind == _DragKind.move ? _cross.stripTarget.value : null;
    if (stripDay != null) {
      await _dropOnStrip(d, stripDay);
      return;
    }
    final changes = <ScheduleChange>[];
    for (final m in _preview(d)) {
      final item = m.item;
      final s = m.schedule;
      // An all-day action without an end keeps having none.
      final endAt = item.isAllDay && item.endAt == null ? null : s.endAt;
      final unchanged =
          s.startAt == item.startAt &&
          (endAt == item.endAt ||
              (item.endAt == null && s.endAt == _effectiveEnd(item)));
      if (!unchanged) {
        changes.add(ScheduleChange(item.id, startAt: s.startAt, endAt: endAt));
      }
    }
    if (changes.isEmpty) {
      _clearDrag();
      return;
    }
    _committing = true;
    // Events dragged out of the visible range leave the selection, so a later
    // Delete can't hit something that isn't on screen.
    final lo = _dayStartsMemo.first;
    final hi = _dayStartsMemo.last;
    final away = {
      for (final c in changes)
        if (!(c.startAt!.isBefore(hi) &&
            (c.endAt == null
                ? !c.startAt!.isBefore(lo)
                : c.endAt!.isAfter(lo))))
          c.id,
    };
    if (away.isNotEmpty) {
      setCalendarSelection(
        ref,
        {...ref.read(calendarSelectionProvider)}..removeAll(away),
      );
    }
    final resizing = d.kind != _DragKind.move;
    try {
      await runUndoableMoveMany(
        context,
        ref,
        changes,
        description: resizing
            ? 'Resized'
            : changes.length == 1
            ? 'Moved'
            : 'Moved ${changes.length} events',
      );
    } finally {
      if (mounted) _clearDrag();
    }
  }

  /// Timed blocks dropped on the all-day strip's day cell become all-day
  /// there (one Undo restores their times and the flag). A group drag turns
  /// every timed member all-day; members that already are all-day stay put.
  Future<void> _dropOnStrip(_Drag d, int day) async {
    final timed = [
      for (final m in d.members)
        if (!m.isAllDay) m,
    ];
    if (timed.isEmpty) {
      _clearDrag();
      return;
    }
    _committing = true;
    final dayStart = calendarAddDays(widget.start, day);
    try {
      if (timed.length == 1) {
        await runUndoableMakeAllDay(
          context,
          ref,
          timed.single.id,
          _local(dayStart),
        );
      } else {
        await runUndoableMoveMany(context, ref, [
          for (final m in timed)
            ScheduleChange(
              m.id,
              startAt: dayStart,
              endAt: null,
              isAllDay: true,
            ),
        ], description: 'Made ${timed.length} events all-day');
      }
    } finally {
      if (mounted) _clearDrag();
    }
  }

  // -- build --

  @override
  Widget build(BuildContext context) {
    final visibleHours = ref.watch(calendarVisibleHoursProvider);
    _showIcons = ref.watch(calendarIconsProvider);
    ref.listen<int>(calendarVisibleHoursProvider, (_, _) => _anchorZoom());
    // Moving to other days clears the selection - except while dragging,
    // where Shift+scroll shifts the range on purpose.
    void clearOnRangeChange(Object? _, Object? _) {
      if (_drag == null && !_committing) clearCalendarSelection(ref);
    }

    ref.listen<int>(calendarScrollToNowProvider, (_, _) => _scrollToNow());
    ref.listen<DateTime>(calendarRangeStartProvider, clearOnRangeChange);
    ref.listen<int>(calendarDayCountProvider, clearOnRangeChange);
    // A refresh drops selected ids that no longer exist (deleted or moved away).
    ref.listen<AsyncValue<List<ActionListItem>>>(calendarRangeProvider, (
      _,
      next,
    ) {
      final sel = ref.read(calendarSelectionProvider);
      final items = next.value;
      if (sel.isEmpty || items == null || next.isLoading) return;
      if (_drag != null || _committing) return;
      final present = {for (final a in items) a.id};
      if (!present.containsAll(sel)) {
        setCalendarSelection(ref, sel.intersection(present));
      }
    });

    return LayoutBuilder(
      builder: (context, box) {
        _viewportHeight = box.maxHeight;
        _hourHeight = math.max(_kMinHourHeight, box.maxHeight / visibleHours);
        if (_scrollController == null) {
          // The red now-line in the vertical centre (the Now button does the
          // same); near midnight it pins to the top/bottom edge.
          final initial = math.max(0.0, _px(_minutesNow()) - box.maxHeight / 2);
          _anchorMinute = initial / _pxPerMinute;
          _scrollController = ScrollController(initialScrollOffset: initial)
            ..addListener(_onScrolled);
          // The first layout may clamp the initial offset; re-sync then.
          WidgetsBinding.instance.addPostFrameCallback((_) => _onScrolled());
        }
        // The viewport got taller/shorter (keyboard, rotation): keep the TIME
        // the user was looking at, not the raw pixels.
        final heightChanged =
            _lastViewportHeight > 0 &&
            (box.maxHeight - _lastViewportHeight).abs() > 0.5;
        _lastViewportHeight = box.maxHeight;
        final anchor = _anchorMinute;
        if (heightChanged && anchor != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final controller = _scrollController;
            if (!mounted || controller == null || !controller.hasClients) {
              return;
            }
            _restoring = true;
            try {
              controller.jumpTo(
                (anchor * _pxPerMinute).clamp(
                  0.0,
                  controller.position.maxScrollExtent,
                ),
              );
            } finally {
              _restoring = false;
            }
          });
        }
        _updateWindow();
        return _buildGrid(context);
      },
    );
  }

  int _minutesNow() {
    final now = _local(DateTime.now().toUtc());
    return now.hour * 60 + now.minute;
  }

  Widget _buildGrid(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dayW = widget.dayWidth;
    _ensureLayout();
    final dayStarts = _dayStartsMemo;
    final now = DateTime.now().toUtc();
    final todayIdx = dayIndexOf(now, widget.start);
    final gridHeight = _hourHeight * 24;
    final planned = ref.watch(planOccurrencesProvider).value ?? const [];
    if (_columnGeometry != (dayW, gridHeight)) {
      _columnCache.clear();
      _columnGeometry = (dayW, gridHeight);
    }

    final children = <Widget>[
      Positioned.fill(
        // Empty grid space: a click clears the selection, a drag sweeps out a
        // time range for a new action. Events sit above and take their own
        // gestures.
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          dragStartBehavior: DragStartBehavior.down,
          onTapDown: (_) {
            if (!isAdditiveCalendarClick()) clearCalendarSelection(ref);
          },
          // A finger must scroll the grid, so on a phone the sweep gesture is
          // replaced by a long-press that makes a one-hour action.
          onPanStart: usePhoneLayout(context) ? null : _createStart,
          onPanUpdate: usePhoneLayout(context) ? null : _createUpdate,
          onPanEnd: usePhoneLayout(context) ? null : (_) => _createEnd(),
          onPanCancel: usePhoneLayout(context) ? null : _createCancel,
          onLongPressStart: usePhoneLayout(context)
              ? (d) => _createHourAt(d.localPosition)
              : null,
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _GridPainter(
                dayCount: widget.dayCount,
                dayWidth: dayW,
                hourHeight: _hourHeight,
                color: _softLine(context),
                todayIndex: todayIdx >= 0 && todayIdx < widget.dayCount
                    ? todayIdx
                    : -1,
                todayTint: scheme.primary.withValues(alpha: 0.05),
              ),
            ),
          ),
        ),
      ),
      // Planning mode: the plan's occurrences as translucent blocks UNDER the
      // real events (the provider is empty, and costs nothing, while it is off).
      if (planned.isNotEmpty)
        Positioned.fill(
          child: PlanGhostLayer(
            firstDay: planDateOf(widget.start),
            dayCount: widget.dayCount,
            dayWidth: dayW,
            hourHeight: _hourHeight,
            phone: usePhoneLayout(context),
            occurrences: planned,
            onEdit: (o) =>
                PlanItemEditorDialog.show(context, itemId: o.planItemId),
            onChanged: (o, start, dur) =>
                applyGhostChange(context, ref, o, start, dur),
          ),
        ),
      for (var d = 0; d < widget.dayCount; d++) _column(d, gridHeight),
      if (todayIdx >= 0 && todayIdx < widget.dayCount)
        Positioned(
          left: todayIdx * dayW,
          width: dayW,
          top: _px(minutesOfDay(now)) - 1,
          height: 2,
          child: IgnorePointer(
            key: const ValueKey('now-line'),
            child: ColoredBox(color: scheme.error),
          ),
        ),
      // Drag ghost and drag-to-create preview: the only things a pointer
      // move rebuilds.
      Positioned.fill(
        child: IgnorePointer(
          child: ListenableBuilder(
            listenable: Listenable.merge([
              _dragN,
              _newRangeN,
              _marqueeN,
              _cross.chip,
              _cross.stripTarget,
            ]),
            builder: (context, _) {
              final drag = _drag;
              final range = _newRange;
              final marquee = _marqueeN.value;
              final chip = _cross.chip.value;
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  // Over the all-day strip the target cell is the feedback.
                  if (drag != null && _cross.stripTarget.value == null)
                    ..._ghosts(drag, dayStarts),
                  if (chip != null) ..._chipGhost(scheme, chip.pos),
                  if (range != null) _createPreview(scheme, range),
                  if (marquee != null)
                    Positioned.fromRect(
                      key: const ValueKey('marquee'),
                      rect: marquee,
                      child: _marqueeBox(scheme),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    ];

    return SingleChildScrollView(
      controller: _scroll,
      // Two fingers pinch-zoom the hours; the grid must not also scroll then.
      physics: _pinching ? const NeverScrollableScrollPhysics() : null,
      child: Listener(
        // Translucent: empty grid space has nothing hit-testable in it, and
        // the wheel must still reach us there.
        behavior: HitTestBehavior.translucent,
        onPointerSignal: _onWheel,
        onPointerDown: _pinchDown,
        onPointerMove: _pinchMove,
        onPointerUp: _pinchEnd,
        onPointerCancel: _pinchEnd,
        child: SizedBox(
          height: gridHeight + 8,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _gutter(context.glass.textSecondary, gridHeight),
              SizedBox(
                width: dayW * widget.dayCount,
                height: gridHeight,
                child: Stack(clipBehavior: Clip.none, children: children),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The hour labels; rebuilt only when the hour height or colour changes.
  Widget _gutter(Color labelColor, double gridHeight) {
    final cached = _gutterCache;
    if (cached != null &&
        _gutterHeight == _hourHeight &&
        _gutterColor == labelColor) {
      return cached;
    }
    _gutterHeight = _hourHeight;
    _gutterColor = labelColor;
    final style = TextStyle(fontSize: 10, color: labelColor);
    return _gutterCache = RepaintBoundary(
      child: SizedBox(
        width: _kGutter,
        height: gridHeight,
        child: Stack(
          children: [
            for (var h = 1; h < 24; h++)
              Positioned(
                top: h * _hourHeight - 7,
                right: 6,
                child: Text('${twoDigits(h)}:00', style: style),
              ),
          ],
        ),
      ),
    );
  }

  /// One day's events in their own repaint boundary. The block widgets are
  /// cached (see [_blockFor]) so a rebuild of the grid hands the framework the
  /// same instances and it skips them.
  Widget _column(int d, double gridHeight) {
    final blocks = [
      for (final p in _placedByDay[d])
        if (_inWindow(p)) _blockFor(p),
    ];
    final cached = _columnCache[d];
    if (cached != null && _sameWidgets(cached.$1, blocks)) return cached.$2;
    final column = Positioned(
      key: ValueKey('day-column-$d'),
      left: d * widget.dayWidth,
      width: widget.dayWidth,
      top: 0,
      height: gridHeight,
      child: RepaintBoundary(
        child: Stack(clipBehavior: Clip.none, children: blocks),
      ),
    );
    _columnCache[d] = (blocks, column);
    return column;
  }

  (double, double)? _columnGeometry;

  // -- vertical windowing --
  //
  // Only blocks within one viewport above/below the visible hours are built;
  // the window moves in half-viewport buckets so scrolling rebuilds the
  // columns rarely, not on every pixel.
  int _winBucket = -1 << 30;
  double _winB = 0;
  double _winLo = double.negativeInfinity;
  double _winHi = double.infinity;

  double get _scrollOffsetNow =>
      _scroll.hasClients ? _scroll.offset : _scroll.initialScrollOffset;

  /// Recomputes the window; true when it moved.
  bool _updateWindow() {
    if (_viewportHeight <= 0) return false;
    final b = _viewportHeight / 2;
    final k = (_scrollOffsetNow / b).floor();
    if (k == _winBucket && b == _winB) return false;
    _winBucket = k;
    _winB = b;
    _winLo = (k - 2) * b;
    _winHi = (k + 5) * b;
    return true;
  }

  double? _lastOffset;
  Timer? _settle;

  void _onScrolled() {
    if (!mounted) return;
    // Hide badges / freeze toolbar hover while the offset is moving; a
    // debounce timer flips it back ~150 ms after the last movement.
    final offset = _scrollOffsetNow;
    final last = _lastOffset;
    _lastOffset = offset;
    if (!_restoring && _pxPerMinute > 0) {
      _anchorMinute = offset / _pxPerMinute;
    }
    if (last != null && last != offset) {
      _cross.scrolling.value = true;
      _settle?.cancel();
      _settle = Timer(_kScrollSettle, () {
        _settle = null;
        _cross.scrolling.value = false;
      });
    }
    // A drag in progress follows the content: re-derive its preview from the
    // last pointer position and the new offset (the pointer itself did not
    // move, so no pointer event will do it).
    final d = _drag;
    if (d != null && !_committing && last != null && last != offset) {
      _dragN.value = d.at(d.current);
    }
    if (_updateWindow()) setState(() {});
  }

  bool _inWindow(_Placed p) {
    final seg = p.event;
    final top = _px(seg.topMin);
    final bottom = top + math.max(_kMinBlockHeight, _px(seg.lenMin));
    return (bottom >= _winLo && top <= _winHi) ||
        (_draggedIds.value?.contains(seg.item.id) ?? false);
  }

  static bool _sameWidgets(List<Widget> a, List<Widget> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!identical(a[i], b[i])) return false;
    }
    return true;
  }

  /// Mirrors [calendarIconsProvider]; set once per build, part of the block
  /// cache key so a flip rebuilds every block exactly once.
  bool _showIcons = false;

  Widget _blockFor(_Placed p) {
    final seg = p.event;
    final running = widget.running.contains(seg.item.id);
    final done = seg.item.isDoneBefore;
    final showIcons = _showIcons;
    final cached = _blockCache[p];
    if (cached != null &&
        cached.showIcons == showIcons &&
        cached.hourHeight == _hourHeight &&
        cached.dayWidth == widget.dayWidth &&
        cached.running == running &&
        cached.done == done) {
      return cached.widget;
    }
    final laneW = widget.dayWidth / p.laneCount;
    final blockW = laneW * p.span - 2;
    final height = math.max(_kMinBlockHeight, _px(seg.lenMin));
    final key = seg.isStart
        ? ValueKey('event-${seg.item.id}')
        : ValueKey('event-${seg.item.id}-d${seg.day}');
    final built = Positioned(
      key: key,
      left: p.lane * laneW,
      top: _px(seg.topMin),
      width: blockW,
      height: height,
      child: _DragScoped(
        dragged: _draggedIds,
        id: seg.item.id,
        builder: (dragging) => _HoverToolbarHost(
          actionId: seg.item.id,
          suppressed: dragging,
          scrolling: _cross.scrolling,
          child: _EventBlock(
            seg: seg,
            height: height,
            width: blockW,
            scrolling: _cross.scrolling,
            running: running,
            showIcons: showIcons,
            dragging: dragging,
            onDragStart: (kind, pos) => _dragStart(p, kind, pos),
            onDragUpdate: _dragUpdate,
          ),
        ),
      ),
    );
    _blockCache[p] = _BlockEntry(
      built,
      _hourHeight,
      widget.dayWidth,
      running,
      done,
      showIcons,
    );
    return built;
  }

  /// One ghost per day slice of every dragged timed event (an event crossing
  /// midnight, e.g. after a cross-day resize, shows a piece in each visible
  /// day), all inside the one ghost layer. The grabbed event keeps its lane
  /// and span; the others are drawn full column width. All-day chips have no
  /// ghost in the grid, and slices outside the visible range are not drawn.
  List<Widget> _ghosts(_Drag drag, List<DateTime> dayStarts) {
    final scheme = Theme.of(context).colorScheme;
    final ghosts = <Widget>[];
    for (final m in _preview(drag)) {
      if (m.item.isAllDay) continue;
      final s = m.schedule;
      // The grabbed block keeps its lane only while it stays on one day; a
      // block crossing midnight is drawn full column width in each day.
      final oneDay =
          dayIndexOf(s.startAt, widget.start) ==
          dayIndexOf(
            s.endAt.subtract(const Duration(seconds: 1)),
            widget.start,
          );
      final grabbed = m.item.id == drag.grabbed.id;
      final useLane = grabbed && oneDay;
      final range = '${_hhmm(s.startAt)} – ${_hhmm(s.endAt)}';
      final laneW = widget.dayWidth / (useLane ? drag.laneCount : 1);
      var first = true;
      for (var day = 0; day < widget.dayCount; day++) {
        final ds = dayStarts[day];
        final de = dayStarts[day + 1];
        if (!s.startAt.isBefore(de) || !s.endAt.isAfter(ds)) continue;
        final from = s.startAt.isAfter(ds) ? s.startAt : ds;
        final to = s.endAt.isBefore(de) ? s.endAt : de;
        final topMin = from.difference(ds).inSeconds / 60;
        final lenMin = to.difference(from).inSeconds / 60;
        final base = grabbed ? 'drag-ghost' : 'drag-ghost-${m.item.id}';
        ghosts.add(
          Positioned(
            key: ValueKey(first ? base : '$base-d$day'),
            left: day * widget.dayWidth + (useLane ? drag.lane : 0) * laneW,
            top: _px(topMin),
            width: laneW * (useLane ? drag.span : 1) - 2,
            height: math.max(_kMinBlockHeight, _px(lenMin)),
            child: _rangeBox(scheme, range),
          ),
        );
        first = false;
      }
    }
    // The magnet locked onto another event's edge: a guide line across its day.
    final snapAt = _snapAt;
    if (snapAt != null) {
      final day = dayIndexOf(snapAt, widget.start);
      if (day >= 0 && day < widget.dayCount) {
        final ds = dayStarts[day];
        ghosts.add(
          Positioned(
            key: const ValueKey('snap-guide'),
            left: day * widget.dayWidth,
            top: _px(snapAt.difference(ds).inSeconds / 60) - 1,
            width: widget.dayWidth,
            height: 2,
            child: IgnorePointer(
              child: ColoredBox(color: scheme.tertiary),
            ),
          ),
        );
      }
    }
    return ghosts;
  }

  /// Ghost of an all-day chip being dragged over the grid: a one-hour block
  /// (the real length is predicted when dropped) at the snapped start.
  List<Widget> _chipGhost(ColorScheme scheme, Offset pos) {
    if (_cross.stripDayAt(pos, widget.dayWidth, widget.dayCount) != null) {
      return const [];
    }
    final cell = _gridCellAt(pos);
    if (cell == null) return const [];
    final (day, minute) = cell;
    final start = calendarAddDays(
      widget.start,
      day,
    ).add(Duration(minutes: minute));
    final end = start.add(const Duration(hours: 1));
    return [
      Positioned(
        key: const ValueKey('chip-ghost'),
        left: day * widget.dayWidth,
        top: _px(minute),
        width: widget.dayWidth - 2,
        height: math.max(_kMinBlockHeight, _px(60)),
        child: _rangeBox(scheme, '${_hhmm(start)} – ${_hhmm(end)}'),
      ),
    ];
  }

  /// The translucent rubber-band rectangle (two solid draw ops).
  Widget _marqueeBox(ColorScheme scheme) => DecoratedBox(
    decoration: BoxDecoration(
      color: scheme.primary.withValues(alpha: 0.15),
      border: Border.all(color: scheme.primary.withValues(alpha: 0.8)),
    ),
  );

  /// The translucent box with the bold white time chip, shared by the
  /// move/resize ghost and the drag-to-create preview.
  Widget _rangeBox(ColorScheme scheme, String range) {
    final g = context.glass;
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: scheme.primary.withValues(alpha: 0.25),
          border: Border.all(color: scheme.primary),
          borderRadius: BorderRadius.circular(8),
        ),
        // Not clipped: on a short block the chip spills below it rather
        // than being cut off.
        child: Align(
          alignment: Alignment.topLeft,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              // The strong glass fill with navy text, so the times stay
              // legible over whatever block sits underneath.
              color: g.fillStrong,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: g.border),
              boxShadow: [BoxShadow(color: g.shadow, blurRadius: 4)],
            ),
            child: Text(
              range,
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: g.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // -- drag-to-create --

  void _createStart(DragStartDetails d) {
    if (isAdditiveCalendarClick()) {
      // Shift/Ctrl+drag on empty space: rubber-band selection, no new action.
      _marqueeOrigin = d.localPosition;
      _marqueeMoved = false;
      _marqueeCancelled = false;
      HardwareKeyboard.instance.addHandler(_marqueeKey);
      return;
    }
    final day = (d.localPosition.dx / widget.dayWidth).floor().clamp(
      0,
      widget.dayCount - 1,
    );
    _newRangeN.value = _NewRange(day, d.localPosition.dy, d.localPosition.dy);
  }

  void _createUpdate(DragUpdateDetails d) {
    final o = _marqueeOrigin;
    if (o != null) {
      if (!_marqueeMoved && (d.localPosition - o).distance < 4) return;
      _marqueeMoved = true;
      _marqueeN.value = Rect.fromPoints(o, d.localPosition);
      return;
    }
    final r = _newRange;
    if (r != null) _newRangeN.value = r.at(d.localPosition.dy);
  }

  void _createCancel() {
    _endMarquee();
    _newRangeN.value = null;
  }

  // -- rubber-band selection --

  /// Grid-content coordinates (the same space the blocks are positioned in, so
  /// scrolling and zoom don't matter) of where a Shift/Ctrl+drag began; null
  /// when no marquee is in progress.
  Offset? _marqueeOrigin;
  bool _marqueeMoved = false;
  final _marqueeN = ValueNotifier<Rect?>(null);

  void _endMarquee() {
    if (_marqueeOrigin != null) {
      HardwareKeyboard.instance.removeHandler(_marqueeKey);
    }
    _marqueeOrigin = null;
    _marqueeMoved = false;
    _marqueeN.value = null;
  }

  bool _marqueeKey(KeyEvent e) {
    if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.escape) {
      // Abandon the rectangle but keep swallowing the drag until release.
      _marqueeN.value = null;
      _marqueeMoved = false;
      _marqueeCancelled = true;
    }
    return false;
  }

  bool _marqueeCancelled = false;

  /// Ids of the timed events whose drawn rectangle intersects [r], computed
  /// from the layout (not the widgets), so blocks outside the built window
  /// are still found.
  Set<String> _marqueeHits(Rect r) {
    final hits = <String>{};
    for (var d = 0; d < _placedByDay.length; d++) {
      for (final p in _placedByDay[d]) {
        final seg = p.event;
        final laneW = widget.dayWidth / p.laneCount;
        final box = Rect.fromLTWH(
          d * widget.dayWidth + p.lane * laneW,
          _px(seg.topMin),
          laneW * p.span - 2,
          math.max(_kMinBlockHeight, _px(seg.lenMin)),
        );
        if (box.overlaps(r)) hits.add(seg.item.id);
      }
    }
    return hits;
  }

  /// The dragged range as UTC start/end: the start snaps down and the end up
  /// to the 10-minute grid, so the slot covers what was swept; at least
  /// [kMinDurationMinutes] long and inside its day.
  (DateTime, DateTime) _newRangeTimes(_NewRange r) {
    int minuteAt(double y, double Function(double) round) {
      final minutes = pxToMinutes(y, pxPerMinute: _pxPerMinute);
      return (round(minutes / kSnapMinutes) * kSnapMinutes).round().clamp(
        0,
        1440,
      );
    }

    var from = minuteAt(
      math.min(r.originY, r.currentY),
      (v) => v.floorToDouble(),
    );
    var to = minuteAt(math.max(r.originY, r.currentY), (v) => v.ceilToDouble());
    if (to - from < kMinDurationMinutes) to = from + kMinDurationMinutes;
    if (to > 1440) {
      to = 1440;
      from = 1440 - kMinDurationMinutes;
    }
    final dayStart = calendarAddDays(widget.start, r.day);
    return (
      dayStart.add(Duration(minutes: from)),
      dayStart.add(Duration(minutes: to)),
    );
  }

  /// Phone: a long-press on empty space opens the new-action dialog with a
  /// one-hour slot starting where the finger is (snapped to 10 minutes).
  Future<void> _createHourAt(Offset local) async {
    final day = (local.dx / widget.dayWidth).floor().clamp(
      0,
      widget.dayCount - 1,
    );
    final (start, _) = _newRangeTimes(_NewRange(day, local.dy, local.dy));
    if (ref.read(calendarPlanningProvider)) {
      await PlanItemEditorDialog.show(
        context,
        initialStart: start,
        initialMinutes: 60,
      );
      return;
    }
    await ActionEditorDialog.show(
      context,
      initialStart: start,
      initialEnd: start.add(const Duration(hours: 1)),
    );
  }

  Future<void> _createEnd() async {
    if (_marqueeOrigin != null) {
      final rect = _marqueeN.value;
      final cancelled = _marqueeCancelled;
      _marqueeCancelled = false;
      _endMarquee();
      if (rect != null && !cancelled) {
        setCalendarSelection(ref, {
          ...ref.read(calendarSelectionProvider),
          ..._marqueeHits(rect),
        });
      }
      return;
    }
    final r = _newRange;
    _newRangeN.value = null;
    if (r == null) return;
    final (start, end) = _newRangeTimes(r);
    if (ref.read(calendarPlanningProvider)) {
      await PlanItemEditorDialog.show(
        context,
        initialStart: start,
        initialMinutes: end.difference(start).inMinutes,
      );
      return;
    }
    await ActionEditorDialog.show(
      context,
      initialStart: start,
      initialEnd: end,
    );
  }

  Widget _createPreview(ColorScheme scheme, _NewRange r) {
    final (start, end) = _newRangeTimes(r);
    final dayStart = calendarAddDays(widget.start, r.day);
    final topMin = start.difference(dayStart).inMinutes;
    final lenMin = end.difference(start).inMinutes;
    return Positioned(
      key: const ValueKey('create-preview'),
      left: r.day * widget.dayWidth,
      top: _px(topMin),
      width: widget.dayWidth - 2,
      height: math.max(_kMinBlockHeight, _px(lenMin)),
      child: _rangeBox(scheme, '${_hhmm(start)} – ${_hhmm(end)}'),
    );
  }
}

/// A time range being dragged out on empty grid space: the day column it
/// started in and the vertical extent (px inside the grid) so far.
class _NewRange {
  final int day;
  final double originY;
  final double currentY;

  const _NewRange(this.day, this.originY, this.currentY);

  _NewRange at(double y) => _NewRange(day, originY, y);
}

class _GridPainter extends CustomPainter {
  final int dayCount;
  final double dayWidth;
  final double hourHeight;
  final Color color;

  /// Column of today (-1 = not in range) and its very light tint.
  final int todayIndex;
  final Color todayTint;

  const _GridPainter({
    required this.dayCount,
    required this.dayWidth,
    required this.hourHeight,
    required this.color,
    required this.todayIndex,
    required this.todayTint,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (todayIndex >= 0) {
      canvas.drawRect(
        Rect.fromLTWH(todayIndex * dayWidth, 0, dayWidth, size.height),
        Paint()..color = todayTint,
      );
    }
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var h = 0; h <= 24; h++) {
      final y = h * hourHeight;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
    for (var d = 0; d < dayCount; d++) {
      final x = d * dayWidth;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) =>
      old.dayCount != dayCount ||
      old.dayWidth != dayWidth ||
      old.hourHeight != hourHeight ||
      old.todayIndex != todayIndex ||
      old.todayTint != todayTint ||
      old.color != color;
}

/// Whether a block's "name, newline, time" label fits as ONE paragraph
/// (title within two lines, time on its own line) and how tall it then is.
/// Measured once per (name, time, width, text scale) and remembered, so
/// rebuilds, scrolling and selection changes never re-measure.
class _LabelFit {
  final bool fits;
  final double height;
  const _LabelFit(this.fits, this.height);
}

final Map<String, _LabelFit> _labelFits = {};

_LabelFit _labelFitFor(
  TextSpan span,
  String key,
  double width,
  TextScaler scaler,
) {
  final cached = _labelFits[key];
  if (cached != null) return cached;
  final painter = TextPainter(
    text: span,
    textDirection: TextDirection.ltr,
    textScaler: scaler,
    maxLines: 3,
  )..layout(maxWidth: math.max(0, width));
  final fit = _LabelFit(!painter.didExceedMaxLines, painter.height);
  painter.dispose();
  if (_labelFits.length > 4000) _labelFits.clear();
  return _labelFits[key] = fit;
}

class _EventBlock extends ConsumerStatefulWidget {
  final _Seg seg;
  final double height;
  final double width;

  /// Hides the direction badge while the grid scrolls (only that subtree
  /// listens, so the block itself is not rebuilt when it flips).
  final ValueListenable<bool> scrolling;
  final bool running;
  final bool showIcons;
  final bool dragging;
  final void Function(_DragKind, Offset) onDragStart;
  final void Function(Offset) onDragUpdate;

  const _EventBlock({
    required this.seg,
    required this.height,
    required this.width,
    required this.scrolling,
    required this.running,
    required this.showIcons,
    required this.dragging,
    required this.onDragStart,
    required this.onDragUpdate,
  });

  @override
  ConsumerState<_EventBlock> createState() => _EventBlockState();
}

class _EventBlockState extends ConsumerState<_EventBlock> {
  /// Pointer is in a resize band: the one MouseRegion switches cursor on band
  /// changes only (no per-band widgets).
  bool _inBand = false;

  /// Touch: the long-press arms the move at once (a buzz tells the user it can
  /// be pulled); holding on without moving for [_kSelectAfterArm] more selects
  /// the event.
  Timer? _armTimer;
  bool _armed = false;
  bool _heldStill = true;

  /// Desktop right-button press: where it went down and the y inside the block
  /// (null = none); the drag starts once the pointer has travelled a little.
  Offset? _rightDown;
  double _rightLocalY = 0;

  /// Planning mode, right click on a real action: 'Create plan item from this
  /// action' opens the plan item editor prefilled with its name, time, length
  /// and the template of the same name (if any).
  Future<void> _planMenu(Offset at) async {
    final item = widget.seg.item;
    final box = Overlay.of(context).context.findRenderObject() as RenderBox;
    // Everything needed afterwards is read BEFORE the await: the block can be
    // rebuilt or unmounted while the menu is open.
    final navContext = Navigator.of(context).context;
    final db = ref.read(databaseProvider);
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(at & Size.zero, Offset.zero & box.size),
      items: const [
        PopupMenuItem(
          key: ValueKey('block-plan-from-action'),
          value: 'plan',
          child: Text('Create plan item from this action'),
        ),
      ],
    );
    if (choice != 'plan' || !navContext.mounted) return;
    final key = item.name.trim().toLowerCase();
    final templates = await db.select(db.actionTemplatesTable).get();
    final template = templates
        .where((t) => t.name.trim().toLowerCase() == key)
        .firstOrNull;
    if (!navContext.mounted) return;
    await PlanItemEditorDialog.show(
      navContext,
      initialStart: item.startAt,
      initialMinutes: _effectiveEnd(item).difference(item.startAt!).inMinutes,
      initialName: item.name,
      initialTemplateId: template?.id,
    );
  }
  Offset _pressPos = Offset.zero;

  void _disarm() {
    _armTimer?.cancel();
    _armTimer = null;
    _armed = false;
  }

  @override
  void dispose() {
    _armTimer?.cancel();
    super.dispose();
  }

  _DragKind _kindAt(double dy) {
    final height = widget.height;
    final h = math.min(_kHandle, height / 3);
    if (widget.seg.isStart && dy < h) return _DragKind.resizeTop;
    if (widget.seg.isEnd && dy > height - h) return _DragKind.resizeBottom;
    return _DragKind.move;
  }

  void _setBand(bool v) {
    if (v != _inBand && mounted) setState(() => _inBand = v);
  }

  @override
  Widget build(BuildContext context) {
    CalendarPerfCounters.blockBuilds++;
    final seg = widget.seg;
    final height = widget.height;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final item = seg.item;
    final done = item.isDoneBefore;
    // Only the quantised colour position matters, so the once-a-minute urgency
    // refresh rebuilds a block only when its colour visibly changes.
    final key = widget.running
        ? null
        : ref.watch(
            actionUrgencyProvider.select(
              (m) => m[item.id] == null ? null : urgencyKey(m[item.id]!),
            ),
          );
    final dark = theme.brightness == Brightness.dark;
    final rc = runningColors(dark: dark);
    // No growth direction: white, "fill me in" (running keeps its colour).
    final unlinked =
        !widget.running &&
        ref.watch(
          actionsWithDirectionsProvider.select(
            (s) => s != null && !s.contains(item.id),
          ),
        );
    final ec = unlinked ? emptyColors(dark: dark, done: done) : null;
    // Done events keep their colour, muted.
    final uc = key == null
        ? null
        : done
        ? urgencyColorsMutedForKey(key, dark: dark)
        : urgencyColorsForKey(key, dark: dark);
    final bg = widget.running
        ? rc.bg
        : ec?.bg ??
              uc?.bg ??
              (done ? scheme.surfaceContainerHighest : scheme.primaryContainer);
    final fg = widget.running
        ? rc.fg
        : ec?.fg ??
              uc?.fg ??
              (done ? scheme.onSurfaceVariant : scheme.onPrimaryContainer);
    final name = TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.w600,
      color: fg,
      decoration: done ? TextDecoration.lineThrough : null,
    );
    final selected = ref.watch(
      calendarSelectionProvider.select((s) => s.contains(item.id)),
    );
    // The action's own start–end (not this day-slice's), so a block that
    // continues past midnight doesn't read "00:00", and the end is visible
    // without opening the event. The end is the one the block is drawn to.
    final timeRange = seg.timeRange;
    final padTop = height >= 16 ? 3.0 : 0.0;
    // Switch off (default): no subscription, no badge widgets at all.
    final icons = widget.showIcons
        ? ref.watch(actionDirectionIconsProvider.select((m) => m[item.id]))
        : null;
    // The badge floats over the bottom-right corner (outside the cached label,
    // so the label-fit cache never depends on it); blocks under 18 px have no
    // room for it.
    final showBadge = icons != null && height >= 18;

    // The label is ONE paragraph. A block gets a ClipRect only when its text
    // is taller than it; otherwise nothing needs clipping.
    Widget label;
    var clip = false;
    if (height >= 26) {
      // Title (w600 10 px, up to two lines) then the time on its own line
      // (8 px normal): one TextSpan tree = one paragraph.
      final children = [
        TextSpan(text: '${item.name}\n'),
        TextSpan(
          text: timeRange,
          style: TextStyle(
            fontSize: 8,
            fontWeight: FontWeight.w400,
            color: fg,
            decoration: TextDecoration.none,
          ),
        ),
      ];
      final textWidth = widget.width - 12;
      final scaler = MediaQuery.textScalerOf(context);
      final fit = _labelFitFor(
        TextSpan(
          style: DefaultTextStyle.of(context).style.merge(name),
          children: children,
        ),
        '${textWidth.toStringAsFixed(1)}|${scaler.scale(10)}|${item.name}|$timeRange',
        textWidth,
        scaler,
      );
      if (fit.fits) {
        label = Text.rich(
          TextSpan(style: name, children: children),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        );
        clip = height < padTop + fit.height;
      } else {
        // Title longer than two lines: keep the two-paragraph form so the
        // ellipsis lands on the title and the time keeps its own line.
        label = OverflowBox(
          alignment: Alignment.topLeft,
          minHeight: 0,
          maxHeight: double.infinity,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: name,
              ),
              Text(timeRange, style: TextStyle(fontSize: 8, color: fg)),
            ],
          ),
        );
        clip = true;
      }
    } else {
      label = Text(
        '${item.name} · $timeRange',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: name,
      );
      clip = height < 12;
    }
    // A one-line label gives the badge its width as right padding so the name
    // ellipsizes instead of running under it.
    final badgeMax = _badgeMaxWidth(widget.width, height);
    final reserve = showBadge && height < 26
        ? directionBadgeWidth(icons, badgeMax, 11) + _kBadgeChrome
        : 0.0;
    Widget content = Padding(
      padding: EdgeInsets.fromLTRB(6, padTop, 6 + reserve, 0),
      child: label,
    );
    if (clip) content = ClipRect(child: content);
    if (showBadge) {
      content = Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.none,
        children: [
          content,
          Positioned(
            right: 2,
            bottom: 2,
            child: _HideWhileScrolling(
              scrolling: widget.scrolling,
              child: _DirectionChip(
                color: bg,
                child: _CountedBadge(
                  key: ValueKey('block-icons-${item.id}'),
                  actionId: item.id,
                  icons: icons,
                  maxWidth: badgeMax,
                ),
              ),
            ),
          ),
        ],
      );
    }

    Widget box = DecoratedBox(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        // One filled rounded rectangle: a thin neutral line keeps neighbouring
        // blocks apart, the selected one gets a thicker border.
        border: selected
            ? Border.all(color: scheme.onSurface, width: 2)
            : Border.all(color: urgencyOutline(bg, dark: dark)),
      ),
      child: content,
    );
    // A saveLayer is only worth paying for on the block being dragged.
    if (widget.dragging) box = Opacity(opacity: 0.4, child: box);

    // Selection happens on press (see [_onPress]); double-click edits. Only
    // the start of a drag comes from this recognizer: the rest (moves,
    // release) arrives through the grid's global pointer route, so the drag
    // survives this block being rebuilt or unmounted mid-drag.
    return Listener(
      onPointerDown: (e) {
        _onPress(ref, item.id, e, phone: usePhoneLayout(context));
        // Desktop: a RIGHT-button drag moves / resizes too, with the magnet.
        if (!usePhoneLayout(context) &&
            e.kind == PointerDeviceKind.mouse &&
            (e.buttons & kSecondaryButton) != 0) {
          _rightDown = e.position;
          _rightLocalY = e.localPosition.dy;
        } else {
          _rightDown = null;
        }
      },
      onPointerMove: (e) {
        final o = _rightDown;
        if (o == null || (e.position - o).distance < 4) return;
        _rightDown = null;
        widget.onDragStart(_kindAt(_rightLocalY), o);
      },
      onPointerUp: (e) {
        // A right click that did not turn into a drag.
        final rightClick = _rightDown != null;
        _rightDown = null;
        _onRelease(ref, item.id);
        if (rightClick &&
            ref.read(calendarPlanningProvider) &&
            !item.isAllDay &&
            item.startAt != null) {
          _planMenu(e.position);
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        dragStartBehavior: DragStartBehavior.down,
        // Phone: a tap opens the editor, a long-press then drag moves the
        // block (a plain drag must scroll the grid). Desktop: double-click
        // edits, a drag moves or resizes.
        onTap: usePhoneLayout(context)
            ? () => _phoneTap(context, ref, item.id)
            : null,
        onDoubleTap: usePhoneLayout(context)
            ? null
            : () => openActionEditor(context, ref, item.id),
        // Phone: a long-press arms the move at once (the block follows the
        // finger); keeping the finger still for 3 s in all SELECTS instead.
        onLongPressStart: usePhoneLayout(context)
            ? (d) {
                _disarm();
                _pressPos = d.globalPosition;
                _heldStill = true;
                _armed = true;
                HapticFeedback.mediumImpact();
                widget.onDragStart(_DragKind.move, _pressPos);
                _armTimer = Timer(_kSelectAfterArm, () {
                  if (!mounted || !_heldStill) return;
                  _phoneSelect(ref, item.id);
                });
              }
            : null,
        onLongPressMoveUpdate: usePhoneLayout(context)
            ? (d) {
                _pressPos = d.globalPosition;
                if (d.offsetFromOrigin.distance > _kHoldSlop) {
                  _heldStill = false;
                }
                if (_armed) widget.onDragUpdate(d.globalPosition);
              }
            : null,
        onLongPressEnd: usePhoneLayout(context) ? (_) => _disarm() : null,
        onLongPressCancel: usePhoneLayout(context) ? _disarm : null,
        onPanStart: usePhoneLayout(context)
            ? null
            : (d) => widget.onDragStart(
                _kindAt(d.localPosition.dy),
                d.globalPosition,
              ),
        onPanUpdate: usePhoneLayout(context)
            ? null
            : (d) => widget.onDragUpdate(d.globalPosition),
        child: MouseRegion(
          cursor: _inBand
              ? SystemMouseCursors.resizeUpDown
              : SystemMouseCursors.click,
          onHover: (e) =>
              _setBand(_kindAt(e.localPosition.dy) != _DragKind.move),
          onExit: (_) => _setBand(false),
          child: box,
        ),
      ),
    );
  }
}

/// Touch: holding a chip for [_kChipSelectHold] selects it (a plain tap opens
/// the editor). The recognizer is raw because `InkWell.onLongPress` is fixed at
/// 500 ms.
class _HoldToSelect extends StatelessWidget {
  const _HoldToSelect({
    required this.enabled,
    required this.onSelect,
    required this.child,
  });

  final bool enabled;
  final VoidCallback onSelect;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return RawGestureDetector(
      gestures: {
        LongPressGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
              () => LongPressGestureRecognizer(duration: _kChipSelectHold),
              (r) => r.onLongPress = onSelect,
            ),
      },
      child: child,
    );
  }
}

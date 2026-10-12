// Support for the screen-recording demo (see demo_desktop_test.dart and
// demo_phone_test.dart): a visible cursor marker, tolerant "human" helpers and
// the demo data. Everything runs against an IN-MEMORY database, never the
// user's real one. This folder is `integration_test/` because Flutter's device
// test runner expects it there.
import 'dart:async';
import 'dart:convert';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/core/ids.dart';
import 'package:livenow/core/window_focus.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/action_service.dart';
import 'package:livenow/domain/budget_service.dart';
import 'package:livenow/domain/budget_rules.dart' show BudgetUnit;
import 'package:livenow/domain/dependency_service.dart';
import 'package:livenow/domain/growth_rules.dart';
import 'package:livenow/domain/metric_service.dart';
import 'package:livenow/domain/postpone_rules.dart';
import 'package:livenow/main.dart';
import 'package:livenow/ui/dialog_stack.dart';
import 'package:livenow/ui/providers.dart';
import 'package:livenow/ui/reminders.dart';
import 'package:livenow/ui/sync_providers.dart';
import 'package:livenow/ui/widgets/notes_blocks/notes_blocks.dart';
import 'package:timezone/timezone.dart' as tz;

// ---------------------------------------------------------------------------
// Cursor marker
// ---------------------------------------------------------------------------

/// Draws a fake mouse cursor / finger dot above the whole app and moves it to
/// wherever the script is about to tap.
/// Key of the repaint boundary around the whole demo app (for snapshots).
final demoBoundaryKey = GlobalKey();

class DemoOverlay extends StatefulWidget {
  const DemoOverlay({
    super.key,
    required this.pointer,
    required this.caption,
    required this.child,
  });

  final ValueNotifier<PointerState> pointer;
  final ValueNotifier<String?> caption;
  final Widget child;

  @override
  State<DemoOverlay> createState() => _DemoOverlayState();
}

class PointerState {
  const PointerState(this.at, this.pulse, {this.touch = false});
  final Offset at;
  final int pulse;
  final bool touch;
}

class _DemoOverlayState extends State<DemoOverlay> {
  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.ltr,
    child: Stack(
      children: [
        Positioned.fill(
          child: RepaintBoundary(key: demoBoundaryKey, child: widget.child),
        ),
        // The scene title, bottom centre.
        Positioned(
          left: 0,
          right: 0,
          bottom: 14,
          child: IgnorePointer(
            child: ValueListenableBuilder<String?>(
              valueListenable: widget.caption,
              builder: (context, text, _) => AnimatedOpacity(
                duration: const Duration(milliseconds: 300),
                opacity: text == null ? 0 : 1,
                child: Center(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xDD1E1B4B),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Text(
                      text ?? '',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: ValueListenableBuilder<PointerState>(
              valueListenable: widget.pointer,
              builder: (context, p, _) => Stack(
                children: [
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 420),
                    curve: Curves.easeInOutCubic,
                    left: p.at.dx - (p.touch ? 18 : 3),
                    top: p.at.dy - (p.touch ? 18 : 3),
                    child: _Marker(pulse: p.pulse, touch: p.touch),
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

class _Marker extends StatelessWidget {
  const _Marker({required this.pulse, required this.touch});
  final int pulse;
  final bool touch;

  @override
  Widget build(BuildContext context) {
    if (touch) {
      return TweenAnimationBuilder<double>(
        key: ValueKey(pulse),
        tween: Tween(begin: 1.0, end: 0.0),
        duration: const Duration(milliseconds: 450),
        builder: (context, t, _) => Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.35 + 0.25 * t),
            border: Border.all(color: const Color(0xFF6B47E8), width: 2),
          ),
        ),
      );
    }
    // A mouse arrow with a click ripple.
    return TweenAnimationBuilder<double>(
      key: ValueKey(pulse),
      tween: Tween(begin: 1.0, end: 0.0),
      duration: const Duration(milliseconds: 450),
      builder: (context, t, _) => SizedBox(
        width: 30,
        height: 30,
        child: Stack(
          children: [
            Positioned(
              left: -9 + 3,
              top: -9 + 3,
              child: Opacity(
                opacity: t,
                child: Container(
                  width: 24 + 20 * (1 - t),
                  height: 24 + 20 * (1 - t),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF6B47E8), width: 2),
                  ),
                ),
              ),
            ),
            const Icon(
              Icons.near_me,
              size: 22,
              color: Colors.white,
              shadows: [Shadow(color: Colors.black, blurRadius: 3)],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The driver
// ---------------------------------------------------------------------------

class Demo {
  Demo(this.tester, this.db, {required this.touch}) {
    _pointer = ValueNotifier(PointerState(const Offset(40, 40), 0, touch: touch));
  }

  final WidgetTester tester;
  final AppDatabase db;

  /// Phone run: the marker is a finger dot instead of a mouse arrow.
  final bool touch;
  late final ValueNotifier<PointerState> _pointer;
  final caption = ValueNotifier<String?>(null);
  final skipped = <String>[];
  final ignored = <String>[];
  var _step = 0;

  /// Speed of the whole demo (1 = normal; larger = slower).
  static const double slow = 1.0;

  Future<void> pause([int ms = 700]) async {
    final end = DateTime.now().add(Duration(milliseconds: (ms * slow).round()));
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 40));
      _swallowFrameworkErrors();
    }
  }

  /// A recorded run must not stop for a framework assertion (an overflow, a
  /// late animation tick on a closed dialog ...): it is logged and dropped.
  void _swallowFrameworkErrors() {
    Object? e;
    while ((e = tester.takeException()) != null) {
      final text = e.toString().split('\n').first;
      debugPrint('DEMO ignored framework error: $text');
      ignored.add(text);
    }
  }

  /// A short title in the log (and, for the recording, a visible pause).
  Future<void> scene(String title, [int ms = 900]) async {
    _step++;
    debugPrint('DEMO[${_step.toString().padLeft(3, '0')}] $title');
    caption.value = title;
    await pause(ms);
  }

  Widget wrap(Widget app) =>
      DemoOverlay(pointer: _pointer, caption: caption, child: app);

  TestGesture? _mouse;

  Future<void> _moveTo(Offset p) async {
    final from = _pointer.value.at;
    _pointer.value = PointerState(p, _pointer.value.pulse, touch: touch);
    if (!touch) {
      // A real (synthetic) mouse follows the marker, so hover toolbars appear.
      _mouse ??= await tester.createGesture(kind: PointerDeviceKind.mouse);
    }
    const steps = 10;
    for (var i = 1; i <= steps; i++) {
      if (!touch) {
        final at = Offset.lerp(from, p, i / steps)!;
        if (i == 1 && !_mouseAdded) {
          await _mouse!.addPointer(location: at);
          _mouseAdded = true;
        }
        await _mouse!.moveTo(at);
      }
      await pause(52);
    }
  }

  bool _mouseAdded = false;

  /// A real-looking click: the synthetic mouse presses and releases on the
  /// spot (touch run: a finger tap).
  Future<void> _click(Offset at, Finder fallback) async {
    if (touch) {
      await tester.tap(fallback, warnIfMissed: false);
      return;
    }
    await tester.tapAt(at, kind: PointerDeviceKind.mouse);
  }

  Future<void> _ripple() async {
    _pointer.value = PointerState(
      _pointer.value.at,
      _pointer.value.pulse + 1,
      touch: touch,
    );
    await tester.pump(const Duration(milliseconds: 60));
  }

  String _label(Finder f) {
    try {
      return f.toString();
    } catch (_) {
      return 'finder';
    }
  }

  bool exists(Finder f) {
    try {
      return f.evaluate().isNotEmpty;
    } catch (_) {
      return false; // e.g. `.first` of nothing
    }
  }

  /// Moves the marker to [f], clicks it, waits [after] ms. A finder that is not
  /// on screen is skipped (and listed at the end) so the demo never stops.
  Future<bool> tap(Finder f, {int after = 800, String? note}) async {
    var target = f;
    try {
      if (f.hitTestable().evaluate().isNotEmpty) target = f.hitTestable();
    } catch (_) {}
    if (!exists(target)) {
      skipped.add(note ?? _label(f));
      debugPrint('DEMO  skip: ${note ?? _label(f)}');
      return false;
    }
    try {
      await tester.ensureVisible(target.first);
    } catch (_) {}
    await tester.pump(const Duration(milliseconds: 80));
    // Wide targets (a card title, a list row) are clicked near their left
    // edge, like a person would: the hover tools sit over the middle/right.
    final rect = tester.getRect(target.first);
    final center = rect.width > 220
        ? Offset(rect.left + 60, rect.center.dy)
        : rect.center;
    await _moveTo(center);
    await _ripple();
    try {
      await _click(center, target.first);
    } catch (e) {
      skipped.add('$note $e');
      return false;
    }
    await pause(after);
    return true;
  }

  Future<bool> tapKey(String key, {int after = 800}) =>
      tap(find.byKey(ValueKey(key)), after: after, note: 'key $key');
  Future<bool> tapText(String text, {int after = 800}) =>
      tap(find.text(text), after: after, note: 'text "$text"');
  Future<bool> tapTooltip(String message, {int after = 800}) =>
      tap(find.byTooltip(message), after: after, note: 'tooltip "$message"');
  Future<bool> tapIcon(IconData icon, {int after = 800}) =>
      tap(find.byIcon(icon), after: after, note: 'icon $icon');

  /// Hovers (desktop) without clicking: toolbars that appear on hover.
  Future<void> hover(Finder f, {int after = 900}) async {
    if (!exists(f)) {
      skipped.add('hover ${_label(f)}');
      return;
    }
    try {
      await tester.ensureVisible(f.first);
    } catch (_) {}
    await tester.pump(const Duration(milliseconds: 80));
    await _moveTo(tester.getCenter(f.first));
    await pause(after);
  }

  /// Scrolls the biggest vertical list back to its top (no animation back).
  Future<void> scrollToTop() async {
    final best = _bestScrollable(null);
    try {
      if (best == null || best.position.pixels == 0) return;
      await _animateScroll(best.position, 0, 600);
      await pause(200);
    } catch (_) {}
  }

  /// Types [text] into the field [f], one letter at a time.
  Future<void> type(Finder f, String text, {int perChar = 70}) async {
    if (!exists(f)) {
      skipped.add('type into ${_label(f)}');
      return;
    }
    await tap(f.first, after: 250, note: 'field ${_label(f)}');
    for (var i = 1; i <= text.length; i++) {
      await tester.enterText(f.first, text.substring(0, i));
      await pause(perChar);
    }
    await pause(400);
  }

  Future<void> clearField(Finder f) async {
    if (!exists(f)) return;
    await tester.enterText(f.first, '');
    await pause(300);
  }

  /// Smoothly scrolls the first scrollable under [within] (default: the
  /// biggest one) down by [dy] pixels, then back up.
  /// The vertical scrollable with the most to scroll (under [within]), or null.
  ScrollableState? _bestScrollable(Finder? within) {
    final scrollables = within == null
        ? find.byType(Scrollable)
        : find.descendant(of: within, matching: find.byType(Scrollable));
    ScrollableState? best;
    var bestExtent = 0.0;
    for (final e in scrollables.evaluate()) {
      if (e is! StatefulElement || !e.mounted) continue;
      final st = e.state as ScrollableState;
      try {
        if (st.position.axis != Axis.vertical) continue;
        if (!st.position.hasContentDimensions) continue;
        final extent = st.position.maxScrollExtent;
        if (extent > bestExtent) {
          bestExtent = extent;
          best = st;
        }
      } catch (_) {
        // a position that is being replaced right now: not a candidate
      }
    }
    return best;
  }

  Future<void> scroll({Finder? within, double dy = 600, bool back = true}) async {
    final first = _bestScrollable(within);
    if (first == null) {
      skipped.add('scroll (nothing scrollable)');
      return;
    }
    try {
      await _moveTo(
        tester.getCenter(find.byWidget(first.widget).first) + const Offset(0, 20),
      );
    } catch (_) {}
    // The tree may have changed while the marker moved (a dialog opening, a
    // list rebuilding): look again, and never let a stale position stop the
    // demo.
    final best = _bestScrollable(within);
    if (best == null) {
      skipped.add('scroll (list gone)');
      return;
    }
    try {
      final pos = best.position;
      final target = (pos.pixels + dy).clamp(0.0, pos.maxScrollExtent);
      await _animateScroll(pos, target, 1400);
      await pause(300);
      if (back) {
        final again = _bestScrollable(within) ?? best;
        await _animateScroll(again.position, 0, 1200);
        await pause(300);
      }
    } catch (e) {
      skipped.add('scroll failed: ${e.toString().split('\n').first}');
    }
  }

  /// Runs a scroll animation and pumps frames until it has really finished
  /// (a slow screen recording stretches frame times, so a fixed pause is not
  /// enough). Gives up after 10 s.
  Future<void> _animateScroll(ScrollPosition pos, double to, int ms) async {
    var done = false;
    try {
      unawaited(
        pos
            .animateTo(to, duration: Duration(milliseconds: ms), curve: Curves.easeInOut)
            .whenComplete(() => done = true),
      );
    } catch (_) {
      return; // the position was disposed meanwhile: nothing to animate
    }
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (!done && DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 40));
      _swallowFrameworkErrors();
    }
  }

  /// A finger-style drag (phone swipes): from the centre of [f] by [by].
  Future<void> drag(Finder f, Offset by, {int after = 700}) async {
    if (!exists(f)) {
      skipped.add('drag ${_label(f)}');
      return;
    }
    final start = tester.getCenter(f.first);
    await _moveTo(start);
    final g = await tester.startGesture(start);
    const steps = 24;
    for (var i = 1; i <= steps; i++) {
      await g.moveTo(start + by * (i / steps));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await pause(after);
  }

  Future<void> longPress(Finder f, {int after = 900}) async {
    if (!exists(f)) {
      skipped.add('long press ${_label(f)}');
      return;
    }
    final c = tester.getCenter(f.first);
    await _moveTo(c);
    await _ripple();
    final g = await tester.startGesture(c);
    await pause(700);
    await g.up();
    await pause(after);
  }

  Future<void> doubleTap(Finder f, {int after = 1000}) async {
    if (!exists(f)) {
      skipped.add('double tap ${_label(f)}');
      return;
    }
    final c = tester.getCenter(f.first);
    await _moveTo(c);
    await _ripple();
    await _click(c, f.first);
    await tester.pump(const Duration(milliseconds: 90));
    await _click(c, f.first);
    await pause(after);
  }

  Future<void> key(LogicalKeyboardKey k, {bool ctrl = false, int after = 600}) async {
    if (ctrl) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(k);
    if (ctrl) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await pause(after);
  }

  /// Closes the top dialog with its Cancel/Close button, else Escape.
  Future<void> closeDialog() async {
    if (exists(find.text('Cancel'))) {
      await tapText('Cancel', after: 600);
    } else {
      await key(LogicalKeyboardKey.escape);
    }
  }

  /// Types into the Notes editor (appflowy) letter by letter at the end of the
  /// last block.
  Future<void> typeInNotes(String text) async {
    final finder = find.byType(AppFlowyEditor);
    if (!exists(finder)) {
      skipped.add('notes editor');
      return;
    }
    await tap(finder, after: 300, note: 'notes editor');
    final ed = tester.widget<AppFlowyEditor>(finder.first).editorState;
    final node = ed.document.root.children.last;
    var offset = node.delta?.length ?? 0;
    ed.selection = Selection.collapsed(Position(path: node.path, offset: offset));
    for (final ch in text.split('')) {
      await ed.apply(ed.transaction..insertText(node, offset, ch));
      offset++;
      await pause(55);
    }
    await pause(500);
  }

  /// Saves what the demo app shows (its own content only) as a PNG under
  /// claude_dev/demo_shots, for checking a scene without watching it.
  Future<void> snapshot(String name) async {
    final boundary =
        demoBoundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return;
    final image = await tester.runAsync(() => boundary.toImage(pixelRatio: 1));
    final data = await tester.runAsync(
      () => image!.toByteData(format: ui.ImageByteFormat.png),
    );
    final dir = Directory('claude_dev/demo_shots')..createSync(recursive: true);
    File('${dir.path}/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
    debugPrint('DEMO snapshot $name');
  }

  void report() {
    debugPrint('DEMO done. Ignored framework errors: ${ignored.length}');
    for (final i in ignored) {
      debugPrint('DEMO   ! $i');
    }
    debugPrint('DEMO done. Skipped (not on screen): ${skipped.length}');
    for (final s in skipped) {
      debugPrint('DEMO   - $s');
    }
  }
}

// ---------------------------------------------------------------------------
// Waiting for the "go" signal from the wrapper script
// ---------------------------------------------------------------------------

/// A short countdown on screen before anything moves, so the recording can
/// start from a calm first frame.
Future<void> countdown(Demo demo, {int seconds = 6}) async {
  for (var i = seconds; i > 0; i--) {
    demo.caption.value = 'Starting in $i...';
    await demo.pause(1000);
  }
  demo.caption.value = null;
  await demo.pause(600);
}

/// Sizes this window so that the app sees exactly [logicalWidth] x
/// [logicalHeight] logical pixels (the title bar and borders are added on top,
/// whatever the screen scaling is) and waits until it has laid out.
Future<void> sizeWindow(
  WidgetTester tester,
  int x,
  int y,
  int logicalWidth,
  int logicalHeight,
) async {
  final dpr = tester.view.devicePixelRatio;
  final chrome = ownWindowChrome() ?? (width: 16, height: 47);
  resizeOwnWindow(
    x,
    y,
    (logicalWidth * dpr).round() + chrome.width,
    (logicalHeight * dpr).round() + chrome.height,
  );
  for (var i = 0; i < 25; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  final size = tester.view.physicalSize / dpr;
  debugPrint(
    'DEMO window is now ${size.width.round()}x${size.height.round()} logical',
  );
}

// ---------------------------------------------------------------------------
// App start with the demo data
// ---------------------------------------------------------------------------

class _NoReminders extends RemindersEnabledNotifier {
  @override
  bool build() => false;
  @override
  void set(bool value) => state = value;
}

/// Opens the demo app (in-memory database, no reminders, host role) in
/// [tester]'s window and returns the driver.
Future<Demo> startDemo(WidgetTester tester, {required bool touch}) async {
  initPostponeTimeZoneData();
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  await seedDemoData(db);
  final demo = Demo(tester, db, touch: touch);
  resetStackedDialogsForTest();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        syncRoleProvider.overrideWithValue(SyncRole.host),
        remindersEnabledProvider.overrideWith(_NoReminders.new),
      ],
      child: demo.wrap(const LiveNowApp()),
    ),
  );
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  return demo;
}

// ---------------------------------------------------------------------------
// Demo data
// ---------------------------------------------------------------------------

DateTime _istanbul(int dayOffset, int hour, [int minute = 0]) {
  final loc = tz.getLocation('Europe/Istanbul');
  final now = tz.TZDateTime.now(loc);
  return tz.TZDateTime(
    loc,
    now.year,
    now.month,
    now.day + dayOffset,
    hour,
    minute,
  ).toUtc();
}

String _notes(List<Node> nodes) =>
    jsonEncode((Document.blank()..insert([0], nodes)).toJson());

Future<void> seedDemoData(AppDatabase db) async {
  final actions = ActionService(db);
  final metrics = MetricService(db);
  final deps = DependencyService(db);
  final budget = BudgetService(db);
  final now = DateTime.now().toUtc();

  // ---- growth directions ---------------------------------------------------
  Future<String> main(String name, String icon) => metrics.saveMetric(
    name: name,
    kind: MetricKind.boolean,
    isMain: true,
    icon: Value(icon),
  );
  final healthy = await main('I am healthy and full of energy', '💪');
  final career = await main('I grow in my career', '🚀');
  final family = await main('I keep my family close', '❤️');

  Future<String> dir(
    String name,
    String icon,
    MetricKind kind,
    MetricWindow? window,
    double target,
    List<String> leadsTo,
  ) => metrics.saveMetric(
    name: name,
    kind: kind,
    window: window,
    target: target,
    icon: Value(icon),
    leadsToIds: leadsTo,
  );
  final exercise = await dir('I exercise three times a week', '🏃', MetricKind.count, MetricWindow.week, 3, [healthy]);
  final sleep = await dir('I sleep enough', '😴', MetricKind.hours, MetricWindow.week, 49, [healthy]);
  final eat = await dir('I eat home-cooked food', '🍲', MetricKind.count, MetricWindow.week, 10, [healthy]);
  final deep = await dir('Deep work 20 hours a week', '🎯', MetricKind.hours, MetricWindow.week, 20, [career]);
  final learn = await dir('I learn something new daily', '📚', MetricKind.count, MetricWindow.week, 7, [career]);
  final network = await dir('I meet colleagues monthly', '🤝', MetricKind.count, MetricWindow.month, 2, [career]);
  final call = await dir('I call my parents weekly', '📞', MetricKind.count, MetricWindow.week, 2, [family]);
  final date = await dir('A date with my partner', '🍷', MetricKind.count, MetricWindow.month, 2, [family]);
  final read = await dir('I read every day', '📖', MetricKind.count, MetricWindow.week, 5, [learn]);
  final flutter = await dir('I study Flutter', '🦋', MetricKind.hours, MetricWindow.week, 5, [learn, deep]);
  final walk = await dir('I walk outside', '🚶', MetricKind.hours, MetricWindow.week, 5, [exercise]);
  await dir('I drink enough water', '💧', MetricKind.count, MetricWindow.week, 7, [healthy]);

  // ---- countable activities ------------------------------------------------
  final runActivity = await actions.createCountableActivity('Morning run');
  final readActivity = await actions.createCountableActivity('Read a book');

  // ---- actions ---------------------------------------------------------------
  final checklist = _notes([
    headingNode(level: 2, text: 'Report outline'),
    todoListNode(checked: true, text: 'Collect the numbers'),
    todoListNode(checked: false, text: 'Write the summary'),
    todoListNode(checked: false, text: 'Add the charts'),
    toggleListNode(
      text: 'Snippet to reuse',
      children: [
        codeBlockNode('final total = items.fold(0, (s, i) => s + i.price);'),
        paragraphNode(text: 'Paste it into the budget export.'),
      ],
    ),
    paragraphNode(text: 'Ping the team when it is ready.'),
  ]);

  final run = await actions.createAction(
    name: 'Morning run',
    startAt: _istanbul(0, 7),
    endAt: _istanbul(0, 7, 45),
    countableActivityId: runActivity,
    metricIds: [exercise, walk],
  );
  final standup = await actions.createAction(
    name: 'Team stand-up',
    startAt: now.add(const Duration(minutes: 20)),
    endAt: now.add(const Duration(minutes: 50)),
    metricIds: [network],
  );
  final deepWork = await actions.createAction(
    name: 'Deep work: write the quarterly report',
    startAt: now.subtract(const Duration(minutes: 35)),
    endAt: now.add(const Duration(minutes: 55)),
    notes: checklist,
    metricIds: [deep],
  );
  final lunch = await actions.createAction(
    name: 'Lunch with Anna',
    startAt: now.add(const Duration(minutes: 75)),
    endAt: now.add(const Duration(minutes: 135)),
    metricIds: [date, eat],
  );
  final diary = await actions.createAction(
    name: 'Diary',
    startAt: now.add(const Duration(minutes: 150)),
    endAt: now.add(const Duration(minutes: 180)),
  );
  await (db.update(db.actionsTable)..where((t) => t.id.equals(diary)))
      .write(const ActionsTableCompanion(resultNote: Value('Client')));
  final book = await actions.createAction(
    name: 'Read a book',
    startAt: now.add(const Duration(minutes: 220)),
    endAt: now.add(const Duration(minutes: 250)),
    countableActivityId: readActivity,
    metricIds: [read],
  );
  await actions.createAction(
    name: 'Drink a litre of water',
    isAllDay: true,
    startAt: _istanbul(0, 0),
    metricIds: [healthy],
  );
  final rent = await actions.createAction(
    name: 'Pay the rent',
    startAt: _istanbul(1, 9),
    endAt: _istanbul(1, 9, 15),
  );
  final plan = await actions.createAction(
    name: 'Plan the week',
    startAt: _istanbul(1, 17),
    endAt: _istanbul(1, 18),
    metricIds: [deep],
  );
  await actions.createAction(
    name: 'Call mom',
    isAllDay: true,
    startAt: _istanbul(1, 0),
    metricIds: [call],
  );
  await actions.createAction(
    name: 'Dentist',
    startAt: _istanbul(2, 15),
    endAt: _istanbul(2, 16),
  );
  await actions.createAction(
    name: 'Gym',
    startAt: _istanbul(3, 7),
    endAt: _istanbul(3, 8),
    metricIds: [exercise],
  );
  await actions.createAction(
    name: 'Study Flutter animations',
    startAt: _istanbul(-1, 20),
    endAt: _istanbul(-1, 21, 15),
    metricIds: [flutter],
  );
  await actions.createAction(
    name: 'Sleep',
    startAt: _istanbul(-1, 23),
    endAt: _istanbul(0, 6, 40),
    metricIds: [sleep],
  );

  // Yesterday's tagged work for the "What is done?" diary.
  await actions.createAction(
    name: '[Client:Acme] [KBT:CS-101] Implement login',
    startAt: _istanbul(-1, 10),
    endAt: _istanbul(-1, 11, 30),
  );
  await actions.createAction(
    name: '[Client:Acme] [KBT:CS-102] Review pull request',
    startAt: _istanbul(-1, 11, 30),
    endAt: _istanbul(-1, 12),
  );
  await actions.createAction(
    name: '[#2] [Client:Acme] [KBT:CS-101] Implement login',
    startAt: _istanbul(-1, 14),
    endAt: _istanbul(-1, 15),
  );
  await actions.createAction(
    name: '[Client:Bluebird] [KBT:CS-77] Fix invoice export',
    startAt: _istanbul(-1, 15, 30),
    endAt: _istanbul(-1, 16, 15),
  );
  // Finished runs feed the template averages.
  for (var d = 2; d <= 5; d++) {
    final id = await actions.createAction(
      name: 'Morning run',
      startAt: _istanbul(-d, 7),
      endAt: _istanbul(-d, 7, 40 + d),
      countableActivityId: runActivity,
    );
    await actions.finish(id);
  }

  // Chain: stand-up -> deep work -> lunch ; plan -> rent.
  await deps.addDependency(predecessorId: standup, successorId: deepWork);
  await deps.addDependency(predecessorId: deepWork, successorId: lunch);
  await deps.addDependency(predecessorId: plan, successorId: rent);
  await deps.addDependency(predecessorId: run, successorId: standup);
  await deps.addDependency(predecessorId: book, successorId: diary);

  // ---- templates ---------------------------------------------------------------
  Future<void> template(Map<String, dynamic> payload) => db
      .into(db.actionTemplatesTable)
      .insert(
        ActionTemplatesTableCompanion.insert(
          id: newId(),
          name: payload['name'] as String,
          payload: jsonEncode(payload),
        ),
      );
  await template({'name': 'Morning run', 'estimatedMinutes': 45, 'useAverage': true, 'isAllDay': false, 'metricIds': [exercise, walk]});
  await template({'name': 'Deep work block', 'estimatedMinutes': 90, 'isAllDay': false, 'metricIds': [deep], 'notes': checklist});
  await template({'name': 'Read a book', 'estimatedMinutes': 30, 'isAllDay': false, 'metricIds': [read]});
  await template({'name': 'Diary', 'estimatedMinutes': 30, 'isAllDay': false, 'diaryBlocks': 'Client', 'metricIds': <String>[]});
  await template({'name': 'Drink a litre of water', 'isAllDay': true, 'metricIds': <String>[]});
  await template({'name': 'Call family', 'estimatedMinutes': 20, 'isAllDay': false, 'metricIds': [call]});

  // ---- budget --------------------------------------------------------------------
  final eur = await budget.saveAccount(name: 'Cash EUR', currency: 'EUR', rateToBase: 1, openingBalance: 800);
  final uah = await budget.saveAccount(name: 'Monobank UAH', currency: 'UAH', rateToBase: 45, openingBalance: 30000);
  final usd = await budget.saveAccount(name: 'Revolut USD', currency: 'USD', rateToBase: 1.1, openingBalance: 500);

  Future<String> cat(
    String name, {
    String? parent,
    double? price,
    double? units,
    String? account,
    bool income = false,
    bool oneTime = false,
    DateTime? end,
    BudgetUnit unit = BudgetUnit.month,
    double? percent,
    String? percentOf,
  }) => budget.saveCategory(
    CategoryInput(
      name: name,
      parentId: parent,
      price: price,
      unitsPerMonth: units,
      isIncome: income,
      oneTime: oneTime,
      endDate: end,
      unit: unit,
      percent: percent,
      countPercentOfId: percentOf,
      accountCountId: account,
      accountUseId: account,
    ),
  );
  final housing = await cat('🏠 Housing');
  final rentCat = await cat('Rent', parent: housing, price: 520, units: 1, account: eur);
  await cat('Utilities', parent: housing, price: 4500, units: 1, account: uah);
  final food = await cat('🍽 Food');
  final groceries = await cat('Groceries', parent: food, price: 1800, units: 4, account: uah);
  final coffee = await cat('☕ Coffee');
  final coffeeA = await cat('Coffee', parent: coffee, price: 90, units: 12, account: uah);
  final coffeeB = await cat('Coffee', parent: coffee, price: 110, units: 6, account: uah);
  final eatOut = await cat('Restaurants', parent: food, price: 25, units: 3, account: usd);
  final transport = await cat('🚕 Transport');
  final taxi = await cat('Taxi', parent: transport, price: 6, units: 8, account: eur);
  await cat('Fuel', parent: transport, price: 40, units: 2, account: eur);
  final gym = await cat('Gym membership', price: 30, units: 1, account: eur);
  await cat('Old yoga studio', price: 25, units: 1, account: eur, end: DateTime.now().toUtc().subtract(const Duration(days: 20)));
  await cat('Laptop', price: 1400, oneTime: true, account: usd);
  final salary = await cat('💼 Salary', price: 3200, units: 1, account: usd, income: true);
  await cat('Savings', income: false, unit: BudgetUnit.percentPerMonth, percent: 10, percentOf: salary, account: eur);
  await cat('Gifts', price: 60, units: 1, account: eur);

  Future<void> tx(String category, int daysAgo, double qty, {String name = ''}) =>
      budget.createTransaction(
        categoryId: category,
        name: name,
        quantity: qty,
        date: DateTime.now().toUtc().subtract(Duration(days: daysAgo)),
      );
  await tx(rentCat, 12, 1, name: 'October rent');
  await tx(rentCat, 42, 1, name: 'September rent');
  await tx(groceries, 2, 1, name: 'Weekly shop');
  await tx(groceries, 9, 1);
  await tx(groceries, 16, 1);
  await tx(groceries, 24, 1);
  await tx(coffeeA, 1, 2, name: 'Flat white');
  await tx(coffeeA, 4, 1);
  await tx(coffeeB, 6, 1, name: 'Cappuccino');
  await tx(eatOut, 3, 1, name: 'Dinner with Anna');
  await tx(eatOut, 20, 1);
  await tx(taxi, 5, 2);
  await tx(taxi, 14, 1);
  await tx(gym, 10, 1, name: 'October membership');
  await tx(gym, 40, 1);
  await tx(salary, 18, 1, name: 'Salary September');
  await tx(salary, 48, 1);
  await tx(rentCat, 70, 1);
}

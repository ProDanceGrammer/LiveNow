import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'device_prefs.dart';

// Touchpad / wheel input shared by the Calendar and the Mindmap.
//
// A laptop touchpad reaches Flutter in two shapes: a Precision Touchpad (and a
// MacBook) sends PointerPanZoom start/update/end events, an older driver sends
// plain PointerScrollEvents with small dx/dy (the same event a mouse wheel
// sends, but in many small steps). Both are handled here. Created at a path
// required by its callers (ui/ shared helpers live here).

/// Device pref keys: swap the horizontal / vertical direction of swipes.
const kTouchpadInvertX = 'touchpadInvertX';
const kTouchpadInvertY = 'touchpadInvertY';

/// Whether the horizontal swipe direction is swapped (Settings).
final touchpadInvertXProvider = Provider<bool>(
  (ref) => ref.watch(devicePrefBoolProvider((kTouchpadInvertX, false))),
);

/// Whether the vertical swipe direction is swapped (Settings).
final touchpadInvertYProvider = Provider<bool>(
  (ref) => ref.watch(devicePrefBoolProvider((kTouchpadInvertY, false))),
);

/// Every pointer but a touchpad. A touchpad's two-finger pan arrives as a
/// PointerPanZoom gesture, which a pan recognizer takes for a one-finger drag
/// (it would drag a node or sweep out a new action): give such a GestureDetector
/// `supportedDevices: kNoTrackpadDevices`.
const kNoTrackpadDevices = {
  PointerDeviceKind.touch,
  PointerDeviceKind.mouse,
  PointerDeviceKind.stylus,
  PointerDeviceKind.invertedStylus,
  PointerDeviceKind.unknown,
};

/// A wheel notch reports exactly 100 (or 120, a Windows wheel) on one axis; a
/// touchpad sends many small, uneven deltas. Used to keep the mouse wheel
/// working as it always did.
bool isWheelNotch(Offset scrollDelta) {
  if (scrollDelta.dx != 0 && scrollDelta.dy != 0) return false;
  final d = (scrollDelta.dx != 0 ? scrollDelta.dx : scrollDelta.dy).abs();
  return d >= 50 && (d % 100 == 0 || d % 120 == 0);
}

/// Whether [e] came from a touchpad (not a notched mouse wheel).
bool isTouchpadScroll(PointerScrollEvent e) =>
    e.kind == PointerDeviceKind.trackpad || !isWheelNotch(e.scrollDelta);

/// Turns the stream of horizontal deltas of ONE swipe into exactly one step.
///
/// Positive input = next (content moved left / fingers moved left). The first
/// time the swipe has travelled [threshold] pixels it returns +1 or -1; the rest
/// of that swipe, including the inertia a touchpad keeps sending after the
/// fingers lift, returns 0. A new swipe starts after [end] or [quiet] of
/// silence.
class SwipeStepper {
  SwipeStepper({
    this.threshold = 60,
    this.quiet = const Duration(milliseconds: 250),
  });

  final double threshold;
  final Duration quiet;

  double _sum = 0;
  bool _fired = false;
  Duration? _last;

  /// [delta] pixels at [now] (an event time stamp). Returns -1, 0 or 1.
  int feed(double delta, Duration now) {
    final last = _last;
    if (last != null && now - last > quiet) _reset();
    _last = now;
    if (_fired) return 0;
    _sum += delta;
    if (_sum.abs() < threshold) return 0;
    _fired = true;
    return _sum > 0 ? 1 : -1;
  }

  /// The fingers lifted (PanZoomEnd): the next movement is a new swipe.
  void end() => _reset();

  void _reset() {
    _sum = 0;
    _fired = false;
    _last = null;
  }
}

/// Turns a pinch's growing / shrinking [scale] (1 at the start) into zoom
/// steps: one step each time it has changed by ~30% since the last step.
class PinchStepper {
  PinchStepper({this.grow = 1.3, this.shrink = 0.77});

  final double grow;
  final double shrink;
  double _base = 1;

  void start() => _base = 1;

  /// [scale] is the cumulative scale of the gesture. Returns +1 (zoom in),
  /// -1 (zoom out) or 0.
  int feed(double scale) {
    final ratio = scale / _base;
    if (ratio > grow) {
      _base = scale;
      return 1;
    }
    if (ratio < shrink) {
      _base = scale;
      return -1;
    }
    return 0;
  }
}

/// [m] with its scale multiplied by [factor] around the scene point [focal]
/// (the scale is kept inside [min]..[max]). Mindmap zoom by touchpad.
Matrix4 zoomedAround(
  Matrix4 m,
  Offset focal,
  double factor, {
  required double min,
  required double max,
}) {
  final current = m.storage[0];
  final next = (current * factor).clamp(min, max);
  final f = next / current;
  if (f == 1) return m;
  return m.clone()
    ..translateByDouble(focal.dx, focal.dy, 0, 1)
    ..scaleByDouble(f, f, 1, 1)
    ..translateByDouble(-focal.dx, -focal.dy, 0, 1);
}

/// The zoom factor of a scroll distance: 100 px (one wheel notch) = 20%.
double zoomFactorFor(double dy) => math.exp(-dy / 100 * 0.18);

/// [m] moved by [screenDelta] screen pixels (content follows the fingers).
Matrix4 pannedBy(Matrix4 m, Offset screenDelta) =>
    Matrix4.translationValues(screenDelta.dx, screenDelta.dy, 0).multiplied(m);

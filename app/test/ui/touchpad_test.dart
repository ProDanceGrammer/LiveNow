import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/ui/touchpad.dart';

/// The pure touchpad helpers: one step per swipe, pinch steps, wheel-notch
/// detection and zooming a matrix about a fixed point.
void main() {
  group('SwipeStepper', () {
    Duration ms(int v) => Duration(milliseconds: v);

    test('fires once per swipe, in the direction of the movement', () {
      final s = SwipeStepper();
      expect(s.feed(20, ms(0)), 0);
      expect(s.feed(50, ms(10)), 1); // 70 px: over the threshold
      expect(s.feed(400, ms(20)), 0, reason: 'the rest of the swipe is ignored');

      s.end();
      expect(s.feed(-30, ms(100)), 0);
      expect(s.feed(-40, ms(110)), -1);
    });

    test('a pause starts a new swipe even without an end event', () {
      final s = SwipeStepper();
      expect(s.feed(100, ms(0)), 1);
      expect(s.feed(100, ms(100)), 0, reason: 'still the same fling');
      expect(s.feed(100, ms(600)), 1, reason: '250 ms of silence = new swipe');
    });

    test('a short swipe does not count', () {
      final s = SwipeStepper();
      expect(s.feed(10, ms(0)), 0);
      expect(s.feed(10, ms(10)), 0);
    });
  });

  group('PinchStepper', () {
    test('steps each time the scale changed by about 30%', () {
      final p = PinchStepper()..start();
      expect(p.feed(1.1), 0);
      expect(p.feed(1.4), 1);
      expect(p.feed(1.5), 0, reason: 'measured from the last step');
      expect(p.feed(1.0), -1);
    });
  });

  group('isWheelNotch', () {
    test('100 and 120 on one axis are a wheel, small uneven deltas are not', () {
      expect(isWheelNotch(const Offset(0, 100)), isTrue);
      expect(isWheelNotch(const Offset(0, -120)), isTrue);
      expect(isWheelNotch(const Offset(100, 0)), isTrue);
      expect(isWheelNotch(const Offset(0, 17.5)), isFalse);
      expect(isWheelNotch(const Offset(3, 100)), isFalse);
      expect(isWheelNotch(Offset.zero), isFalse);
    });
  });

  group('zoomedAround', () {
    test('the focal point stays where it is while the scale changes', () {
      final m = Matrix4.identity()
        ..translateByDouble(40, 25, 0, 1)
        ..scaleByDouble(0.5, 0.5, 1, 1);
      const focal = Offset(300, 200); // a SCENE point
      Offset screenOf(Matrix4 x) => MatrixUtils.transformPoint(x, focal);

      final before = screenOf(m);
      final z = zoomedAround(m, focal, 2, min: 0.04, max: 30);
      expect(z.storage[0], closeTo(1.0, 1e-9));
      expect((screenOf(z) - before).distance, lessThan(1e-6));
    });

    test('the scale stays inside min..max', () {
      final m = Matrix4.identity()..scaleByDouble(20, 20, 1, 1);
      final z = zoomedAround(m, Offset.zero, 10, min: 0.04, max: 30);
      expect(z.storage[0], 30);
      final out = zoomedAround(m, Offset.zero, 1e-9, min: 0.04, max: 30);
      expect(out.storage[0], 0.04);
    });
  });
}

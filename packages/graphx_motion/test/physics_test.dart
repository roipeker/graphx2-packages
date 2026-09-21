import 'package:flutter_test/flutter_test.dart';
import 'package:graphx_motion/motion.dart';

void main() {
  group('physics', () {
    test('spring analytical solve is frame-partition independent', () {
      var one = 0.0;
      var split = 0.0;
      final a = MotionEngine();
      a.maxDelta = double.infinity;
      final b = MotionEngine();
      b.maxDelta = double.infinity;

      final ha = a.springDouble(
        () => one,
        (value) => one = value,
        100,
        spring: Spring.wobbly,
      );
      final hb = b.springDouble(
        () => split,
        (value) => split = value,
        100,
        spring: Spring.wobbly,
      );

      a.tick(1 / 30);
      b.tick(1 / 60);
      b.tick(1 / 60);

      expect(one, closeTo(split, 1e-10));
      expect(ha.velocity, closeTo(hb.velocity!, 1e-10));
    });

    test('spring replacement preserves conflicting property velocity only', () {
      final engine = MotionEngine();
      engine.maxDelta = double.infinity;
      final owner = Object();
      const x = MotionPropertyKey('x');
      const y = MotionPropertyKey('y');
      var px = 0.0;
      var py = 0.0;

      final grouped = engine.springProperties(
        [
          DoubleMotionProperty(
            property: x,
            read: () => px,
            write: (value) => px = value,
            to: 100,
          ),
          DoubleMotionProperty(
            property: y,
            read: () => py,
            write: (value) => py = value,
            to: 100,
          ),
        ],
        owner: owner,
        spring: Spring.wobbly,
      );

      engine.tick(.08);
      final outgoingVelocity = grouped.velocityFor(x)!;
      final yVelocity = grouped.velocityFor(y)!;
      expect(outgoingVelocity.abs(), greaterThan(0));
      expect(yVelocity.abs(), greaterThan(0));

      final replacement = engine.springDouble(
        () => px,
        (value) => px = value,
        -40,
        owner: owner,
        property: x,
        spring: Spring.snappy,
      );

      expect(replacement.velocity, closeTo(outgoingVelocity, 1e-12));
      expect(grouped.isActive, isTrue);
      expect(grouped.velocityFor(x), isNull);
      expect(grouped.velocityFor(y), closeTo(yVelocity, 1e-12));
    });

    test('invalid setup returns pooled storage before throwing', () {
      final engine = MotionEngine();
      engine.maxDelta = double.infinity;
      var value = 0.0;

      expect(
        () => engine.springDouble(
          () => value,
          (next) => value = next,
          double.nan,
        ),
        throwsArgumentError,
      );
      expect(engine.activeCount, 0);
      expect(engine.pooledRuntimeCount, 1);

      expect(
        () => engine.inertiaDouble(
          () => value,
          (next) => value = next,
          velocity: double.infinity,
        ),
        throwsArgumentError,
      );
      expect(engine.activeCount, 0);
      expect(engine.pooledRuntimeCount, 1);
    });

    test('physics has no duration progress or seeking', () {
      final engine = MotionEngine();
      engine.maxDelta = double.infinity;
      var value = 0.0;
      final handle = engine.springDouble(
        () => value,
        (next) => value = next,
        1,
      );

      expect(() => handle.progress, throwsUnsupportedError);
      expect(() => handle.progress = .5, throwsUnsupportedError);
    });

    test('damp settles exactly on target and emits onSettled', () {
      final engine = MotionEngine();
      engine.maxDelta = double.infinity;
      var value = 0.0;
      var settled = 0;
      var completed = 0;

      final handle = engine.dampDouble(
        () => value,
        (next) => value = next,
        10,
        damp: const Damp(response: .03, tolerance: 1e-5),
        onSettled: () => settled++,
        onComplete: () => completed++,
      );

      for (var i = 0; i < 120 && handle.isActive; ++i) {
        engine.tick(1 / 60);
      }

      expect(handle.isCompleted, isTrue);
      expect(value, 10);
      expect(settled, 1);
      expect(completed, 0);
    });

    test('unbounded inertia settles at analytical asymptotic position', () {
      final engine = MotionEngine();
      engine.maxDelta = double.infinity;
      var value = 0.0;
      final handle = engine.inertiaDouble(
        () => value,
        (next) => value = next,
        velocity: 1000,
        inertia: const Inertia(friction: 5, tolerance: .01),
      );

      for (var i = 0; i < 600 && handle.isActive; ++i) {
        engine.tick(1 / 60);
      }

      expect(handle.isCompleted, isTrue);
      expect(value, closeTo(200, 1e-6));
    });

    test('bounded inertia remains within bounds while bouncing', () {
      final engine = MotionEngine();
      engine.maxDelta = double.infinity;
      var value = 5.0;
      var minSeen = value;
      var maxSeen = value;

      final handle = engine.inertiaDouble(
        () => value,
        (next) {
          value = next;
          if (next < minSeen) minSeen = next;
          if (next > maxSeen) maxSeen = next;
        },
        velocity: 800,
        inertia: const Inertia(
          friction: 3,
          min: 0,
          max: 10,
          bounce: .45,
          tolerance: .02,
        ),
      );

      for (var i = 0; i < 900 && handle.isActive; ++i) {
        engine.tick(1 / 60);
      }

      expect(handle.isCompleted, isTrue);
      expect(minSeen, greaterThanOrEqualTo(0));
      expect(maxSeen, lessThanOrEqualTo(10));
      expect(value, inInclusiveRange(0, 10));
    });

    test('cancel complete snaps spring but stops inertia in place', () {
      final engine = MotionEngine();
      engine.maxDelta = double.infinity;
      var springValue = 0.0;
      var inertiaValue = 0.0;

      final spring = engine.springDouble(
        () => springValue,
        (next) => springValue = next,
        100,
      );
      final inertia = engine.inertiaDouble(
        () => inertiaValue,
        (next) => inertiaValue = next,
        velocity: 100,
      );
      engine.tick(.05);
      final beforeStop = inertiaValue;

      spring.cancel(complete: true);
      inertia.cancel(complete: true);

      expect(springValue, 100);
      expect(inertiaValue, beforeStop);
      expect(spring.isCompleted, isTrue);
      expect(inertia.isCompleted, isTrue);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:graphx_motion/motion.dart';

void main() {
  group('MotionEngine', () {
    test('animates an arbitrary double without a host dependency', () {
      final engine = MotionEngine();
      engine.maxDelta = double.infinity;
      var value = 0.0;

      final handle = engine.toDouble(
        () => value,
        (next) => value = next,
        100,
        duration: 1,
        ease: Ease.linear,
      );

      expect(engine.wantsUpdate, isTrue);
      engine.tick(.25);
      expect(value, closeTo(25, 1e-9));
      expect(handle.progress, closeTo(.25, 1e-9));

      engine.tick(.75);
      expect(value, closeTo(100, 1e-9));
      expect(handle.isCompleted, isTrue);
      expect(engine.wantsUpdate, isFalse);
    });

    test('auto overwrite removes only conflicting tracks from a group', () {
      final engine = MotionEngine();
      engine.maxDelta = double.infinity;
      final owner = Object();
      const x = MotionPropertyKey('x');
      const y = MotionPropertyKey('y');
      var px = 0.0;
      var py = 0.0;

      final grouped = engine.toProperties(
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
        duration: 1,
        ease: Ease.linear,
      );

      engine.tick(.5);
      expect(px, closeTo(50, 1e-9));
      expect(py, closeTo(50, 1e-9));

      final replacement = engine.toDouble(
        () => px,
        (value) => px = value,
        200,
        owner: owner,
        property: x,
        duration: .5,
        ease: Ease.linear,
      );

      expect(grouped.isActive, isTrue);
      expect(grouped.isCancelled, isFalse);

      engine.tick(.5);
      expect(px, closeTo(200, 1e-9));
      expect(py, closeTo(100, 1e-9));
      expect(grouped.isCompleted, isTrue);
      expect(replacement.isCompleted, isTrue);
    });

    test('reentrant overwrite does not skip unaffected grouped tracks', () {
      final engine = MotionEngine();
      engine.maxDelta = double.infinity;
      final owner = Object();
      const x = MotionPropertyKey('x');
      const y = MotionPropertyKey('y');
      const z = MotionPropertyKey('z');
      var px = 0.0;
      var py = 0.0;
      var pz = 0.0;
      MotionHandle? replacement;

      final grouped = engine.toProperties(
        [
          DoubleMotionProperty(
            property: x,
            read: () => px,
            write: (value) {
              px = value;
              replacement ??= engine.toProperties(
                [
                  DoubleMotionProperty(
                    property: x,
                    read: () => px,
                    write: (next) => px = next,
                    to: 200,
                  ),
                  DoubleMotionProperty(
                    property: y,
                    read: () => py,
                    write: (next) => py = next,
                    to: 200,
                  ),
                ],
                owner: owner,
                duration: .5,
                ease: Ease.linear,
              );
            },
            to: 100,
          ),
          DoubleMotionProperty(
            property: y,
            read: () => py,
            write: (value) => py = value,
            to: 100,
          ),
          DoubleMotionProperty(
            property: z,
            read: () => pz,
            write: (value) => pz = value,
            to: 100,
          ),
        ],
        owner: owner,
        duration: 1,
        ease: Ease.linear,
      );

      engine.tick(.5);

      expect(grouped.isActive, isTrue);
      expect(replacement, isNotNull);
      expect(px, closeTo(50, 1e-9));
      expect(py, closeTo(0, 1e-9));
      expect(pz, closeTo(50, 1e-9));

      engine.tick(.5);
      expect(grouped.isCompleted, isTrue);
      expect(replacement!.isCompleted, isTrue);
      expect(px, closeTo(200, 1e-9));
      expect(py, closeTo(200, 1e-9));
      expect(pz, closeTo(100, 1e-9));
    });

    test('cancel and runtime reuse from a writer is generation safe', () {
      final engine = MotionEngine();
      engine.maxDelta = double.infinity;
      var value = 0.0;
      late MotionHandle first;
      MotionHandle? replacement;

      first = engine.toDouble(
        () => value,
        (next) {
          value = next;
          if (replacement == null) {
            first.cancel();
            replacement = engine.toDouble(
              () => value,
              (v) => value = v,
              100,
              duration: .5,
              ease: Ease.linear,
            );
          }
        },
        10,
        duration: 1,
        ease: Ease.linear,
      );

      engine.tick(.5);
      expect(first.isCancelled, isTrue);
      expect(replacement, isNotNull);
      expect(replacement!.isActive, isTrue);
      expect(value, closeTo(5, 1e-9));

      engine.tick(.5);
      expect(value, closeTo(100, 1e-9));
      expect(replacement!.isCompleted, isTrue);
    });

    test('owner + hook finds the most recently started matching motion', () {
      final engine = MotionEngine();
      engine.maxDelta = double.infinity;
      final owner = Object();
      var value = 0.0;

      final handle = engine.toDouble(
        () => value,
        (next) => value = next,
        1,
        owner: owner,
        hook: #intro,
        duration: 1,
      );

      expect(engine.find(owner: owner, hook: #intro), same(handle));
      handle.cancel();
      expect(engine.find(owner: owner, hook: #intro), isNull);
    });

    test('paused motion lets the host sleep and wakes on resume', () {
      final engine = MotionEngine();
      engine.maxDelta = double.infinity;
      var wakes = 0;
      var sleeps = 0;
      engine.onWake = () => wakes++;
      engine.onIdle = () => sleeps++;
      var value = 0.0;

      final handle = engine.toDouble(
        () => value,
        (next) => value = next,
        1,
        duration: 1,
      );
      expect(wakes, 1);
      expect(engine.runningCount, 1);

      handle.pause();
      expect(engine.runningCount, 0);
      expect(engine.wantsUpdate, isFalse);
      expect(sleeps, 1);

      handle.resume();
      expect(engine.runningCount, 1);
      expect(wakes, 2);
    });

    test('timeScale zero sleeps the host without losing running state', () {
      final engine = MotionEngine();
      engine.maxDelta = double.infinity;
      var wakes = 0;
      var sleeps = 0;
      var value = 0.0;
      engine.onWake = () => wakes++;
      engine.onIdle = () => sleeps++;

      final handle = engine.toDouble(
        () => value,
        (next) => value = next,
        100,
        duration: 1,
        ease: Ease.linear,
      );
      expect(wakes, 1);

      engine.timeScale = 0;
      expect(engine.runningCount, 1);
      expect(engine.wantsUpdate, isFalse);
      expect(sleeps, 1);
      engine.tick(.5);
      expect(value, 0);
      expect(handle.isActive, isTrue);

      engine.timeScale = 1;
      expect(engine.wantsUpdate, isTrue);
      expect(wakes, 2);
      engine.tick(1);
      expect(value, closeTo(100, 1e-9));
      expect(handle.isCompleted, isTrue);
    });

    test('anonymous auto-overwrite does not infer identity from closures', () {
      final engine = MotionEngine();
      engine.maxDelta = double.infinity;
      final owner = Object();
      var value = 0.0;

      final first = engine.toDouble(
        () => value,
        (next) => value = next,
        10,
        owner: owner,
        duration: 1,
      );
      final second = engine.toDouble(
        () => value,
        (next) => value = next,
        20,
        owner: owner,
        duration: 1,
      );

      expect(first.isActive, isTrue);
      expect(second.isActive, isTrue);
      expect(engine.count(owner: owner), 2);
    });
  });
}

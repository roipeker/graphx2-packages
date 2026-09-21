import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:graphx_motion/motion.dart';

void main() {
  group('Motion hardening lifecycle harness', () {
    for (final seed in <int>[3, 11, 29, 47, 89, 149]) {
      test('randomized overwrite/cancel/pause lifecycle converges (seed $seed)', () {
        final random = math.Random(seed);
        final engine = MotionEngine();
        engine.maxDelta = double.infinity;
        final owner = Object();
        var x = 0.0;
        var y = 0.0;
        final xKey = const MotionPropertyKey('hardening.x');
        final yKey = const MotionPropertyKey('hardening.y');
        MotionHandle? latest;

        for (var step = 0; step < 500; ++step) {
          switch (random.nextInt(7)) {
            case 0:
            case 1:
              latest = engine.toConfiguredDouble(
                () => x,
                (value) => x = value,
                random.nextDouble() * 500 - 250,
                duration: .01 + random.nextDouble() * .5,
                overwrite: Overwrite.auto,
                owner: owner,
                property: xKey,
                hook: 'x',
              );
            case 2:
              latest = engine.toConfiguredProperties(
                [
                  DoubleMotionProperty(
                    read: () => x,
                    write: (value) => x = value,
                    to: random.nextDouble() * 300,
                    property: xKey,
                  ),
                  DoubleMotionProperty(
                    read: () => y,
                    write: (value) => y = value,
                    to: random.nextDouble() * 300,
                    property: yKey,
                  ),
                ],
                owner: owner,
                duration: .01 + random.nextDouble() * .5,
                overwrite: Overwrite.auto,
                hook: 'xy',
              );
            case 3:
              latest?.pause();
            case 4:
              latest?.resume();
            case 5:
              if (latest?.isActive ?? false) latest!.cancel();
            case 6:
              engine.tick(random.nextDouble() * .08);
          }
          _expectCountsSane(engine, seed, step);
        }

        engine.cancel(owner: owner);
        engine.tick(1);
        expect(engine.activeCount, 0, reason: 'seed=$seed');
        expect(engine.runningCount, 0, reason: 'seed=$seed');
        expect(engine.wantsUpdate, isFalse, reason: 'seed=$seed');
        expect(
          engine.find(owner: owner, hook: 'x'),
          isNull,
          reason: 'seed=$seed',
        );
        expect(
          engine.find(owner: owner, hook: 'xy'),
          isNull,
          reason: 'seed=$seed',
        );
        engine.dispose();
      });
    }

    test('stale handle cannot control recycled runtime generation', () {
      final engine = MotionEngine();
      engine.maxDelta = double.infinity;
      var value = 0.0;
      final old = engine.toDouble(
        () => value,
        (next) => value = next,
        1,
        duration: .01,
        ease: Ease.linear,
      );
      engine.tick(.02);
      expect(old.isActive, isFalse);

      final current = engine.toDouble(
        () => value,
        (next) => value = next,
        100,
        duration: 1,
        ease: Ease.linear,
      );
      old.cancel();
      old.pause();
      old.resume();
      engine.tick(.5);

      expect(current.isActive, isTrue);
      expect(value, closeTo(50.5, 1e-6));
      current.cancel();
      expect(engine.activeCount, 0);
      expect(engine.wantsUpdate, isFalse);
      engine.dispose();
    });
  });
}

void _expectCountsSane(MotionEngine engine, int seed, int step) {
  expect(engine.activeCount, greaterThanOrEqualTo(0), reason: 'seed=$seed step=$step');
  expect(engine.runningCount, greaterThanOrEqualTo(0), reason: 'seed=$seed step=$step');
  expect(
    engine.runningCount,
    lessThanOrEqualTo(engine.activeCount),
    reason: 'seed=$seed step=$step',
  );
  if (engine.runningCount == 0) {
    expect(engine.wantsUpdate, isFalse, reason: 'seed=$seed step=$step');
  }
}

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:graphx_motion/motion.dart';

void main() {
  group('Motion hardening partition harness', () {
    for (final seed in <int>[1, 7, 19, 41, 73, 101, 137, 211]) {
      test('duration state is tick-partition invariant (seed $seed)', () {
        final random = math.Random(seed);
        for (var scenario = 0; scenario < 80; ++scenario) {
          final spec = _ScenarioSpec.random(random);
          final coarse = _runScenario(spec, const [10.0]);
          final fine = _runScenario(spec, List<double>.filled(1000, .01));
          final jittered = _runScenario(spec, _jitteredPartition(10.0, seed + scenario));

          _expectSnapshot(coarse, fine, seed, scenario, spec, 'fine');
          _expectSnapshot(coarse, jittered, seed, scenario, spec, 'jittered');
        }
      });
    }

    test('timeline random seek is independent of prior traversal', () {
      for (var seed = 0; seed < 64; ++seed) {
        final random = math.Random(seed);
        final targetProgress = random.nextDouble();
        final direct = _timelineAt(targetProgress, traverseFirst: false);
        final traversed = _timelineAt(targetProgress, traverseFirst: true);

        expect(
          direct,
          closeTo(traversed, 1e-9),
          reason: 'seed=$seed progress=$targetProgress',
        );
      }
    });
  });
}

final class _ScenarioSpec {
  const _ScenarioSpec({
    required this.start,
    required this.target,
    required this.duration,
    required this.delay,
    required this.repeat,
    required this.repeatDelay,
    required this.yoyo,
  });

  factory _ScenarioSpec.random(math.Random random) => _ScenarioSpec(
    start: random.nextDouble() * 200 - 100,
    target: random.nextDouble() * 200 - 100,
    duration: .05 + random.nextDouble() * 1.5,
    delay: random.nextDouble() * .5,
    repeat: random.nextInt(4),
    repeatDelay: random.nextDouble() * .3,
    yoyo: random.nextBool(),
  );

  final double start;
  final double target;
  final double duration;
  final double delay;
  final int repeat;
  final double repeatDelay;
  final bool yoyo;

  @override
  String toString() =>
      'start=$start target=$target duration=$duration delay=$delay '
      'repeat=$repeat repeatDelay=$repeatDelay yoyo=$yoyo';
}

final class _Snapshot {
  const _Snapshot(this.value, this.active, this.running, this.wantsUpdate);

  final double value;
  final int active;
  final int running;
  final bool wantsUpdate;
}

_Snapshot _runScenario(_ScenarioSpec spec, List<double> partition) {
  final engine = MotionEngine();
  engine.maxDelta = double.infinity;
  var value = spec.start;
  engine.toDouble(
    () => value,
    (next) => value = next,
    spec.target,
    from: spec.start,
    duration: spec.duration,
    delay: spec.delay,
    repeat: spec.repeat,
    repeatDelay: spec.repeatDelay,
    yoyo: spec.yoyo,
    ease: Ease.cubic.easeInOut,
  );

  for (final dt in partition) {
    engine.tick(dt);
  }

  final snapshot = _Snapshot(
    value,
    engine.activeCount,
    engine.runningCount,
    engine.wantsUpdate,
  );
  engine.dispose();
  return snapshot;
}

List<double> _jitteredPartition(double total, int seed) {
  final random = math.Random(seed);
  final result = <double>[];
  var remaining = total;
  while (remaining > 1e-12) {
    final next = math.min(remaining, .001 + random.nextDouble() * .12);
    result.add(next);
    remaining -= next;
  }
  return result;
}

void _expectSnapshot(
  _Snapshot expected,
  _Snapshot actual,
  int seed,
  int scenario,
  _ScenarioSpec spec,
  String partition,
) {
  final reason = 'seed=$seed scenario=$scenario partition=$partition $spec';
  expect(actual.value, closeTo(expected.value, 1e-8), reason: reason);
  expect(actual.active, expected.active, reason: reason);
  expect(actual.running, expected.running, reason: reason);
  expect(actual.wantsUpdate, expected.wantsUpdate, reason: reason);
}

double _timelineAt(double progress, {required bool traverseFirst}) {
  final engine = MotionEngine();
  engine.maxDelta = double.infinity;
  var value = 10.0;
  final property = MotionProperty<double>(
    read: () => value,
    write: (next) => value = next,
  );

  final timeline = engine.timeline(
    defaults: const MotionSpec(duration: .6, ease: Ease.linear),
  );
  timeline.add(MotionClip.property<double>(property, 40));
  timeline.add(property.clipBy(30));
  timeline.add(MotionClip.property<double>(property, 5));

  if (traverseFirst) {
    timeline.play();
    engine.tick(timeline.duration);
  }
  timeline.progress = progress;

  final result = value;
  timeline.dispose();
  engine.dispose();
  return result;
}

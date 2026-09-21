import 'package:flutter_test/flutter_test.dart';
import 'package:graphx_motion/motion.dart';

void main() {
  test('withPrevious aligns to the previous clip start', () {
    final engine = MotionEngine();
    engine.maxDelta = double.infinity;
    var x = 0.0;
    var y = 0.0;
    final xMotion = MotionProperty<double>(read: () => x, write: (value) => x = value);
    final yMotion = MotionProperty<double>(read: () => y, write: (value) => y = value);

    final timeline = engine.timeline(defaults: const MotionSpec(duration: 1, ease: Ease.linear));
    timeline.add(MotionClip.property<double>(xMotion, 100));
    timeline.withPrevious(
      MotionClip.property<double>(yMotion, 200, duration: .5, ease: Ease.linear),
      offset: .25,
    );
    timeline.play();

    expect(timeline.duration, 1);
    engine.tick(.25);
    expect(x, closeTo(25, 1e-9));
    expect(y, closeTo(0, 1e-9));
    engine.tick(.25);
    expect(x, closeTo(50, 1e-9));
    expect(y, closeTo(100, 1e-9));
    engine.tick(.5);
    expect(x, closeTo(100, 1e-9));
    expect(y, closeTo(200, 1e-9));
    engine.dispose();
  });

  test('afterPrevious aligns to the previous clip end, not the timeline cursor', () {
    final engine = MotionEngine();
    engine.maxDelta = double.infinity;
    var x = 0.0;
    var y = 0.0;
    var z = 0.0;
    final xMotion = MotionProperty<double>(read: () => x, write: (value) => x = value);
    final yMotion = MotionProperty<double>(read: () => y, write: (value) => y = value);
    final zMotion = MotionProperty<double>(read: () => z, write: (value) => z = value);

    final timeline = engine.timeline(defaults: const MotionSpec(duration: 1, ease: Ease.linear));
    timeline.add(MotionClip.property<double>(xMotion, 100));
    timeline.withPrevious(
      MotionClip.property<double>(yMotion, 100, duration: .5, ease: Ease.linear),
      offset: .25,
    );
    timeline.afterPrevious(
      MotionClip.property<double>(zMotion, 100, duration: .5, ease: Ease.linear),
      offset: .1,
    );

    expect(timeline.duration, closeTo(1.35, 1e-9));
    timeline.play();
    engine.tick(.85);
    expect(z, closeTo(0, 1e-9));
    engine.tick(.25);
    expect(z, closeTo(50, 1e-9));
    engine.dispose();
  });

  test('relative placement validates offsets and timeline mutability', () {
    final engine = MotionEngine();
    var value = 0.0;
    final property = MotionProperty<double>(read: () => value, write: (next) => value = next);
    final clip = MotionClip.property<double>(property, 1, duration: 1);
    final timeline = engine.timeline();

    expect(() => timeline.withPrevious(clip, offset: double.nan), throwsArgumentError);
    expect(() => timeline.afterPrevious(clip, offset: -1), throwsArgumentError);

    timeline.add(clip);
    timeline.seek(.5);
    expect(() => timeline.withPrevious(clip), throwsStateError);
    engine.dispose();
  });
}

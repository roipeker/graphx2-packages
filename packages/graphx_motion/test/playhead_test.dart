import 'package:flutter_test/flutter_test.dart';
import 'package:graphx_motion/motion.dart';

void main() {
  test('duration handle exposes silent time/progress setters', () {
    final engine = MotionEngine();
    engine.maxDelta = double.infinity;
    var value = 0.0;
    var updates = 0;
    final handle = engine.toDouble(
      () => value,
      (next) => value = next,
      100,
      duration: 2,
      ease: Ease.linear,
      onUpdate: () => updates++,
    );

    handle.progress = .25;
    expect(value, closeTo(25, 1e-9));
    expect(handle.time, closeTo(.5, 1e-9));
    expect(updates, 0, reason: 'direct playhead setters are silent');

    handle.time = 1.5;
    expect(value, closeTo(75, 1e-9));
    expect(handle.progress, closeTo(.75, 1e-9));
    expect(updates, 0);
    engine.dispose();
  });

  test('timeline sequential clips capture starts at their actual local start', () {
    final engine = MotionEngine();
    engine.maxDelta = double.infinity;
    final owner = Object();
    var x = 0.0;
    final xMotion = MotionProperty<double>(
      owner: owner,
      read: () => x,
      write: (next) => x = next,
    );

    final timeline = engine.timeline(
      defaults: const MotionSpec(duration: 1, ease: Ease.linear),
    );
    timeline.to<double>(xMotion, 100);
    timeline.to<double>(xMotion, 200);
    timeline.play();

    engine.tick(1);
    expect(x, closeTo(100, 1e-9));
    engine.tick(.5);
    expect(x, closeTo(150, 1e-9));
    engine.tick(.5);
    expect(x, closeTo(200, 1e-9));
    expect(timeline.progress, 1);
    timeline.dispose();
    engine.dispose();
  });

  test('random seek resolves overlapping starts at local start time', () {
    final engine = MotionEngine();
    engine.maxDelta = double.infinity;
    var x = 0.0;
    final property = MotionProperty<double>(
      read: () => x,
      write: (next) => x = next,
    );
    final timeline = engine.timeline(
      defaults: const MotionSpec(duration: 1, ease: Ease.linear),
    );
    timeline.to<double>(property, 100);
    timeline.to<double>(property, 200, at: .5);

    timeline.time = 1;
    expect(x, closeTo(125, 1e-9));

    timeline.time = .25;
    expect(x, closeTo(25, 1e-9));
    timeline.dispose();
    engine.dispose();
  });

  test('seek before first delayed clip restores the timeline baseline', () {
    final engine = MotionEngine();
    engine.maxDelta = double.infinity;
    var x = 20.0;
    final property = MotionProperty<double>(
      read: () => x,
      write: (next) => x = next,
    );
    final timeline = engine.timeline(
      defaults: const MotionSpec(duration: 1, ease: Ease.linear),
    );
    timeline.wait(.5);
    timeline.to<double>(property, 100);

    timeline.time = 1;
    expect(x, closeTo(60, 1e-9));
    timeline.time = .25;
    expect(x, closeTo(20, 1e-9));
    timeline.dispose();
    engine.dispose();
  });

  test('timeline seek is deterministic and reverse preserves sample', () {
    final engine = MotionEngine();
    engine.maxDelta = double.infinity;
    var value = 0.0;
    var calls = 0;
    final property = MotionProperty<double>(
      read: () => value,
      write: (next) => value = next,
    );

    final timeline = engine.timeline(
      defaults: const MotionSpec(duration: 1, ease: Ease.linear),
    );
    timeline.to<double>(property, 100);
    timeline.call(() => calls++);
    timeline.to<double>(property, 200);

    timeline.progress = .75;
    expect(value, closeTo(150, 1e-9));
    expect(calls, 0, reason: 'direct seek is silent');

    timeline.reverse();
    final before = value;
    expect(value, closeTo(before, 1e-9));
    engine.tick(.25);
    expect(value, closeTo(125, 1e-9));
    timeline.dispose();
    engine.dispose();
  });

  test('timeline playhead can itself be tweened', () {
    final engine = MotionEngine();
    engine.maxDelta = double.infinity;
    var value = 0.0;
    final property = MotionProperty<double>(
      read: () => value,
      write: (next) => value = next,
    );
    final timeline = engine.timeline(
      defaults: const MotionSpec(duration: 1, ease: Ease.linear),
    );
    timeline.to<double>(property, 100);

    timeline.motion.to(progress: 1, duration: 2, ease: Ease.linear);
    engine.tick(1);
    expect(timeline.progress, closeTo(.5, 1e-9));
    expect(value, closeTo(50, 1e-9));
    engine.tick(1);
    expect(timeline.progress, closeTo(1, 1e-9));
    expect(value, closeTo(100, 1e-9));
    timeline.dispose();
    engine.dispose();
  });

  test('driven Timeline playhead traverses callbacks and completion once', () {
    final engine = MotionEngine();
    engine.maxDelta = double.infinity;
    var value = 0.0;
    var crossed = 0;
    var completed = 0;
    final property = MotionProperty<double>(
      read: () => value,
      write: (next) => value = next,
    );
    final timeline = engine.timeline(
      defaults: const MotionSpec(duration: 1, ease: Ease.linear),
      onComplete: () => completed++,
    );
    timeline.to<double>(property, 100);
    timeline.call(() => crossed++, at: .5);

    timeline.motion.to(progress: 1, duration: 1, ease: Ease.linear);
    engine.tick(.5);
    expect(crossed, 1);
    expect(completed, 0);
    engine.tick(.5);
    expect(completed, 1);
    expect(timeline.isCompleted, isTrue);
    engine.tick(1);
    expect(completed, 1);
    timeline.dispose();
    engine.dispose();
  });

  test('live duration handle playhead can itself be tweened', () {
    final engine = MotionEngine();
    engine.maxDelta = double.infinity;
    var value = 0.0;
    final target = engine.toDouble(
      () => value,
      (next) => value = next,
      100,
      duration: 1,
      ease: Ease.linear,
    );
    target.pause();

    target.motion.to(progress: 1, duration: 2, ease: Ease.linear);
    engine.tick(1);
    expect(target.progress, closeTo(.5, 1e-9));
    expect(value, closeTo(50, 1e-9));
    engine.tick(1);
    expect(target.progress, closeTo(1, 1e-9));
    expect(value, closeTo(100, 1e-9));
    engine.dispose();
  });

  test('physics handles reject deterministic playhead control', () {
    final engine = MotionEngine();
    var value = 0.0;
    final handle = engine.springDouble(
      () => value,
      (next) => value = next,
      1,
    );
    expect(() => handle.progress, throwsUnsupportedError);
    expect(() => handle.time, throwsUnsupportedError);
    expect(() => handle.motion.to(progress: 1), throwsUnsupportedError);
    engine.dispose();
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:graphx_motion/motion.dart';

void main() {
  test('timeline motion.play uses authored seconds and timeScale', () {
    final engine = MotionEngine();
    engine.maxDelta = double.infinity;
    var value = 0.0;
    final property = MotionProperty<double>(
      read: () => value,
      write: (next) => value = next,
    );
    final timeline = engine.timeline(
      defaults: const MotionSpec(duration: 2, ease: Ease.linear),
    );
    timeline.to<double>(property, 100);

    timeline.motion.play(timeScale: 2);
    engine.tick(.5);

    expect(timeline.time, closeTo(1, 1e-9));
    expect(timeline.progress, closeTo(.5, 1e-9));
    expect(value, closeTo(50, 1e-9));

    engine.tick(.5);
    expect(timeline.progress, 1);
    expect(value, 100);
    engine.dispose();
  });

  test('timeline motion.play repeat and yoyo use normal Motion semantics', () {
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
    final repeats = <int>[];

    timeline.motion.play(
      repeat: 1,
      yoyo: true,
      onRepeat: repeats.add,
    );

    engine.tick(1);
    expect(timeline.progress, 1);
    expect(value, 100);
    expect(repeats, [1]);

    engine.tick(.5);
    expect(timeline.progress, closeTo(.5, 1e-9));
    expect(value, closeTo(50, 1e-9));

    engine.tick(.5);
    expect(timeline.progress, 0);
    expect(value, 0);
    engine.dispose();
  });

  test('motion.play repeats the current playhead segment', () {
    final engine = MotionEngine();
    engine.maxDelta = double.infinity;
    var value = 0.0;
    final property = MotionProperty<double>(
      read: () => value,
      write: (next) => value = next,
    );
    final timeline = engine.timeline(
      defaults: const MotionSpec(duration: 2, ease: Ease.linear),
    );
    timeline.to<double>(property, 100);

    timeline.progress = .25;
    timeline.motion.play(repeat: 1, yoyo: true);

    engine.tick(.75);
    expect(timeline.progress, closeTo(.625, 1e-9));
    expect(value, closeTo(62.5, 1e-9));

    engine.tick(.75);
    expect(timeline.progress, 1);
    expect(value, 100);

    engine.tick(1.5);
    expect(timeline.progress, closeTo(.25, 1e-9));
    expect(value, closeTo(25, 1e-9));
    engine.dispose();
  });

  test('motion.play validates timeScale', () {
    final engine = MotionEngine();
    final timeline = engine.timeline();
    timeline.wait(1);

    expect(() => timeline.motion.play(timeScale: 0), throwsArgumentError);
    expect(
      () => timeline.motion.play(timeScale: double.nan),
      throwsArgumentError,
    );
    engine.dispose();
  });
}

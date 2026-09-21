import 'package:flutter_test/flutter_test.dart';
import 'package:graphx_motion/graphx_motion.dart';

void main() {
  test('MotionClip is passive until added timeline plays', () {
    final engine = MotionEngine();
    engine.maxDelta = double.infinity;
    var value = 0.0;
    final property = MotionProperty<double>(
      read: () => value,
      write: (next) => value = next,
    );
    final clip = MotionClip.property<double>(
      property,
      100,
      duration: 1,
      ease: Ease.linear,
    );

    expect(engine.activeCount, 0);
    final timeline = engine.timeline();
    timeline.add(clip);
    expect(engine.activeCount, 0);
    timeline.play();
    engine.tick(.5);
    expect(value, closeTo(50, 1e-9));
    engine.tick(.5);
    expect(value, closeTo(100, 1e-9));
    expect(timeline.isCompleted, isTrue);
    engine.dispose();
  });

  test('nested timelines flatten into one root clock and preserve placement', () {
    final engine = MotionEngine();
    engine.maxDelta = double.infinity;
    final owner = Object();
    var x = 0.0;
    var y = 0.0;
    final xMotion = MotionProperty<double>(
      owner: owner,
      read: () => x,
      write: (next) => x = next,
    );
    final yMotion = MotionProperty<double>(
      owner: owner,
      read: () => y,
      write: (next) => y = next,
    );
    var childStarted = 0;
    var childCompleted = 0;

    final child = engine.timeline(
      defaults: const MotionSpec(duration: .5, ease: Ease.linear),
      onStart: () => childStarted++,
      onComplete: () => childCompleted++,
    );
    child.to<double>(xMotion, 100);
    child.to<double>(yMotion, 200);

    final root = engine.timeline();
    root.wait(.25);
    root.add(child);
    root.play();

    expect(child.isNested, isTrue);
    expect(root.duration, closeTo(1.25, 1e-9));
    expect(engine.activeCount, 3, reason: 'two leaves + one root clock');

    engine.tick(.25);
    expect(x, 0);
    expect(childStarted, 1);
    engine.tick(.5);
    expect(x, closeTo(100, 1e-9));
    expect(y, 0);
    engine.tick(.5);
    expect(y, closeTo(200, 1e-9));
    expect(childCompleted, 1);
    expect(root.isCompleted, isTrue);
    expect(child.isCompleted, isTrue);
    engine.dispose();
  });

  test('timeline nesting is arbitrary-depth but remains one root clock', () {
    final engine = MotionEngine();
    engine.maxDelta = double.infinity;
    var value = 0.0;
    final property = MotionProperty<double>(
      read: () => value,
      write: (next) => value = next,
    );

    final leaf = engine.timeline(
      defaults: const MotionSpec(duration: .25, ease: Ease.linear),
    );
    leaf.add(property.clip(1));
    final middle = engine.timeline();
    middle.add(leaf);
    final upper = engine.timeline();
    upper.add(middle);
    final root = engine.timeline();
    root.add(upper);
    root.play();

    expect(engine.activeCount, 2, reason: 'one leaf runtime + one root clock');
    engine.tick(.25);
    expect(value, closeTo(1, 1e-9));
    expect(root.isCompleted, isTrue);
    expect(upper.isCompleted, isTrue);
    expect(middle.isCompleted, isTrue);
    expect(leaf.isCompleted, isTrue);
    engine.dispose();
  });

  test('nested timeline cannot be controlled or modified independently', () {
    final engine = MotionEngine();
    final child = engine.timeline();
    child.wait(.2);
    final root = engine.timeline();
    root.add(child);

    expect(() => child.play(), throwsStateError);
    expect(() => child.wait(.1), throwsStateError);
    expect(() => root.add(root), throwsArgumentError);
    engine.dispose();
  });
}

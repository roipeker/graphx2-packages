import 'package:flutter_test/flutter_test.dart';
import 'package:graphx/graphx.dart';
import 'package:graphx_motion/graphx_motion.dart';

void main() {
  test('timeline appends, overlaps, labels and completes on engine clock', () {
    final engine = MotionEngine();
    engine.maxDelta = double.infinity;
    final owner = Object();
    var x = 0.0;
    var y = 0.0;
    final xMotion = MotionProperty<double>(
      owner: owner,
      read: () => x,
      write: (value) => x = value,
    );
    final yMotion = MotionProperty<double>(
      owner: owner,
      read: () => y,
      write: (value) => y = value,
    );
    var called = 0;
    var completed = 0;

    final timeline = engine.timeline(
      defaults: const MotionSpec(duration: 1, ease: Ease.linear),
      onComplete: () => completed++,
    );
    timeline.label(#intro);
    timeline.to<double>(xMotion, 100);
    timeline.to<double>(yMotion, 200, at: #intro);
    timeline.call(() => called++, at: .5);
    timeline.play();

    expect(timeline.duration, 1);
    expect(engine.wantsUpdate, isTrue);
    engine.tick(.5);
    expect(x, closeTo(50, 1e-9));
    expect(y, closeTo(100, 1e-9));
    expect(called, 1);
    expect(timeline.progress, closeTo(.5, 1e-9));
    engine.tick(.5);
    expect(x, closeTo(100, 1e-9));
    expect(y, closeTo(200, 1e-9));
    expect(timeline.isCompleted, isTrue);
    expect(completed, 1);
    engine.dispose();
  });

  test('timeline pause and resume controls all scheduled children', () {
    final engine = MotionEngine();
    engine.maxDelta = double.infinity;
    var value = 0.0;
    final property = MotionProperty<double>(read: () => value, write: (next) => value = next);
    final timeline = engine.timeline(defaults: const MotionSpec(duration: 1, ease: Ease.linear));
    timeline.to<double>(property, 100);
    timeline.play();
    engine.tick(.25);
    expect(value, closeTo(25, 1e-9));
    timeline.pause();
    engine.tick(.5);
    expect(value, closeTo(25, 1e-9));
    expect(timeline.isPaused, isTrue);
    timeline.resume();
    engine.tick(.75);
    expect(value, closeTo(100, 1e-9));
    expect(timeline.isCompleted, isTrue);
    engine.dispose();
  });

  test('timeline children keep normal property overwrite semantics', () {
    final engine = MotionEngine();
    engine.maxDelta = double.infinity;
    final owner = Object();
    var x = 0.0;
    var y = 0.0;
    final xMotion = MotionProperty<double>(
      owner: owner,
      read: () => x,
      write: (value) => x = value,
    );
    final yMotion = MotionProperty<double>(
      owner: owner,
      read: () => y,
      write: (value) => y = value,
    );
    final timeline = engine.timeline(defaults: const MotionSpec(duration: 1, ease: Ease.linear));
    timeline.toMany([xMotion.target(100), yMotion.target(200)]);
    timeline.play();
    engine.tick(.25);
    expect(x, closeTo(25, 1e-9));
    expect(y, closeTo(50, 1e-9));
    engine.to<double>(xMotion, 0, duration: .75, ease: Ease.linear);
    engine.tick(.75);
    expect(x, closeTo(0, 1e-9));
    expect(y, closeTo(200, 1e-9));
    expect(timeline.isCompleted, isTrue);
    engine.dispose();
  });

  test('GraphX node facade stays terse and uses normal Stage clock', () {
    final root = GRoot();
    final stage = GStage(root, maxDelta: 1);
    stage.mount();
    stage.setViewport(100, 100);
    stage.motion.engine.maxDelta = double.infinity;
    final node = root.addChild(GNode());
    node.setPosition(0, 0);

    final timeline = stage.motion.timeline(
      defaults: const MotionSpec(duration: 1, ease: Ease.linear),
    );
    timeline.node(node).to(x: 100, y: 50);
    timeline.label(#fade);
    timeline.node(node).to(alpha: .5, duration: .5, at: #fade);
    timeline.play();

    stage.tick(.5);
    expect(node.x, closeTo(50, 1e-9));
    expect(node.y, closeTo(25, 1e-9));
    stage.tick(.5);
    expect(node.x, closeTo(100, 1e-9));
    expect(node.y, closeTo(50, 1e-9));
    stage.tick(.5);
    expect(node.alpha, closeTo(.5, 1e-9));
    expect(timeline.isCompleted, isTrue);
    stage.dispose();
  });

  test('restart reconstructs child runtimes from current property values', () {
    final engine = MotionEngine();
    engine.maxDelta = double.infinity;
    var value = 0.0;
    final property = MotionProperty<double>(read: () => value, write: (next) => value = next);
    final timeline = engine.timeline(defaults: const MotionSpec(duration: 1, ease: Ease.linear));
    timeline.to<double>(property, 100);
    timeline.play();
    engine.tick(1);
    expect(value, 100);
    value = 0;
    timeline.restart();
    engine.tick(.5);
    expect(value, closeTo(50, 1e-9));
    engine.dispose();
  });

  test('timeline rejects infinite child repeat', () {
    final engine = MotionEngine();
    var value = 0.0;
    final property = MotionProperty<double>(read: () => value, write: (next) => value = next);
    final timeline = engine.timeline();
    expect(() => timeline.to<double>(property, 1, repeat: -1), throwsArgumentError);
    engine.dispose();
  });
}

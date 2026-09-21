import 'package:flutter_test/flutter_test.dart';
import 'package:graphx/graphx.dart';
import 'package:graphx_motion/graphx_motion.dart';

void main() {
  test('generic clipBy resolves from the clip local start', () {
    final engine = MotionEngine();
    engine.maxDelta = double.infinity;
    var value = 10.0;
    final property = MotionProperty<double>(
      read: () => value,
      write: (next) => value = next,
    );

    final timeline = engine.timeline(
      defaults: const MotionSpec(duration: 1, ease: Ease.linear),
    );
    timeline.add(property.clip(30));
    timeline.add(property.clipBy(20));

    timeline.progress = .75;
    expect(value, closeTo(40, 1e-9));

    timeline.progress = 1;
    expect(value, closeTo(50, 1e-9));
    engine.dispose();
  });

  test('node clipBy composes after absolute clip deterministically', () {
    final root = GRoot();
    final stage = GStage(root, maxDelta: 1);
    stage.mount();
    stage.setViewport(100, 100);
    final node = root.addChild(GNode());
    node.setPosition(10, 20);

    final timeline = stage.motion.timeline(
      defaults: const MotionSpec(duration: 1, ease: Ease.linear),
    );
    timeline.add(node.motion.clip(x: 30, y: 40));
    timeline.add(node.motion.clipBy(x: 20, y: -10));

    timeline.progress = .75;
    expect(node.x, closeTo(40, 1e-9));
    expect(node.y, closeTo(35, 1e-9));

    timeline.progress = 1;
    expect(node.x, closeTo(50, 1e-9));
    expect(node.y, closeTo(30, 1e-9));
    stage.dispose();
  });

  test('node clipBy supports scale shorthand and rotation deltas', () {
    final root = GRoot();
    final stage = GStage(root, maxDelta: 1);
    stage.mount();
    stage.setViewport(100, 100);
    final node = root.addChild(GNode());
    node.setScale(1);
    node.rotation = .25;

    final timeline = stage.motion.timeline(
      defaults: const MotionSpec(duration: 1, ease: Ease.linear),
    );
    timeline.add(node.motion.clipBy(scale: .5, rotation: 1));

    timeline.progress = 1;
    expect(node.scaleX, closeTo(1.5, 1e-9));
    expect(node.scaleY, closeTo(1.5, 1e-9));
    expect(node.rotation, closeTo(1.25, 1e-9));
    stage.dispose();
  });

  test('clipBy validates finite deltas and scale ambiguity', () {
    var value = 0.0;
    final property = MotionProperty<double>(
      read: () => value,
      write: (next) => value = next,
    );
    expect(() => property.clipBy(double.nan), throwsArgumentError);

    final node = GNode();
    expect(
      () => node.motion.clipBy(scale: 1, scaleX: 1),
      throwsArgumentError,
    );
  });
}

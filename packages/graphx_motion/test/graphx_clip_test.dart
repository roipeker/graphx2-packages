import 'package:flutter_test/flutter_test.dart';
import 'package:graphx/graphx.dart';
import 'package:graphx_motion/graphx_motion.dart';

void main() {
  test('node.motion.clip and blur.motion.clip compose in one timeline', () {
    final root = GRoot();
    final stage = GStage(root, maxDelta: 10);
    stage.mount();
    stage.setViewport(100, 100);
    stage.motion.engine.maxDelta = double.infinity;

    final node = root.addChild(GNode());
    final blur = GBlurFilter(blurX: 0, blurY: 0);
    node.filters = [blur];

    final timeline = stage.motion.timeline(
      defaults: const MotionSpec(duration: 1, ease: Ease.linear),
    );
    timeline.add(node.motion.clip(x: 100));
    timeline.add(blur.motion.clip(blurX: 20, blurY: 10), at: 0);
    timeline.play();

    expect(stage.motion.activeCount, 3, reason: 'node + blur + root timeline clock');
    stage.tick(.5);
    expect(node.x, closeTo(50, 1e-9));
    expect(blur.blurX, closeTo(10, 1e-9));
    expect(blur.blurY, closeTo(5, 1e-9));

    stage.tick(.5);
    expect(node.x, closeTo(100, 1e-9));
    expect(blur.blurX, closeTo(20, 1e-9));
    expect(blur.blurY, closeTo(10, 1e-9));
    expect(timeline.isCompleted, isTrue);
    stage.dispose();
  });

  test('all retained numeric filter facades compose through MotionClip', () {
    final root = GRoot();
    final stage = GStage(root, maxDelta: 10);
    stage.mount();
    stage.setViewport(100, 100);
    stage.motion.engine.maxDelta = double.infinity;

    final node = root.addChild(GNode());
    final shadow = GDropShadowFilter(
      offsetX: 0,
      offsetY: 0,
      blurX: 0,
      blurY: 0,
    );
    final glow = GGlowFilter(blurX: 0, blurY: 0, spread: 0);
    final bevel = GBevelFilter(
      offsetX: 0,
      offsetY: 0,
      blurX: 0,
      blurY: 0,
    );
    final outline = GOutlineFilter(width: 0, softness: 0);
    node.filters = [shadow, glow, bevel, outline];

    final timeline = stage.motion.timeline(
      defaults: const MotionSpec(duration: 1, ease: Ease.linear),
    );
    timeline.add(
      shadow.motion.clip(
        offsetX: 20,
        offsetY: 10,
        blurX: 8,
        blurY: 6,
      ),
    );
    timeline.add(
      glow.motion.clip(blurX: 12, blurY: 10, spread: 4),
      at: 0,
    );
    timeline.add(
      bevel.motion.clip(
        offsetX: 6,
        offsetY: 4,
        blurX: 8,
        blurY: 6,
      ),
      at: 0,
    );
    timeline.add(outline.motion.clip(width: 6, softness: 4), at: 0);
    timeline.play();

    expect(stage.motion.activeCount, 5, reason: 'four filter leaves + root clock');
    stage.tick(.5);
    expect(shadow.offsetX, closeTo(10, 1e-9));
    expect(shadow.blurX, closeTo(4, 1e-9));
    expect(glow.spread, closeTo(2, 1e-9));
    expect(bevel.offsetX, closeTo(3, 1e-9));
    expect(outline.width, closeTo(3, 1e-9));

    stage.tick(.5);
    expect(shadow.offsetY, closeTo(10, 1e-9));
    expect(glow.blurX, closeTo(12, 1e-9));
    expect(bevel.blurY, closeTo(6, 1e-9));
    expect(outline.softness, closeTo(4, 1e-9));
    expect(timeline.isCompleted, isTrue);
    stage.dispose();
  });

  test('immediate to overwrites the same property started by a filter clip', () {
    final root = GRoot();
    final stage = GStage(root, maxDelta: 10);
    stage.mount();
    stage.setViewport(100, 100);
    stage.motion.engine.maxDelta = double.infinity;

    final node = root.addChild(GNode());
    final glow = GGlowFilter(blurX: 0, blurY: 0, spread: 0);
    node.filters = [glow];

    final timeline = stage.motion.timeline(
      defaults: const MotionSpec(duration: 1, ease: Ease.linear),
    );
    timeline.add(glow.motion.clip(blurX: 20, spread: 10));
    timeline.play();

    stage.tick(.25);
    expect(glow.blurX, closeTo(5, 1e-9));
    expect(glow.spread, closeTo(2.5, 1e-9));

    glow.motion.to(blurX: 40, duration: .75, ease: Ease.linear);
    stage.tick(.75);

    expect(glow.blurX, closeTo(40, 1e-9));
    expect(glow.spread, closeTo(10, 1e-9));
    expect(timeline.isCompleted, isTrue);
    stage.dispose();
  });

  test('custom object mutation needs only MotionProperty to join a timeline', () {
    final engine = MotionEngine();
    engine.maxDelta = double.infinity;
    final state = _CustomState();
    final amount = MotionProperty<double>(
      owner: state,
      read: () => state.amount,
      write: (value) => state.amount = value,
    );

    final clip = amount.clip(100, duration: 1, ease: Ease.linear);
    expect(state.amount, 0);
    expect(engine.activeCount, 0);

    final timeline = engine.timeline();
    timeline.add(clip);
    timeline.play();
    engine.tick(.5);
    expect(state.amount, closeTo(50, 1e-9));
    engine.tick(.5);
    expect(state.amount, closeTo(100, 1e-9));
    expect(timeline.isCompleted, isTrue);
    engine.dispose();
  });
}

final class _CustomState {
  double amount = 0;
}

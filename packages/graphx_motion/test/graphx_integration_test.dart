import 'package:flutter_test/flutter_test.dart';
import 'package:graphx/graphx_extension.dart';
import 'package:graphx_motion/graphx_motion.dart';

void main() {
  test('stage motion listens only while active', () {
    final stage = _stage(GRoot());
    final motion = stage.motion;
    motion.engine.maxDelta = double.infinity;
    var value = 0.0;

    expect(stage.signals.onUpdate.hasListeners, isFalse);
    final handle = motion.tween(
      0,
      100,
      onValue: (next) => value = next,
      duration: 1,
      ease: Ease.linear,
    );
    expect(stage.signals.onUpdate.hasListeners, isTrue);

    stage.tick(.5);
    expect(value, closeTo(50, 1e-9));
    handle.pause();
    expect(stage.signals.onUpdate.hasListeners, isFalse);
    handle.resume();
    expect(stage.signals.onUpdate.hasListeners, isTrue);

    stage.tick(.5);
    expect(handle.isCompleted, isTrue);
    stage.dispose();
  });

  test('overwrite replacement keeps the Stage clock alive', () async {
    final root = GRoot();
    final stage = _stage(root);
    stage.motion.engine.maxDelta = double.infinity;
    final node = GNode();
    root.addChild(node);

    var enterStarts = 0;
    var exitStarts = 0;
    final first = node.motion.to(
      scale: 2,
      duration: 1,
      ease: Ease.linear,
      overwrite: Overwrite.all,
      onStart: () => enterStarts++,
    );

    stage.tick(.2);
    expect(enterStarts, 1);
    expect(node.scale, closeTo(1.2, 1e-9));

    final replacement = node.motion.to(
      scale: 1,
      duration: 1,
      ease: Ease.linear,
      overwrite: Overwrite.all,
      onStart: () => exitStarts++,
    );

    expect(first.isCancelled, isTrue);
    expect(replacement.isActive, isTrue);
    expect(stage.signals.onUpdate.hasListeners, isTrue);

    await Future<void>.delayed(Duration.zero);
    expect(stage.signals.onUpdate.hasListeners, isTrue);

    stage.tick(.5);
    expect(exitStarts, 1);
    expect(node.scale, closeTo(1.1, 1e-9));

    stage.tick(.5);
    expect(node.scale, closeTo(1, 1e-9));
    expect(replacement.isCompleted, isTrue);
    stage.dispose();
  });

  test('free scalar repaint is opt in', () {
    final stage = _stage(GRoot());
    final motion = stage.motion;
    motion.engine.maxDelta = double.infinity;
    var value = 0.0;
    stage.consumePaintRequest();

    motion.tween(
      0,
      1,
      onValue: (next) => value = next,
      duration: 1,
      ease: Ease.linear,
    );
    stage.tick(.5);
    expect(value, closeTo(.5, 1e-9));
    expect(stage.needsPaint, isFalse);

    motion.cancelAll();
    stage.consumePaintRequest();
    motion.tween(
      value,
      2,
      onValue: (next) => value = next,
      duration: 1,
      ease: Ease.linear,
      paint: true,
    );
    stage.tick(.5);
    expect(stage.needsPaint, isTrue);
    stage.dispose();
  });

  test('free spring uses the Stage demand gate until settled', () {
    final stage = _stage(GRoot());
    final motion = stage.motion;
    motion.engine.maxDelta = double.infinity;
    var value = 0.0;
    var settled = 0;

    final handle = motion.spring(
      0,
      100,
      onValue: (next) => value = next,
      spring: Spring.snappy,
      onSettled: () => settled++,
    );

    expect(stage.signals.onUpdate.hasListeners, isTrue);
    for (var i = 0; i < 300 && handle.isActive; ++i) {
      stage.tick(1 / 60);
    }

    expect(handle.isCompleted, isTrue);
    expect(value, closeTo(100, 1e-9));
    expect(settled, 1);
    stage.dispose();
  });

  test('timeScale zero releases the Stage update subscription', () {
    final stage = _stage(GRoot());
    final motion = stage.motion;
    motion.engine.maxDelta = double.infinity;
    var value = 0.0;

    motion.tween(
      0,
      1,
      onValue: (next) => value = next,
      duration: 1,
    );
    expect(stage.signals.onUpdate.hasListeners, isTrue);

    motion.timeScale = 0;
    expect(stage.signals.onUpdate.hasListeners, isFalse);
    stage.tick(.5);
    expect(value, 0);

    motion.timeScale = 1;
    expect(stage.signals.onUpdate.hasListeners, isTrue);
    stage.dispose();
  });

  test('node facade groups properties and exposes hook lookup', () {
    final root = GRoot();
    final stage = _stage(root);
    stage.motion.engine.maxDelta = double.infinity;
    final node = GNode();
    root.addChild(node);

    final handle = node.motion.to(
      x: 100,
      y: 80,
      alpha: .5,
      duration: 1,
      ease: Ease.linear,
      hook: #move,
    );
    expect(node.motion[#move], same(handle));

    stage.tick(.5);
    expect(node.x, closeTo(50, 1e-9));
    expect(node.y, closeTo(40, 1e-9));
    expect(node.alpha, closeTo(.75, 1e-9));

    final xOnly = node.motion.to(
      x: 200,
      duration: .5,
      ease: Ease.linear,
    );
    stage.tick(.5);
    expect(xOnly.isCompleted, isTrue);
    expect(handle.isCompleted, isTrue);
    expect(node.x, closeTo(200, 1e-9));
    expect(node.y, closeTo(80, 1e-9));
    expect(node.alpha, closeTo(.5, 1e-9));
    stage.dispose();
  });

  test('node spring retarget preserves velocity while other tracks continue', () {
    final root = GRoot();
    final stage = _stage(root);
    stage.motion.engine.maxDelta = double.infinity;
    final node = GNode();
    root.addChild(node);

    final grouped = node.motion.spring(
      x: 180,
      y: 120,
      spring: Spring.wobbly,
      hook: #move,
    );
    stage.tick(.08);
    final outgoingX = grouped.velocityFor(GNodeMotionProperties.x)!;
    final outgoingY = grouped.velocityFor(GNodeMotionProperties.y)!;

    final replacement = node.motion.spring(
      x: -40,
      spring: Spring.snappy,
      hook: #retarget,
    );

    expect(
      replacement.velocityFor(GNodeMotionProperties.x),
      closeTo(outgoingX, 1e-12),
    );
    expect(grouped.isActive, isTrue);
    expect(grouped.velocityFor(GNodeMotionProperties.x), isNull);
    expect(
      grouped.velocityFor(GNodeMotionProperties.y),
      closeTo(outgoingY, 1e-12),
    );
    stage.dispose();
  });

  test('node inertia respects independent axis bounds', () {
    final root = GRoot();
    final stage = _stage(root);
    stage.motion.engine.maxDelta = double.infinity;
    final node = GNode();
    node.setPosition(50, 50);
    root.addChild(node);

    final handle = node.motion.inertia(
      velocityX: 900,
      velocityY: -700,
      xBounds: const MotionBounds(0, 100, bounce: .4),
      yBounds: const MotionBounds(20, 80, bounce: .35),
      friction: 4,
    );

    for (var i = 0; i < 900 && handle.isActive; ++i) {
      stage.tick(1 / 60);
      expect(node.x, inInclusiveRange(0, 100));
      expect(node.y, inInclusiveRange(20, 80));
    }
    expect(handle.isCompleted, isTrue);
    stage.dispose();
  });

  test('filter motion derives Stage from ownership and invalidates paint', () {
    final root = GRoot();
    final stage = _stage(root);
    stage.motion.engine.maxDelta = double.infinity;
    final node = GNode();
    root.addChild(node);
    final blur = GBlurFilter(blurX: 8, blurY: 6);
    node.filters = [blur];

    expect(blur.owner, same(node));
    stage.consumePaintRequest();
    final handle = blur.motion.spring(
      blurX: 0,
      blurY: 0,
      spring: Spring.wobbly,
    );

    for (var i = 0; i < 300 && handle.isActive; ++i) {
      stage.tick(1 / 60);
      expect(blur.blurX, greaterThanOrEqualTo(0));
      expect(blur.blurY, greaterThanOrEqualTo(0));
    }

    expect(handle.isCompleted, isTrue);
    expect(blur.blurX, 0);
    expect(blur.blurY, 0);
    expect(stage.needsPaint, isTrue);
    expect(() => blur.motion.spring(blurX: -1), throwsArgumentError);
    stage.dispose();
  });

  test('color-transform motion writes through the explicit owner node', () {
    final root = GRoot();
    final stage = _stage(root);
    stage.motion.engine.maxDelta = double.infinity;
    final node = GNode();
    root.addChild(node);

    stage.consumePaintRequest();
    final handle = node.colorTransform
        .motion(owner: node)
        .to(
          const GColorTransform(
            redMultiplier: .2,
            greenMultiplier: .4,
            blueMultiplier: .6,
            alphaMultiplier: .8,
            redOffset: 20,
            greenOffset: 40,
            blueOffset: 60,
            alphaOffset: 80,
          ),
          duration: 1,
          ease: Ease.linear,
        );

    stage.tick(.5);
    final color = node.colorTransform;
    expect(color.redMultiplier, closeTo(.6, 1e-9));
    expect(color.greenMultiplier, closeTo(.7, 1e-9));
    expect(color.blueMultiplier, closeTo(.8, 1e-9));
    expect(color.alphaMultiplier, closeTo(.9, 1e-9));
    expect(color.redOffset, closeTo(10, 1e-9));
    expect(color.greenOffset, closeTo(20, 1e-9));
    expect(color.blueOffset, closeTo(30, 1e-9));
    expect(color.alphaOffset, closeTo(40, 1e-9));
    expect(stage.needsPaint, isTrue);

    stage.tick(.5);
    expect(handle.isCompleted, isTrue);
    stage.dispose();
  });

  test('subtree disposal cancels descendant node motion immediately', () {
    final root = GRoot();
    final stage = _stage(root);
    stage.motion.engine.maxDelta = double.infinity;
    final parent = GNode();
    final child = GNode();
    root.addChild(parent);
    parent.addChild(child);

    MotionCancelReason? reason;
    final handle = child.motion.to(
      x: 100,
      duration: 1,
      ease: Ease.linear,
      onCancel: (value) => reason = value,
    );

    stage.tick(.25);
    expect(child.x, closeTo(25, 1e-9));
    expect(stage.motion.activeCount, 1);

    parent.dispose();

    expect(child.isDisposed, isTrue);
    expect(handle.isCancelled, isTrue);
    expect(reason, MotionCancelReason.ownerDisposed);
    expect(stage.motion.activeCount, 0);
    expect(stage.motion.runningCount, 0);
    expect(stage.motion.wantsUpdate, isFalse);
    stage.dispose();
  });

  test('generic node-owned property motion terminates on subtree dispose', () {
    final root = GRoot();
    final stage = _stage(root);
    stage.motion.engine.maxDelta = double.infinity;
    final parent = GNode();
    final child = GNode();
    root.addChild(parent);
    parent.addChild(child);

    var value = 0.0;
    MotionCancelReason? reason;
    final property = MotionProperty<double>(
      owner: child,
      read: () => value,
      write: (next) => value = next,
    );
    final handle = stage.motion.to<double>(
      property,
      100,
      duration: 1,
      ease: Ease.linear,
      onCancel: (value) => reason = value,
    );

    stage.tick(.25);
    expect(value, closeTo(25, 1e-9));
    expect(stage.motion.activeCount, 1);

    parent.dispose();

    expect(child.isDisposed, isTrue);
    expect(handle.isCancelled, isTrue);
    expect(reason, MotionCancelReason.ownerDisposed);
    expect(stage.motion.activeCount, 0);
    expect(stage.motion.runningCount, 0);
    expect(stage.motion.wantsUpdate, isFalse);
    stage.dispose();
  });

  test('temporary detach keeps node motion, dispose cancels it', () {
    final root = GRoot();
    final stage = _stage(root);
    stage.motion.engine.maxDelta = double.infinity;
    final node = GNode();
    root.addChild(node);

    final handle = node.motion.to(
      x: 100,
      duration: 1,
      ease: Ease.linear,
    );

    root.removeChild(node);
    expect(handle.isActive, isTrue);
    stage.tick(.25);
    expect(node.x, closeTo(25, 1e-9));

    root.addChild(node);
    node.dispose();
    expect(handle.isCancelled, isTrue);
    stage.dispose();
  });
}

GStage _stage(GRoot root) {
  final stage = GStage(root, maxDelta: 10);
  stage.mount();
  stage.setViewport(320, 200);
  return stage;
}

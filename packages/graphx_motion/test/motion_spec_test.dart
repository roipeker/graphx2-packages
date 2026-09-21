import 'package:flutter_test/flutter_test.dart';
import 'package:graphx/graphx.dart';
import 'package:graphx_motion/graphx_motion.dart';

void main() {
  test('Stage defaults cascade into generic property motion', () {
    final stage = _stage();
    stage.motion.engine.maxDelta = double.infinity;
    stage.motion.defaults = const MotionSpec(
      duration: 1,
      ease: Ease.linear,
    );

    var value = 0.0;
    final property = MotionProperty<double>(
      read: () => value,
      write: (next) => value = next,
    );

    stage.motion.to<double>(property, 100);
    stage.tick(.25);
    expect(value, closeTo(25, 1e-9));
    stage.dispose();
  });

  test('Stage defaults cascade through scalar and retained facades', () {
    final root = GRoot();
    final stage = _stage(root);
    stage.motion.engine.maxDelta = double.infinity;
    stage.motion.defaults = const MotionSpec(
      duration: 1,
      ease: Ease.linear,
    );

    var scalar = 0.0;
    stage.motion.tween(0, 100, onValue: (next) => scalar = next);

    final node = root.addChild(GNode());
    node.motion.to(x: 100);

    final blur = GBlurFilter(blurX: 4, blurY: 4);
    node.filters = [blur];
    blur.motion.to(blurX: 20);

    final sourceTransform = node.colorTransform;
    sourceTransform
        .motion(owner: node)
        .to(
          const GColorTransform(redMultiplier: 0),
        );

    stage.tick(.25);
    expect(scalar, closeTo(25, 1e-9));
    expect(node.x, closeTo(25, 1e-9));
    expect(blur.blurX, closeTo(8, 1e-9));
    expect(node.colorTransform.redMultiplier, closeTo(.75, 1e-9));
    stage.dispose();
  });

  test('MotionSpec overrides Stage defaults and explicit args win last', () {
    final stage = _stage();
    stage.motion.engine.maxDelta = double.infinity;
    stage.motion.defaults = const MotionSpec(
      duration: 2,
      ease: Ease.linear,
    );

    var value = 0.0;
    final property = MotionProperty<double>(
      read: () => value,
      write: (next) => value = next,
    );
    const fast = MotionSpec(duration: 1);

    stage.motion.to<double>(
      property,
      100,
      motion: fast,
      duration: .5,
    );
    stage.tick(.25);
    expect(value, closeTo(50, 1e-9));
    stage.dispose();
  });

  test('one property may override interpolation per transition', () {
    final engine = MotionEngine();
    engine.maxDelta = double.infinity;
    var value = 0.0;
    final property = MotionProperty<double>(
      read: () => value,
      write: (next) => value = next,
    );

    engine.to<double>(
      property,
      100,
      duration: 1,
      ease: Ease.linear,
      interpolate: (from, to, t) => from + (to - from) * t * t,
    );
    engine.tick(.5);
    expect(value, closeTo(25, 1e-9));
    engine.dispose();
  });

  test('live reverse preserves the current sample then runs backward', () {
    final engine = MotionEngine();
    engine.maxDelta = double.infinity;
    var value = 0.0;
    final handle = engine.toDouble(
      () => value,
      (next) => value = next,
      100,
      duration: 1,
      ease: Ease.linear,
    );

    engine.tick(.4);
    expect(value, closeTo(40, 1e-9));

    handle.reverse();
    expect(value, closeTo(40, 1e-9));

    engine.tick(.2);
    expect(value, closeTo(20, 1e-9));
    engine.tick(.2);
    expect(value, closeTo(0, 1e-9));
    expect(handle.isCompleted, isTrue);
    engine.dispose();
  });

  test('reverse preserves pause state', () {
    final engine = MotionEngine();
    engine.maxDelta = double.infinity;
    var value = 0.0;
    final handle = engine.toDouble(
      () => value,
      (next) => value = next,
      100,
      duration: 1,
      ease: Ease.linear,
    );

    engine.tick(.4);
    handle.pause();
    handle.reverse();
    expect(handle.isPaused, isTrue);
    expect(value, closeTo(40, 1e-9));

    engine.tick(.2);
    expect(value, closeTo(40, 1e-9));
    handle.resume();
    engine.tick(.2);
    expect(value, closeTo(20, 1e-9));
    engine.dispose();
  });

  test('reverse before delayed motion starts is a no-op', () {
    final engine = MotionEngine();
    engine.maxDelta = double.infinity;
    var value = 0.0;
    var starts = 0;
    final handle = engine.toDouble(
      () => value,
      (next) => value = next,
      100,
      duration: 1,
      delay: 1,
      ease: Ease.linear,
      onStart: () => starts++,
    );

    handle.reverse();
    expect(value, 0);
    expect(starts, 0);

    engine.tick(1.5);
    expect(starts, 1);
    expect(value, closeTo(50, 1e-9));
    expect(handle.isActive, isTrue);
    engine.dispose();
  });

  test('silent seek consumes initial delay and playback starts on next tick', () {
    final engine = MotionEngine();
    engine.maxDelta = double.infinity;
    var value = 0.0;
    var starts = 0;
    final handle = engine.toDouble(
      () => value,
      (next) => value = next,
      100,
      duration: 1,
      delay: 1,
      ease: Ease.linear,
      onStart: () => starts++,
    );

    handle.seek(.5);
    expect(starts, 0);
    expect(value, closeTo(50, 1e-9));

    engine.tick(.25);
    expect(value, closeTo(75, 1e-9));
    expect(starts, 1);
    engine.dispose();
  });

  test('silent seek clamps to cycle bounds without lifecycle callbacks', () {
    final engine = MotionEngine();
    engine.maxDelta = double.infinity;
    var value = 0.0;
    var starts = 0;
    final handle = engine.toDouble(
      () => value,
      (next) => value = next,
      100,
      duration: 1,
      ease: Ease.linear,
      onStart: () => starts++,
    );

    handle.seek(-3);
    expect(value, closeTo(0, 1e-9));
    expect(starts, 0);

    handle.seek(3);
    expect(value, closeTo(100, 1e-9));
    expect(handle.progress, 1);
    expect(starts, 0);
    engine.dispose();
  });

  test('repeatDelay holds the endpoint until the next cycle boundary', () {
    final engine = MotionEngine();
    engine.maxDelta = double.infinity;
    var value = 0.0;
    var repeats = 0;
    final handle = engine.toDouble(
      () => value,
      (next) => value = next,
      100,
      duration: .5,
      repeat: 1,
      repeatDelay: .25,
      ease: Ease.linear,
      onRepeat: (_) => repeats++,
    );

    engine.tick(.5);
    expect(value, closeTo(100, 1e-9));
    expect(repeats, 1);
    expect(handle.isActive, isTrue);

    engine.tick(.2);
    expect(value, closeTo(100, 1e-9));

    engine.tick(.05);
    expect(value, closeTo(0, 1e-9));

    engine.tick(.25);
    expect(value, closeTo(50, 1e-9));
    engine.tick(.25);
    expect(value, closeTo(100, 1e-9));
    expect(handle.isCompleted, isTrue);
    engine.dispose();
  });

  test('yoyo repeatDelay holds the directed endpoint', () {
    final engine = MotionEngine();
    engine.maxDelta = double.infinity;
    var value = 0.0;
    final handle = engine.toDouble(
      () => value,
      (next) => value = next,
      100,
      duration: .5,
      repeat: 1,
      repeatDelay: .25,
      yoyo: true,
      ease: Ease.linear,
    );

    engine.tick(.5);
    expect(value, closeTo(100, 1e-9));
    engine.tick(.25);
    expect(value, closeTo(100, 1e-9));
    engine.tick(.25);
    expect(value, closeTo(50, 1e-9));
    engine.tick(.25);
    expect(value, closeTo(0, 1e-9));
    expect(handle.isCompleted, isTrue);
    engine.dispose();
  });

  test('repeat timing is independent of host tick partitioning', () {
    double run(List<double> ticks) {
      final engine = MotionEngine();
      engine.maxDelta = double.infinity;
      var value = 0.0;
      final handle = engine.toDouble(
        () => value,
        (next) => value = next,
        100,
        duration: .5,
        repeat: 1,
        repeatDelay: .25,
        ease: Ease.linear,
      );
      for (final tick in ticks) {
        engine.tick(tick);
      }
      expect(handle.isCompleted, isTrue);
      engine.dispose();
      return value;
    }

    expect(run([1.25]), closeTo(100, 1e-9));
    expect(run([.5, .1, .15, .25, .25]), closeTo(100, 1e-9));
  });

  test('duration callback order is deterministic across repeat delay', () {
    final engine = MotionEngine();
    engine.maxDelta = double.infinity;
    var value = 0.0;
    final events = <String>[];
    engine.toDouble(
      () => value,
      (next) {
        value = next;
        events.add('write:${next.toStringAsFixed(0)}');
      },
      100,
      duration: .5,
      repeat: 1,
      repeatDelay: .25,
      ease: Ease.linear,
      onStart: () => events.add('start'),
      onUpdate: () => events.add('update'),
      onRepeat: (iteration) => events.add('repeat:$iteration'),
      onComplete: () => events.add('complete'),
    );

    engine.tick(.5);
    expect(events, ['start', 'write:100', 'update', 'repeat:1']);
    events.clear();

    engine.tick(.2);
    expect(events, isEmpty);
    engine.tick(.05);
    expect(events, ['write:0', 'update']);
    events.clear();

    engine.tick(.5);
    expect(events, ['write:100', 'update', 'complete']);
    engine.dispose();
  });

  test('overwrite before first tick cancels without starting old motion', () {
    final engine = MotionEngine();
    engine.maxDelta = double.infinity;
    final owner = Object();
    const property = MotionPropertyKey('x');
    var value = 0.0;
    final events = <String>[];

    final first = engine.toDouble(
      () => value,
      (next) => value = next,
      100,
      owner: owner,
      property: property,
      onStart: () => events.add('old-start'),
      onCancel: (reason) => events.add('old-cancel:$reason'),
    );
    final replacement = engine.toDouble(
      () => value,
      (next) => value = next,
      50,
      owner: owner,
      property: property,
      onStart: () => events.add('new-start'),
    );

    expect(first.isCancelled, isTrue);
    expect(replacement.isActive, isTrue);
    expect(events, ['old-cancel:MotionCancelReason.overwritten']);
    engine.tick(.1);
    expect(events, [
      'old-cancel:MotionCancelReason.overwritten',
      'new-start',
    ]);
    engine.dispose();
  });

  test('zero duration callback order is start update complete once', () {
    final engine = MotionEngine();
    engine.maxDelta = double.infinity;
    var value = 0.0;
    final events = <String>[];
    final handle = engine.toDouble(
      () => value,
      (next) {
        value = next;
        events.add('write');
      },
      1,
      duration: 0,
      onStart: () => events.add('start'),
      onUpdate: () => events.add('update'),
      onComplete: () => events.add('complete'),
    );

    expect(events, isEmpty);
    engine.tick(0);
    expect(events, ['start', 'write', 'update', 'complete']);
    expect(value, 1);
    expect(handle.isCompleted, isTrue);
    engine.tick(1);
    expect(events, ['start', 'write', 'update', 'complete']);
    engine.dispose();
  });

  test('invalid cascading defaults fail at assignment', () {
    final engine = MotionEngine();
    expect(
      () => engine.defaults = const MotionSpec(duration: -1),
      throwsArgumentError,
    );
    expect(
      () => engine.defaults = const MotionSpec(repeatDelay: -1),
      throwsArgumentError,
    );
    engine.dispose();
  });
}

GStage _stage([GRoot? root]) {
  final stage = GStage(root ?? GRoot(), maxDelta: 10);
  stage.mount();
  stage.setViewport(100, 100);
  return stage;
}

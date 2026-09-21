import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:graphx/graphx.dart';
import 'package:graphx_motion/graphx_motion.dart';

void main() {
  test('free double property has stable overwrite identity', () {
    final stage = GStage(GRoot(), maxDelta: 10);
    stage.mount();
    stage.setViewport(100, 100);
    stage.motion.engine.maxDelta = double.infinity;
    var value = 0.0;
    final property = MotionProperty<double>(
      read: () => value,
      write: (next) => value = next,
    );

    final first = stage.motion.to<double>(
      property,
      100,
      duration: 1,
      ease: Ease.linear,
    );
    stage.tick(.25);
    expect(value, closeTo(25, 1e-9));

    final replacement = stage.motion.to<double>(
      property,
      0,
      duration: .75,
      ease: Ease.linear,
    );
    expect(first.isCancelled, isTrue);
    expect(replacement.isActive, isTrue);

    stage.tick(.75);
    expect(value, closeTo(0, 1e-9));
    expect(replacement.isCompleted, isTrue);
    stage.dispose();
  });

  test('Color uses the same property API with an interpolation callback', () {
    final stage = GStage(GRoot(), maxDelta: 10);
    stage.mount();
    stage.setViewport(100, 100);
    stage.motion.engine.maxDelta = double.infinity;
    var value = const ui.Color(0xffff0000);
    final property = MotionProperty<ui.Color>(
      read: () => value,
      write: (next) => value = next,
      interpolate: MotionColors.hsl,
    );

    final handle = stage.motion.to(
      property,
      const ui.Color(0xff00ff00),
      duration: 1,
      ease: Ease.linear,
    );

    stage.tick(.5);
    expect(value.r, closeTo(1, 1e-9));
    expect(value.g, closeTo(1, 1e-9));
    expect(value.b, closeTo(0, 1e-9));

    stage.tick(.5);
    expect(handle.isCompleted, isTrue);
    expect(value, const ui.Color(0xff00ff00));
    stage.dispose();
  });

  test('custom value types only need one interpolation function', () {
    final engine = MotionEngine();
    engine.maxDelta = double.infinity;
    var value = (x: 0.0, y: 10.0);
    final property = MotionProperty<({double x, double y})>(
      read: () => value,
      write: (next) => value = next,
      interpolate: (from, to, t) => (
        x: from.x + (to.x - from.x) * t,
        y: from.y + (to.y - from.y) * t,
      ),
    );

    engine.to(
      property,
      (x: 20.0, y: 30.0),
      duration: 1,
      ease: Ease.linear,
    );
    engine.tick(.5);

    expect(value.x, closeTo(10, 1e-9));
    expect(value.y, closeTo(20, 1e-9));
  });

  test('heterogeneous targets run as one grouped runtime', () {
    final engine = MotionEngine();
    engine.maxDelta = double.infinity;
    final owner = Object();
    var radius = 40.0;
    var color = const ui.Color(0xffff0000);
    var updates = 0;

    final radiusMotion = MotionProperty<double>(
      owner: owner,
      read: () => radius,
      write: (value) => radius = value,
    );
    final colorMotion = MotionProperty<ui.Color>(
      owner: owner,
      read: () => color,
      write: (value) => color = value,
      interpolate: MotionColors.rgb,
    );

    final radiusTarget = radiusMotion.target(120);
    expect(engine.activeCount, 0, reason: 'target() must remain passive');

    final handle = engine.toMany(
      [radiusTarget, colorMotion.target(const ui.Color(0xff0000ff))],
      duration: 1,
      ease: Ease.linear,
      onUpdate: () => updates++,
    );

    expect(engine.activeCount, 1);
    engine.tick(.5);
    expect(radius, closeTo(80, 1e-9));
    expect(color.r, closeTo(.5, .01));
    expect(color.b, closeTo(.5, .01));
    expect(updates, 1, reason: 'group emits one update callback per sample');

    engine.tick(.5);
    expect(handle.isCompleted, isTrue);
    expect(radius, closeTo(120, 1e-9));
    expect(color, const ui.Color(0xff0000ff));
    expect(updates, 2);
    engine.dispose();
  });

  test('grouped generic overwrite removes only the conflicting property', () {
    final engine = MotionEngine();
    engine.maxDelta = double.infinity;
    final owner = Object();
    var radius = 0.0;
    var angle = 0.0;
    final radiusMotion = MotionProperty<double>(
      owner: owner,
      read: () => radius,
      write: (value) => radius = value,
    );
    final angleMotion = MotionProperty<double>(
      owner: owner,
      read: () => angle,
      write: (value) => angle = value,
    );

    final grouped = engine.toMany(
      [radiusMotion.target(100), angleMotion.target(200)],
      duration: 1,
      ease: Ease.linear,
    );
    engine.tick(.25);
    expect(radius, closeTo(25, 1e-9));
    expect(angle, closeTo(50, 1e-9));

    final radiusReplacement = engine.to<double>(
      radiusMotion,
      0,
      duration: .75,
      ease: Ease.linear,
    );
    expect(grouped.isActive, isTrue);
    expect(radiusReplacement.isActive, isTrue);

    engine.tick(.75);
    expect(radius, closeTo(0, 1e-9));
    expect(angle, closeTo(200, 1e-9));
    expect(grouped.isCompleted, isTrue);
    expect(radiusReplacement.isCompleted, isTrue);
    engine.dispose();
  });

  test('grouped generic targets require one explicit owner domain', () {
    final engine = MotionEngine();
    var a = 0.0;
    var b = 0.0;
    final first = MotionProperty<double>(
      read: () => a,
      write: (value) => a = value,
    );
    final second = MotionProperty<double>(
      read: () => b,
      write: (value) => b = value,
    );

    expect(
      () => engine.toMany([first.target(1), second.target(2)]),
      throwsArgumentError,
    );
    expect(engine.activeCount, 0);
    engine.dispose();
  });

  test('empty grouped target list completes synchronously without demand', () {
    final engine = MotionEngine();
    var completed = 0;

    final handle = engine.toMany(
      const <MotionTarget>[],
      onComplete: () => completed++,
    );

    expect(handle.isCompleted, isTrue);
    expect(completed, 1);
    expect(engine.activeCount, 0);
    expect(engine.wantsUpdate, isFalse);
    engine.dispose();
  });

  test('ease families remain plain callbacks', () {
    final EaseFunction bounce = Ease.bounce.easeOut;
    final EaseFunction elastic = Ease.elastic.easeOut;
    final EaseFunction bezier = Ease.bezier(.25, .1, .25, 1);

    expect(bounce(0), 0);
    expect(bounce(1), 1);
    expect(elastic(0), 0);
    expect(elastic(1), 1);
    expect(bezier(0), 0);
    expect(bezier(1), 1);
    expect(Ease.steps(4)(.6), .5);
  });
}

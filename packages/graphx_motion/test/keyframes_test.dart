import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:graphx/graphx.dart';
import 'package:graphx_motion/graphx_motion.dart';

void main() {
  test('generic keyframes are passive and deterministic under random seek', () {
    final engine = MotionEngine();
    engine.maxDelta = double.infinity;
    var value = 10.0;
    final property = MotionProperty<double>(
      read: () => value,
      write: (next) => value = next,
    );
    final clip = property.keyframes(duration: 2, ease: Ease.linear);
    clip.at(.25, 30);
    clip.at(.75, 90);

    final timeline = engine.timeline();
    timeline.add(clip);
    expect(engine.activeCount, 0);

    timeline.time = .25;
    expect(value, closeTo(20, 1e-9));

    timeline.time = 1;
    expect(value, closeTo(60, 1e-9));

    timeline.time = 1.75;
    expect(value, closeTo(90, 1e-9), reason: 'last key holds through clip end');

    timeline.time = 0;
    expect(value, closeTo(10, 1e-9), reason: 'sparse first key restores baseline');

    timeline.dispose();
    engine.dispose();
  });

  test('frame ease controls the segment ending at that frame', () {
    final engine = MotionEngine();
    engine.maxDelta = double.infinity;
    var value = 0.0;
    final property = MotionProperty<double>(
      read: () => value,
      write: (next) => value = next,
    );
    final timeline = engine.timeline();
    final frames = property.keyframes(duration: 1, ease: Ease.linear);
    frames.at(0, 0);
    frames.at(.5, 100, ease: (t) => t * t);
    frames.at(1, 200);
    timeline.add(frames);

    timeline.time = .25;
    expect(value, closeTo(25, 1e-9));
    timeline.time = .75;
    expect(value, closeTo(150, 1e-9));

    timeline.dispose();
    engine.dispose();
  });

  test('keyframe default ease inherits from its owning timeline', () {
    final engine = MotionEngine();
    engine.maxDelta = double.infinity;
    var value = 0.0;
    final property = MotionProperty<double>(
      read: () => value,
      write: (next) => value = next,
    );
    final timeline = engine.timeline(
      defaults: MotionSpec(ease: (t) => t * t),
    );
    final frames = property.keyframes(duration: 1);
    frames.at(0, 0);
    frames.at(1, 100);
    timeline.add(frames);

    timeline.time = .5;
    expect(value, closeTo(25, 1e-9));

    timeline.dispose();
    engine.dispose();
  });

  test('parallel keyframe tracks remain one retained composition', () {
    final engine = MotionEngine();
    engine.maxDelta = double.infinity;
    var x = 0.0;
    var y = 10.0;
    final owner = Object();
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
    final xFrames = xMotion.keyframes(duration: 1, ease: Ease.linear);
    xFrames.at(1, 100);
    final yFrames = yMotion.keyframes(duration: .5, ease: Ease.linear);
    yFrames.at(1, 30);
    final timeline = engine.timeline();
    timeline.add(MotionClip.parallel([xFrames, yFrames]));

    expect(timeline.duration, closeTo(1, 1e-9));
    timeline.time = .25;
    expect(x, closeTo(25, 1e-9));
    expect(y, closeTo(20, 1e-9));
    timeline.time = .75;
    expect(x, closeTo(75, 1e-9));
    expect(y, closeTo(30, 1e-9));

    timeline.dispose();
    engine.dispose();
  });

  test('node keyframes author multiple sparse tracks as one passive clip', () {
    final engine = MotionEngine();
    engine.maxDelta = double.infinity;
    final node = GNode();
    node.x = 10;
    node.y = 20;
    node.scaleX = 1;
    node.scaleY = 1;
    node.alpha = 1;

    final clip = node.motion.keyframes(
      (frames) {
        frames.at(0, y: 40, alpha: 0);
        frames.at(.5, x: 110, scale: 2);
        frames.at(1, x: 210, y: 20, scale: 1, alpha: 1);
      },
      duration: 1,
      ease: Ease.linear,
    );
    final timeline = engine.timeline();
    timeline.add(clip);

    timeline.time = .25;
    expect(node.x, closeTo(60, 1e-9), reason: 'x starts from its clip-start value');
    expect(node.y, closeTo(35, 1e-9));
    expect(node.alpha, closeTo(.25, 1e-9));
    expect(node.scaleX, closeTo(1.5, 1e-9));
    expect(node.scaleY, closeTo(1.5, 1e-9));

    timeline.time = .75;
    expect(node.x, closeTo(160, 1e-9));
    expect(node.y, closeTo(25, 1e-9));
    expect(node.alpha, closeTo(.75, 1e-9));
    expect(node.scaleX, closeTo(1.5, 1e-9));

    timeline.dispose();
    engine.dispose();
  });

  test('node keyframe shortest rotation uses circular interpolation', () {
    final engine = MotionEngine();
    engine.maxDelta = double.infinity;
    final node = GNode();
    node.rotation = math.pi * 1.75;
    final timeline = engine.timeline();
    timeline.add(
      node.motion.keyframes(
        (frames) {
          frames.at(1, rotation: math.pi * .25);
        },
        duration: 1,
        ease: Ease.linear,
        shortest: true,
      ),
    );

    timeline.time = .5;
    expect(node.rotation, closeTo(math.pi * 2, 1e-9));

    timeline.dispose();
    engine.dispose();
  });

  test('keyframe authoring validates positions and node values', () {
    final property = MotionProperty<double>(
      read: () => 0,
      write: (_) {},
    );
    final frames = property.keyframes(duration: 1);
    frames.at(.5, 1);
    expect(() => frames.at(.5, 2), throwsArgumentError);
    expect(() => frames.at(1.1, 2), throwsArgumentError);

    final node = GNode();
    expect(
      () => node.motion.keyframes(
        (f) => f.at(.5, scale: 2, scaleX: 3),
        duration: 1,
      ),
      throwsArgumentError,
    );
    expect(
      () => node.motion.keyframes(
        (f) => f.at(.5, x: double.nan),
        duration: 1,
      ),
      throwsArgumentError,
    );
  });
}

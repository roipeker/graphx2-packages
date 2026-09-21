import 'package:flutter_test/flutter_test.dart';
import 'package:graphx_motion/motion.dart';

void main() {
  test('overwrite replacement is one atomic demand interval', () {
    final engine = MotionEngine();
    engine.maxDelta = double.infinity;
    final owner = Object();
    const x = MotionPropertyKey('x');
    var value = 0.0;
    var wakes = 0;
    var idles = 0;
    engine.onWake = () => wakes++;
    engine.onIdle = () => idles++;

    final first = engine.toDouble(
      () => value,
      (next) => value = next,
      100,
      owner: owner,
      property: x,
      duration: 1,
      ease: Ease.linear,
    );
    expect(wakes, 1);
    expect(idles, 0);

    engine.tick(.2);
    expect(value, closeTo(20, 1e-9));

    final replacement = engine.toDouble(
      () => value,
      (next) => value = next,
      0,
      owner: owner,
      property: x,
      duration: 1,
      ease: Ease.linear,
      overwrite: Overwrite.all,
    );

    expect(first.isCancelled, isTrue);
    expect(replacement.isActive, isTrue);
    expect(engine.wantsUpdate, isTrue);
    expect(wakes, 1);
    expect(idles, 0);

    engine.tick(.5);
    expect(value, closeTo(10, 1e-9));

    replacement.cancel();
    expect(engine.wantsUpdate, isFalse);
    expect(wakes, 1);
    expect(idles, 1);
  });

  test('partial auto-overwrite does not expose idle', () {
    final engine = MotionEngine();
    engine.maxDelta = double.infinity;
    final owner = Object();
    const x = MotionPropertyKey('x');
    const y = MotionPropertyKey('y');
    var px = 0.0;
    var py = 0.0;
    var wakes = 0;
    var idles = 0;
    engine.onWake = () => wakes++;
    engine.onIdle = () => idles++;

    final grouped = engine.toProperties(
      [
        DoubleMotionProperty(
          property: x,
          read: () => px,
          write: (value) => px = value,
          to: 100,
        ),
        DoubleMotionProperty(
          property: y,
          read: () => py,
          write: (value) => py = value,
          to: 100,
        ),
      ],
      owner: owner,
      duration: 1,
      ease: Ease.linear,
    );
    expect(wakes, 1);

    engine.tick(.2);
    final replacement = engine.toDouble(
      () => px,
      (value) => px = value,
      200,
      owner: owner,
      property: x,
      duration: 1,
      ease: Ease.linear,
    );

    expect(grouped.isActive, isTrue);
    expect(replacement.isActive, isTrue);
    expect(wakes, 1);
    expect(idles, 0);

    grouped.cancel();
    expect(engine.wantsUpdate, isTrue);
    expect(idles, 0);
    replacement.cancel();
    expect(idles, 1);
  });
}

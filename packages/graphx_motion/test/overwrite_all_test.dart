import 'package:flutter_test/flutter_test.dart';
import 'package:graphx_motion/motion.dart';

void main() {
  test('Overwrite.all leaves exactly the newest owner runtime active', () {
    final engine = MotionEngine();
    engine.maxDelta = double.infinity;
    final owner = Object();
    const scaleX = MotionPropertyKey('scaleX');
    const scaleY = MotionPropertyKey('scaleY');
    var sx = 1.0;
    var sy = 1.0;
    final cancelled = <int>[];

    MotionHandle start(int id, double target) => engine.toProperties(
      [
        DoubleMotionProperty(
          property: scaleX,
          read: () => sx,
          write: (value) => sx = value,
          to: target,
        ),
        DoubleMotionProperty(
          property: scaleY,
          read: () => sy,
          write: (value) => sy = value,
          to: target,
        ),
      ],
      owner: owner,
      duration: .3,
      ease: Ease.linear,
      overwrite: Overwrite.all,
      onCancel: (_) => cancelled.add(id),
    );

    final first = start(1, 2);
    expect(engine.count(owner: owner), 1);

    final second = start(2, 1);
    expect(first.isCancelled, isTrue);
    expect(second.isActive, isTrue);
    expect(cancelled, [1]);
    expect(engine.count(owner: owner), 1);

    // Several replacements in the same event turn must still leave only the
    // final runtime active. Earlier runtimes may never receive an onStart tick,
    // but they are cancelled synchronously at creation time.
    final third = start(3, 2);
    final fourth = start(4, 1);
    final fifth = start(5, 2);

    expect(second.isCancelled, isTrue);
    expect(third.isCancelled, isTrue);
    expect(fourth.isCancelled, isTrue);
    expect(fifth.isActive, isTrue);
    expect(cancelled, [1, 2, 3, 4]);
    expect(engine.count(owner: owner), 1);

    engine.tick(.3);
    expect(fifth.isCompleted, isTrue);
    expect(sx, closeTo(2, 1e-9));
    expect(sy, closeTo(2, 1e-9));
    expect(engine.count(owner: owner), 0);
  });
}

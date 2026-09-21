import 'package:flutter_test/flutter_test.dart';
import 'package:graphx_motion/graphx_motion.dart';

void main() {
  test('Timeline callbacks at zero fire once on play', () {
    final engine = MotionEngine();
    engine.maxDelta = double.infinity;
    var value = 0.0;
    var calls = 0;
    final property = MotionProperty<double>(
      read: () => value,
      write: (next) => value = next,
    );

    final timeline = engine.timeline(
      defaults: const MotionSpec(duration: .5, ease: Ease.linear),
    );
    timeline.call(() => calls++, at: 0);
    timeline.to<double>(property, 1);
    timeline.play();

    engine.tick(.25);
    expect(calls, 1);
    expect(value, closeTo(.5, 1e-9));
    engine.tick(.25);
    expect(calls, 1);
    expect(timeline.isCompleted, isTrue);
    engine.dispose();
  });
}

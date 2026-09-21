import 'package:flutter_test/flutter_test.dart';
import 'package:graphx_motion/graphx_motion.dart';

void main() {
  test('Timeline wait advances append cursor without runtime work', () {
    final engine = MotionEngine();
    engine.maxDelta = double.infinity;
    var value = 0.0;
    final property = MotionProperty<double>(
      read: () => value,
      write: (next) => value = next,
    );

    final timeline = engine.timeline(
      defaults: const MotionSpec(duration: .5, ease: Ease.linear),
    );
    timeline.wait(.25);
    timeline.to<double>(property, 1);
    timeline.play();

    expect(timeline.duration, .75);
    engine.tick(.25);
    expect(value, 0);
    engine.tick(.25);
    expect(value, closeTo(.5, 1e-9));
    engine.tick(.25);
    expect(value, closeTo(1, 1e-9));
    expect(timeline.isCompleted, isTrue);
    engine.dispose();
  });
}

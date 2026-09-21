import 'package:flutter_test/flutter_test.dart';
import 'package:graphx_motion/graphx_motion.dart';

void main() {
  test('custom MotionProperty clip stays passive until root timeline play', () {
    final engine = MotionEngine();
    engine.maxDelta = double.infinity;
    var value = 0.0;
    final property = MotionProperty<double>(
      read: () => value,
      write: (next) => value = next,
    );

    final clip = property.clip(1, duration: 1, ease: Ease.linear);
    expect(engine.activeCount, 0);

    final timeline = engine.timeline();
    timeline.add(clip);
    timeline.play();
    expect(engine.activeCount, 2, reason: 'one leaf runtime + one root clock');
    engine.tick(1);
    expect(value, 1);
    expect(timeline.isCompleted, isTrue);
    engine.dispose();
  });
}

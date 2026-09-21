import 'package:flutter_test/flutter_test.dart';
import 'package:graphx/graphx.dart';
import 'package:graphx_motion/graphx_motion.dart';

void main() {
  test('custom owners remain caller-managed', () {
    final stage = GStage(GRoot());
    stage.mount();
    stage.setViewport(320, 200);
    stage.motion.engine.maxDelta = double.infinity;

    final owner = Object();
    var value = 0.0;

    final handle = stage.motion.spring(
      0,
      100,
      owner: owner,
      onValue: (next) => value = next,
    );

    stage.tick(1 / 60);
    expect(handle.isActive, isTrue);
    expect(value, greaterThan(0));

    stage.motion.cancel(owner: owner);
    expect(handle.isCancelled, isTrue);

    stage.dispose();
  });
}

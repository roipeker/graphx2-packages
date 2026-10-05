import 'package:flutter_test/flutter_test.dart';
import 'package:graphx_particles/src/particle_store.dart';

void main() {
  test('frame index follows particles through swap-remove', () {
    final store = ParticleStore(3);
    for (var i = 0; i < 3; ++i) {
      store.add(
        x: i.toDouble(),
        y: 0,
        vx: 0,
        vy: 0,
        life: 10,
        rotation: 0,
        angularVelocity: 0,
        scale: 1,
        baseColor: 0xffffffff,
        frameIndex: 10 + i,
      );
    }

    store.removeAt(1);
    expect(store.count, 2);
    expect(store.x[1], 2);
    expect(store.frameIndex[1], 12);
  });
}

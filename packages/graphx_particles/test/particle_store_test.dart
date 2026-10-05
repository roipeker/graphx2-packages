import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:graphx_particles/src/particle_store.dart';

void main() {
  ParticleStore store(int capacity) => ParticleStore(capacity);

  int add(ParticleStore store, double x, {double life = 10}) => store.add(
    x: x,
    y: 0,
    vx: 0,
    vy: 0,
    life: life,
    rotation: 0,
    angularVelocity: 0,
    scale: 1,
    baseColor: 0xffffffff,
  );

  test('capacity is fixed', () {
    expect(() => ParticleStore(-1), throwsArgumentError);
    final particles = store(1);
    add(particles, 1);
    expect(particles.isFull, isTrue);
    expect(() => add(particles, 2), throwsStateError);
  });

  test('swap-remove keeps active storage packed', () {
    final particles = store(3);
    add(particles, 1);
    add(particles, 2);
    add(particles, 3);

    particles.removeAt(1);

    expect(particles.count, 2);
    expect(particles.x[0], 1);
    expect(particles.x[1], 3);
    expect(particles.oldest, 0);
    expect(particles.newest, 1);
    expect(particles.next[0], 1);
    expect(particles.previous[1], 0);
  });

  test('lifetime endpoint storage is lazy and follows swap-remove', () {
    final particles = store(3);
    expect(particles.endpointFlags, isNull);
    expect(particles.endScale, isNull);
    expect(particles.endColor, isNull);

    particles.enableEndScale();
    expect(particles.endpointFlags, isNotNull);
    expect(particles.endScale, isNotNull);
    expect(particles.endColor, isNull);

    particles.add(
      x: 1,
      y: 0,
      vx: 0,
      vy: 0,
      life: 10,
      rotation: 0,
      angularVelocity: 0,
      scale: 1,
      baseColor: 0xff112233,
      particleEndScale: 2,
    );
    particles.add(
      x: 2,
      y: 0,
      vx: 0,
      vy: 0,
      life: 10,
      rotation: 0,
      angularVelocity: 0,
      scale: 1,
      baseColor: 0xff445566,
      particleEndScale: 3,
      particleEndColor: 0xff778899,
    );
    particles.add(
      x: 3,
      y: 0,
      vx: 0,
      vy: 0,
      life: 10,
      rotation: 0,
      angularVelocity: 0,
      scale: 1,
      baseColor: 0xffabcdef,
    );

    expect(particles.endColor, isNotNull);
    expect(
      particles.endpointFlags![0],
      ParticleStore.endpointScaleFlag,
    );
    expect(
      particles.endpointFlags![1],
      ParticleStore.endpointScaleFlag | ParticleStore.endpointColorFlag,
    );
    expect(particles.endpointFlags![2], 0);

    particles.removeAt(0); // slot 2 moves into slot 0.
    expect(particles.x[0], 3);
    expect(particles.endpointFlags![0], 0);

    particles.removeAt(0); // slot 1 moves into slot 0 with both endpoints.
    expect(particles.x[0], 2);
    expect(
      particles.endpointFlags![0],
      ParticleStore.endpointScaleFlag | ParticleStore.endpointColorFlag,
    );
    expect(particles.endScale![0], 3);
    expect(particles.endColor![0], 0xff778899);
  });

  test('oldest recycling remains O(1) across swapped slots', () {
    final particles = store(4);
    add(particles, 10);
    add(particles, 20);
    add(particles, 30);
    add(particles, 40);

    particles.removeAt(1); // moves 40 into slot 1; order is 10, 30, 40.
    expect(particles.removeOldest(), 0);
    expect(particles.count, 2);

    // 40 moves again, but the order list still identifies 30 as oldest.
    expect(particles.x[particles.oldest], 30);
    particles.removeOldest();
    expect(particles.count, 1);
    expect(particles.x[particles.oldest], 40);
  });

  test('lifetime expiration handles swap-remove during iteration', () {
    final particles = store(4);
    add(particles, 1, life: .1);
    add(particles, 2, life: 2);
    add(particles, 3, life: .1);
    add(particles, 4, life: 2);

    expect(
      particles.step(
        .2,
        accelerationX: 0,
        accelerationY: 0,
        drag: 0,
      ),
      2,
    );
    expect(particles.count, 2);
    expect(particles.x.take(2).toSet(), <double>{2, 4});
  });

  test('constant acceleration uses exact kinematics for a step', () {
    final particles = store(1);
    particles.add(
      x: 2,
      y: 3,
      vx: 4,
      vy: -2,
      life: 10,
      rotation: .5,
      angularVelocity: 2,
      scale: 1,
      baseColor: 0xffffffff,
    );

    particles.step(
      .25,
      accelerationX: 8,
      accelerationY: 12,
      drag: 0,
    );

    expect(particles.x[0], closeTo(3.25, 1e-5));
    expect(particles.y[0], closeTo(2.875, 1e-5));
    expect(particles.vx[0], closeTo(6, 1e-5));
    expect(particles.vy[0], closeTo(1, 1e-5));
    expect(particles.rotation[0], closeTo(1, 1e-5));
  });

  test('drag follows the analytical exponential solution', () {
    final particles = store(1);
    particles.add(
      x: 0,
      y: 0,
      vx: 10,
      vy: -4,
      life: 10,
      rotation: 0,
      angularVelocity: 0,
      scale: 1,
      baseColor: 0xffffffff,
    );

    const dt = .5;
    const drag = 2.0;
    const ax = 6.0;
    const ay = -2.0;
    particles.step(
      dt,
      accelerationX: ax,
      accelerationY: ay,
      drag: drag,
    );

    final decay = math.exp(-drag * dt);
    final terminalX = ax / drag;
    final terminalY = ay / drag;
    final factor = (1 - decay) / drag;
    expect(
      particles.x[0],
      closeTo(terminalX * dt + (10 - terminalX) * factor, 1e-5),
    );
    expect(
      particles.y[0],
      closeTo(terminalY * dt + (-4 - terminalY) * factor, 1e-5),
    );
    expect(
      particles.vx[0],
      closeTo(terminalX + (10 - terminalX) * decay, 1e-5),
    );
    expect(
      particles.vy[0],
      closeTo(terminalY + (-4 - terminalY) * decay, 1e-5),
    );
  });

  test('sub-frame advance removes a particle that dies before frame end', () {
    final particles = store(1);
    final index = add(particles, 0, life: .1);
    expect(
      particles.advanceAt(
        index,
        .2,
        accelerationX: 0,
        accelerationY: 0,
        drag: 0,
      ),
      isFalse,
    );
    expect(particles.count, 0);
  });
}

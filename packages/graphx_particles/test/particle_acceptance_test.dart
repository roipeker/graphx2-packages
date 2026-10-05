import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:graphx/graphx.dart';
import 'package:graphx_particles/graphx_particles.dart';
import 'package:graphx_paths/graphx_paths.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('curve endpoints and deterministic capacity policy stay exact', () async {
    final curve = GParticleCurve.stops(<double>[.25, 2, .5]);
    expect(curve.evaluate(0), closeTo(.25, 1e-6));
    expect(curve.evaluate(1), closeTo(.5, 1e-6));

    final fixture = await _Fixture.create(capacity: 2);
    addTearDown(fixture.dispose);
    fixture.emitter.life = const GParticleRange(10);

    expect(fixture.emitter.burst(3), 2);
    expect(fixture.emitter.activeCount, 2);
    expect(fixture.emitter.stats.droppedLastFrame, 1);

    fixture.emitter.overflow = GParticleOverflow.recycleOldest;
    expect(fixture.emitter.burst(2), 2);
    expect(fixture.emitter.activeCount, 2);
    expect(fixture.emitter.stats.recycledLastFrame, 2);
  });

  test('stage updates expire particles and release update demand', () async {
    final fixture = await _Fixture.create(capacity: 4);
    addTearDown(fixture.dispose);
    fixture.emitter.life = const GParticleRange(.15);

    fixture.emitter.burst(1);
    expect(fixture.emitter.updatesEnabled, isTrue);
    fixture.stage.tick(.1);
    expect(fixture.emitter.activeCount, 1);
    fixture.stage.tick(.1);
    expect(fixture.emitter.activeCount, 0);
    expect(fixture.emitter.updatesEnabled, isFalse);
  });

  test('local and world simulation preserve their coordinate contracts', () async {
    final local = await _Fixture.create(capacity: 4);
    final world = await _Fixture.create(capacity: 4);
    addTearDown(local.dispose);
    addTearDown(world.dispose);

    local.emitter.particleScale = const GParticleRange(0);
    local.emitter.life = const GParticleRange(10);
    local.emitter.setPosition(10, 20);
    local.emitter.burst(1);

    world.emitter.particleScale = const GParticleRange(0);
    world.emitter.life = const GParticleRange(10);
    world.emitter.space = GParticleSpace.world;
    world.emitter.setPosition(10, 20);
    world.emitter.burst(1);

    local.emitter.setPosition(30, 40);
    world.emitter.setPosition(30, 40);

    final localBounds = local.emitter.getBounds(local.root);
    final worldBounds = world.emitter.getBounds(world.root);
    expect(localBounds.x1, closeTo(30, 1e-5));
    expect(localBounds.y1, closeTo(40, 1e-5));
    expect(worldBounds.x1, closeTo(10, 1e-5));
    expect(worldBounds.y1, closeTo(20, 1e-5));
  });

  test('path emission uses retained graphx_paths tangent sampling', () async {
    final fixture = await _Fixture.create(capacity: 4);
    addTearDown(fixture.dispose);
    final path = GPath();
    path.moveTo(0, 0);
    path.lineTo(100, 0);

    fixture.emitter.shape = GParticleShape.path(path);
    fixture.emitter.directionMode = GParticleDirectionMode.tangent;
    fixture.emitter.angle = const GParticleRange(0);
    fixture.emitter.speed = const GParticleRange(10);
    fixture.emitter.particleScale = const GParticleRange(0);
    fixture.emitter.life = const GParticleRange(10);
    fixture.emitter.burst(1);

    final before = fixture.emitter.localBounds;
    fixture.stage.tick(.1);
    final after = fixture.emitter.localBounds;
    expect(after.x1 - before.x1, closeTo(1, 1e-4));
    expect(after.y1, closeTo(before.y1, 1e-5));
  });

  test('same-image particles render as one atlas batch', () async {
    final fixture = await _Fixture.create(capacity: 16);
    addTearDown(fixture.dispose);
    fixture.emitter.life = const GParticleRange(10);
    fixture.emitter.burst(12);

    final session = GRenderSession(width: 200, height: 200);
    final capture = await session.renderStage(fixture.stage);
    expect(fixture.emitter.stats.drawCalls, 1);
    expect(fixture.emitter.activeCount, 12);
    expect(fixture.emitter.stats.submittedParticles, 16);
    capture.dispose();
    session.dispose();
  });

  test('force fields and kill constraints operate inside packed simulation', () async {
    final fixture = await _Fixture.create(capacity: 4);
    addTearDown(fixture.dispose);
    fixture.emitter.life = const GParticleRange(10);
    fixture.emitter.particleScale = const GParticleRange(0);
    fixture.emitter.fields = <GParticleField>[
      GParticleField.wind(x: 100, y: 0),
    ];
    fixture.emitter.burst(1);

    final before = fixture.emitter.localBounds;
    fixture.stage.tick(.1);
    final after = fixture.emitter.localBounds;
    expect(after.x1, greaterThan(before.x1));

    fixture.emitter.constraints = <GParticleConstraint>[
      GParticleConstraint.bounds(
        GRect(-1, -1, 2, 2),
        response: GParticleConstraintResponse.kill,
      ),
    ];
    fixture.stage.tick(.1);
    expect(fixture.emitter.activeCount, 0);
  });

  test('secondary death emission and prewarm remain deterministic', () async {
    final source = await _Fixture.create(capacity: 4);
    final target = await _Fixture.create(capacity: 16);
    addTearDown(source.dispose);
    addTearDown(target.dispose);

    // Secondary emitters must share a Stage, so move both emitters into one tree.
    target.root.removeChild(target.emitter);
    source.root.addChild(target.emitter);
    target.stage.dispose();

    source.emitter.life = const GParticleRange(.05);
    target.emitter.life = const GParticleRange(10);
    source.emitter.onDeath = GParticleSpawn(target.emitter, count: 2);
    source.emitter.burst(1);
    source.stage.tick(.1);
    expect(target.emitter.activeCount, 2);

    target.emitter.clear();
    target.emitter.rate = 20;
    target.emitter.prewarm(.5, step: .1);
    expect(target.emitter.activeCount, 10);
    expect(target.emitter.isRunning, isFalse);
  });

  test('line trails add one retained draw alongside particle sprites', () async {
    final fixture = await _Fixture.create(capacity: 4);
    addTearDown(fixture.dispose);
    fixture.emitter.life = const GParticleRange(10);
    fixture.emitter.speed = const GParticleRange(40);
    fixture.emitter.angle = const GParticleRange(0);
    fixture.emitter.trail = GParticleTrail(samples: 4, duration: .5, width: 2);
    fixture.emitter.burst(1);
    fixture.stage.tick(.1);
    fixture.stage.tick(.1);

    final session = GRenderSession(width: 200, height: 200);
    final capture = await session.renderStage(fixture.stage);
    expect(fixture.emitter.stats.drawCalls, 2);
    capture.dispose();
    session.dispose();
  });
}

final class _Fixture {
  _Fixture({
    required this.owner,
    required this.emitter,
    required this.root,
    required this.stage,
  });

  final GTexture owner;
  final GParticleEmitter emitter;
  final GRoot root;
  final GStage stage;

  static Future<_Fixture> create({required int capacity}) async {
    final owner = GTexture.owned(await _makeImage());
    final emitter = GParticleEmitter(
      texture: owner,
      capacity: capacity,
      seed: 42,
    );
    final root = GRoot();
    root.addChild(emitter);
    final stage = GStage(root, maxDelta: 1.0);
    stage.mount();
    stage.setViewport(200, 200);
    return _Fixture(owner: owner, emitter: emitter, root: root, stage: stage);
  }

  void dispose() {
    if (!stage.isDisposed) stage.dispose();
    if (!owner.isDisposed) owner.dispose();
  }
}

Future<ui.Image> _makeImage() async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final paint = ui.Paint();
  paint.color = const ui.Color(0xffffffff);
  canvas.drawRect(const ui.Rect.fromLTWH(0, 0, 4, 4), paint);
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(4, 4);
  } finally {
    picture.dispose();
  }
}

import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:graphx/graphx_extension.dart';
import 'package:graphx_motion/graphx_motion.dart';

void main() {
  test('image instance motion keeps independent property overwrite', () async {
    final texture = await _texture();
    final root = GRoot();
    final stage = GStage(root, maxDelta: 10);
    stage.mount();
    stage.setViewport(320, 200);
    stage.motion.engine.maxDelta = double.infinity;
    final batch = root.addChild(GImageBatch());
    final instance = batch.add(texture);

    expect(instance.batch, same(batch));

    final grouped = instance.motion.to(
      x: 100,
      y: 80,
      rotation: 1,
      scale: 2,
      alpha: .5,
      duration: 1,
      ease: Ease.linear,
      hook: #move,
    );

    stage.tick(.5);
    expect(instance.x, closeTo(50, 1e-9));
    expect(instance.y, closeTo(40, 1e-9));
    expect(instance.rotation, closeTo(.5, 1e-9));
    expect(instance.scale, closeTo(1.5, 1e-9));
    expect(instance.alpha, closeTo(.75, 1e-9));

    final xOnly = instance.motion.to(
      x: 200,
      duration: .5,
      ease: Ease.linear,
    );

    stage.tick(.5);
    expect(xOnly.isCompleted, isTrue);
    expect(grouped.isCompleted, isTrue);
    expect(instance.x, closeTo(200, 1e-9));
    expect(instance.y, closeTo(80, 1e-9));
    expect(instance.rotation, closeTo(1, 1e-9));
    expect(instance.scale, closeTo(2, 1e-9));
    expect(instance.alpha, closeTo(.5, 1e-9));

    stage.dispose();
    texture.dispose();
  });

  test('removed image instance cancels its stage-owned motion', () async {
    final texture = await _texture();
    final root = GRoot();
    final stage = GStage(root, maxDelta: 10);
    stage.mount();
    stage.setViewport(320, 200);
    stage.motion.engine.maxDelta = double.infinity;
    final batch = root.addChild(GImageBatch());
    final instance = batch.add(texture);

    final handle = instance.motion.spring(x: 200, spring: Spring.slow);
    stage.tick(1 / 60);
    expect(handle.isActive, isTrue);

    instance.remove();
    expect(instance.batch, isNull);
    stage.tick(1 / 60);

    expect(handle.isCancelled, isTrue);
    expect(stage.motion.wantsUpdate, isFalse);

    stage.dispose();
    texture.dispose();
  });

  test('spring keeps strict instance scale and alpha domains valid', () async {
    final texture = await _texture();
    final root = GRoot();
    final stage = GStage(root, maxDelta: 10);
    stage.mount();
    stage.setViewport(320, 200);
    stage.motion.engine.maxDelta = double.infinity;
    final batch = root.addChild(GImageBatch());
    final instance = batch.add(texture, scale: 1, alpha: 1);

    final handle = instance.motion.spring(
      scale: 0,
      alpha: 0,
      spring: Spring.wobbly,
    );

    for (var i = 0; i < 240 && handle.isActive; ++i) {
      stage.tick(1 / 60);
      expect(instance.scale, greaterThanOrEqualTo(0));
      expect(instance.alpha, inInclusiveRange(0, 1));
    }

    expect(handle.isCompleted, isTrue);
    expect(instance.scale, 0);
    expect(instance.alpha, 0);

    stage.dispose();
    texture.dispose();
  });

  test('instance color motion converts wide gamut to packed sRGB boundary', () async {
    final texture = await _texture();
    final root = GRoot();
    final stage = GStage(root, maxDelta: 10);
    stage.mount();
    stage.setViewport(320, 200);
    stage.motion.engine.maxDelta = double.infinity;
    final batch = root.addChild(GImageBatch());
    final instance = batch.add(texture);
    const target = ui.Color.from(
      alpha: 1,
      red: .15,
      green: .9,
      blue: .25,
      colorSpace: ui.ColorSpace.displayP3,
    );
    final expected = target.withValues(colorSpace: ui.ColorSpace.sRGB);

    final handle = instance.motion.toColor(
      target,
      duration: 1,
      ease: Ease.linear,
    );

    stage.tick(1);

    expect(handle.isCompleted, isTrue);
    expect(instance.color.colorSpace, ui.ColorSpace.sRGB);
    expect(instance.color.r, closeTo(expected.r, 1e-9));
    expect(instance.color.g, closeTo(expected.g, 1e-9));
    expect(instance.color.b, closeTo(expected.b, 1e-9));

    stage.dispose();
    texture.dispose();
  });
}

Future<GTexture> _texture() async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final paint = ui.Paint();
  paint.color = const ui.Color(0xffffffff);
  canvas.drawRect(const ui.Rect.fromLTWH(0, 0, 2, 2), paint);
  final picture = recorder.endRecording();
  final image = await picture.toImage(2, 2);
  picture.dispose();
  return GTexture.owned(image);
}

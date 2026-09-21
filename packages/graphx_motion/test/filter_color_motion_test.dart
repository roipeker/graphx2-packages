import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:graphx/graphx_extension.dart';
import 'package:graphx_motion/graphx_motion.dart';

void main() {
  test('filter numeric and generic color properties coexist independently', () {
    final root = GRoot();
    final stage = GStage(root, maxDelta: 10);
    stage.mount();
    stage.setViewport(320, 200);
    stage.motion.engine.maxDelta = double.infinity;
    final node = GNode();
    root.addChild(node);
    final glow = GGlowFilter(
      blurX: 4,
      blurY: 4,
      color: const ui.Color(0xffff0000),
    );
    node.filters = [glow];

    final colorProperty = MotionProperty<ui.Color>(
      owner: glow,
      property: const MotionPropertyKey('GGlowFilter.color'),
      read: () => glow.color,
      write: (value) => glow.color = value,
      interpolate: MotionColors.hsl,
    );

    final numeric = glow.motion.to(
      blurX: 20,
      blurY: 12,
      duration: 1,
      ease: Ease.linear,
      hook: #shape,
    );
    final color = stage.motion.to(
      colorProperty,
      const ui.Color(0xff00ff00),
      duration: 1,
      ease: Ease.linear,
      hook: #color,
    );

    stage.tick(.5);
    expect(numeric.isActive, isTrue);
    expect(color.isActive, isTrue);
    expect(glow.blurX, closeTo(12, 1e-9));
    expect(glow.blurY, closeTo(8, 1e-9));

    final replacement = stage.motion.to(
      colorProperty,
      const ui.Color(0xff0000ff),
      duration: .5,
      ease: Ease.linear,
    );

    expect(color.isCancelled, isTrue);
    expect(numeric.isActive, isTrue);

    stage.tick(.5);
    expect(replacement.isCompleted, isTrue);
    expect(numeric.isCompleted, isTrue);
    expect(glow.blurX, 20);
    expect(glow.blurY, 12);
    expect(glow.color, const ui.Color(0xff0000ff));
    stage.dispose();
  });

  test('two declared Color properties have independent identities', () {
    final root = GRoot();
    final stage = GStage(root, maxDelta: 10);
    stage.mount();
    stage.setViewport(320, 200);
    stage.motion.engine.maxDelta = double.infinity;
    final node = GNode();
    root.addChild(node);
    final bevel = GBevelFilter();
    node.filters = [bevel];

    final highlight = MotionProperty<ui.Color>(
      owner: bevel,
      property: const MotionPropertyKey('GBevelFilter.highlightColor'),
      read: () => bevel.highlightColor,
      write: (value) => bevel.highlightColor = value,
      interpolate: MotionColors.rgb,
    );
    final shadow = MotionProperty<ui.Color>(
      owner: bevel,
      property: const MotionPropertyKey('GBevelFilter.shadowColor'),
      read: () => bevel.shadowColor,
      write: (value) => bevel.shadowColor = value,
      interpolate: MotionColors.rgb,
    );

    final a = stage.motion.to(
      highlight,
      const ui.Color(0xffff0000),
      duration: 1,
      ease: Ease.linear,
    );
    final b = stage.motion.to(
      shadow,
      const ui.Color(0xff0000ff),
      duration: 1,
      ease: Ease.linear,
    );

    stage.tick(1);
    expect(a.isCompleted, isTrue);
    expect(b.isCompleted, isTrue);
    expect(bevel.highlightColor, const ui.Color(0xffff0000));
    expect(bevel.shadowColor, const ui.Color(0xff0000ff));
    stage.dispose();
  });
}

import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:graphx_motion/graphx_motion.dart';

void main() {
  group('MotionColors', () {
    test('rgb delegates normal gamut conversion to dart:ui', () {
      const srgb = ui.Color.from(
        alpha: 1,
        red: 1,
        green: 0,
        blue: 0,
        colorSpace: ui.ColorSpace.sRGB,
      );
      const p3 = ui.Color.from(
        alpha: 1,
        red: 0,
        green: 1,
        blue: 0,
        colorSpace: ui.ColorSpace.displayP3,
      );

      final value = MotionColors.rgb(srgb, p3, .5);
      expect(value.colorSpace, ui.ColorSpace.displayP3);
    });

    test('rgb preserves extended sRGB channels', () {
      const from = ui.Color.from(
        alpha: 1,
        red: 1.4,
        green: -.2,
        blue: .1,
        colorSpace: ui.ColorSpace.extendedSRGB,
      );
      const to = ui.Color.from(
        alpha: 1,
        red: 2,
        green: .4,
        blue: .3,
        colorSpace: ui.ColorSpace.extendedSRGB,
      );

      final value = MotionColors.rgb(from, to, .5);
      expect(value.colorSpace, ui.ColorSpace.extendedSRGB);
      expect(value.r, closeTo(1.7, 1e-12));
      expect(value.g, closeTo(.1, 1e-12));
    });

    test('hsl/hsv preserve the wider normal-gamut working space', () {
      const srgb = ui.Color.from(
        alpha: 1,
        red: .9,
        green: .2,
        blue: .1,
        colorSpace: ui.ColorSpace.sRGB,
      );
      const p3 = ui.Color.from(
        alpha: 1,
        red: .1,
        green: .8,
        blue: .4,
        colorSpace: ui.ColorSpace.displayP3,
      );

      final hsl = MotionColors.hsl(srgb, p3, .5);
      final hsv = MotionColors.hsv(srgb, p3, .5);

      expect(hsl.colorSpace, ui.ColorSpace.displayP3);
      expect(hsv.colorSpace, ui.ColorSpace.displayP3);
      expect(MotionColors.hsl(srgb, p3, 0), same(srgb));
      expect(MotionColors.hsl(srgb, p3, 1), same(p3));
    });

    test('hsl/hsv reject extended sRGB', () {
      const extended = ui.Color.from(
        alpha: 1,
        red: 1.3,
        green: .2,
        blue: .1,
        colorSpace: ui.ColorSpace.extendedSRGB,
      );
      const normal = ui.Color(0xff00ff00);

      expect(() => MotionColors.hsl(extended, normal, .5), throwsArgumentError);
      expect(() => MotionColors.hsv(normal, extended, .5), throwsArgumentError);
    });

    test('hsl uses shortest circular hue path', () {
      const from = ui.Color(0xffff002b);
      const to = ui.Color(0xffff2b00);
      final mid = MotionColors.hsl(from, to, .5);

      expect(mid.r, greaterThan(.95));
      expect(mid.g, lessThan(.2));
      expect(mid.b, lessThan(.2));
    });
  });
}

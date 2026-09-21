import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart' show HSLColor, HSVColor;
import 'package:graphx_motion/motion.dart';

import 'stage_motion.dart';

/// Interpolation space for immutable [ui.Color] values.
enum MotionColorSpace { rgb, hsl, hsv }

/// Temporary source-compatibility name for internal adapters.
@Deprecated('Use MotionColorSpace.')
typedef ColorLerpMode = MotionColorSpace;

/// Color interpolation callbacks usable directly by [MotionProperty].
abstract final class MotionColors {
  static ui.Color rgb(ui.Color from, ui.Color to, double t) => _lerpRgb(from, to, t);

  static ui.Color hsl(ui.Color from, ui.Color to, double t) =>
      _lerpModel(from, to, t, MotionColorSpace.hsl, true);

  static ui.Color hsv(ui.Color from, ui.Color to, double t) =>
      _lerpModel(from, to, t, MotionColorSpace.hsv, true);

  static MotionInterpolator<ui.Color> forSpace(MotionColorSpace space) => switch (space) {
    MotionColorSpace.rgb => rgb,
    MotionColorSpace.hsl => hsl,
    MotionColorSpace.hsv => hsv,
  };

  static ui.Color lerp(
    ui.Color from,
    ui.Color to,
    double t, {
    MotionColorSpace space = MotionColorSpace.rgb,
    @Deprecated('Hue interpolation is shortest-path by default.') bool shortestHue = true,
    @Deprecated('Use space.') MotionColorSpace? mode,
  }) {
    final resolved = mode ?? space;
    if (resolved == MotionColorSpace.rgb) return _lerpRgb(from, to, t);
    return _lerpModel(from, to, t, resolved, shortestHue);
  }

  static HSLColor lerpHsl(
    HSLColor from,
    HSLColor to,
    double t, {
    bool shortestHue = true,
  }) => HSLColor.fromAHSL(
    _clamp01(_lerp(from.alpha, to.alpha, t)),
    _lerpHue(from.hue, to.hue, t, shortestHue),
    _clamp01(_lerp(from.saturation, to.saturation, t)),
    _clamp01(_lerp(from.lightness, to.lightness, t)),
  );

  static HSVColor lerpHsv(
    HSVColor from,
    HSVColor to,
    double t, {
    bool shortestHue = true,
  }) => HSVColor.fromAHSV(
    _clamp01(_lerp(from.alpha, to.alpha, t)),
    _lerpHue(from.hue, to.hue, t, shortestHue),
    _clamp01(_lerp(from.saturation, to.saturation, t)),
    _clamp01(_lerp(from.value, to.value, t)),
  );
}

ui.Color _lerpModel(
  ui.Color from,
  ui.Color to,
  double t,
  MotionColorSpace space,
  bool shortestHue,
) {
  if (t == 0.0) return from;
  if (t == 1.0) return to;
  _validateModelSpace(from, to);
  final working = _workingSpace(from, to);
  final a = _inSpace(from, working);
  final b = _inSpace(to, working);
  return switch (space) {
    MotionColorSpace.rgb => _lerpRgb(a, b, t),
    MotionColorSpace.hsl => _hslToColor(
      MotionColors.lerpHsl(
        _hslFromColor(a),
        _hslFromColor(b),
        t,
        shortestHue: shortestHue,
      ),
      working,
    ),
    MotionColorSpace.hsv => _hsvToColor(
      MotionColors.lerpHsv(
        _hsvFromColor(a),
        _hsvFromColor(b),
        t,
        shortestHue: shortestHue,
      ),
      working,
    ),
  };
}

void _validateModelSpace(ui.Color from, ui.Color to) {
  if (from.colorSpace == ui.ColorSpace.extendedSRGB ||
      to.colorSpace == ui.ColorSpace.extendedSRGB) {
    throw ArgumentError(
      'HSL/HSV interpolation does not accept extendedSRGB. '
      'Use MotionColors.rgb or tone-map first.',
    );
  }
}

ui.Color _lerpRgb(ui.Color from, ui.Color to, double t) {
  if (t == 0.0) return from;
  if (t == 1.0) return to;
  if (from.colorSpace == ui.ColorSpace.extendedSRGB ||
      to.colorSpace == ui.ColorSpace.extendedSRGB) {
    final a = _inSpace(from, ui.ColorSpace.extendedSRGB);
    final b = _inSpace(to, ui.ColorSpace.extendedSRGB);
    return ui.Color.from(
      alpha: _clamp01(_lerp(a.a, b.a, t)),
      red: _lerp(a.r, b.r, t),
      green: _lerp(a.g, b.g, t),
      blue: _lerp(a.b, b.b, t),
      colorSpace: ui.ColorSpace.extendedSRGB,
    );
  }
  return ui.Color.lerp(from, to, t)!;
}

ui.ColorSpace _workingSpace(ui.Color from, ui.Color to) =>
    from.colorSpace == ui.ColorSpace.displayP3 || to.colorSpace == ui.ColorSpace.displayP3
    ? ui.ColorSpace.displayP3
    : ui.ColorSpace.sRGB;

ui.Color _inSpace(ui.Color color, ui.ColorSpace colorSpace) =>
    color.colorSpace == colorSpace ? color : color.withValues(colorSpace: colorSpace);

HSLColor _hslFromColor(ui.Color color) {
  final r = color.r;
  final g = color.g;
  final b = color.b;
  final maxValue = math.max(r, math.max(g, b));
  final minValue = math.min(r, math.min(g, b));
  final delta = maxValue - minValue;
  final lightness = (maxValue + minValue) * .5;
  final saturation = delta == 0.0 ? 0.0 : _clamp01(delta / (1.0 - (2.0 * lightness - 1.0).abs()));
  return HSLColor.fromAHSL(
    _clamp01(color.a),
    _hueFromRgb(r, g, b, maxValue, delta),
    saturation,
    _clamp01(lightness),
  );
}

HSVColor _hsvFromColor(ui.Color color) {
  final r = color.r;
  final g = color.g;
  final b = color.b;
  final maxValue = math.max(r, math.max(g, b));
  final minValue = math.min(r, math.min(g, b));
  final delta = maxValue - minValue;
  return HSVColor.fromAHSV(
    _clamp01(color.a),
    _hueFromRgb(r, g, b, maxValue, delta),
    maxValue == 0.0 ? 0.0 : _clamp01(delta / maxValue),
    _clamp01(maxValue),
  );
}

double _hueFromRgb(
  double r,
  double g,
  double b,
  double maxValue,
  double delta,
) {
  if (delta == 0.0) return 0.0;
  late final double hue;
  if (maxValue == r) {
    hue = 60.0 * (((g - b) / delta) % 6.0);
  } else if (maxValue == g) {
    hue = 60.0 * (((b - r) / delta) + 2.0);
  } else {
    hue = 60.0 * (((r - g) / delta) + 4.0);
  }
  return hue < 0.0 ? hue + 360.0 : hue;
}

ui.Color _hslToColor(HSLColor color, ui.ColorSpace colorSpace) {
  final chroma = (1.0 - (2.0 * color.lightness - 1.0).abs()) * color.saturation;
  final x = chroma * (1.0 - (((color.hue / 60.0) % 2.0) - 1.0).abs());
  final m = color.lightness - chroma * .5;
  final (r, g, b) = _rgbFromHue(color.hue, chroma, x);
  return ui.Color.from(
    alpha: _clamp01(color.alpha),
    red: _clamp01(r + m),
    green: _clamp01(g + m),
    blue: _clamp01(b + m),
    colorSpace: colorSpace,
  );
}

ui.Color _hsvToColor(HSVColor color, ui.ColorSpace colorSpace) {
  final chroma = color.saturation * color.value;
  final x = chroma * (1.0 - (((color.hue / 60.0) % 2.0) - 1.0).abs());
  final m = color.value - chroma;
  final (r, g, b) = _rgbFromHue(color.hue, chroma, x);
  return ui.Color.from(
    alpha: _clamp01(color.alpha),
    red: _clamp01(r + m),
    green: _clamp01(g + m),
    blue: _clamp01(b + m),
    colorSpace: colorSpace,
  );
}

(double, double, double) _rgbFromHue(double hue, double chroma, double x) {
  if (hue < 60.0) return (chroma, x, 0.0);
  if (hue < 120.0) return (x, chroma, 0.0);
  if (hue < 180.0) return (0.0, chroma, x);
  if (hue < 240.0) return (0.0, x, chroma);
  if (hue < 300.0) return (x, 0.0, chroma);
  return (chroma, 0.0, x);
}

double _lerp(double a, double b, double t) => a + (b - a) * t;
double _clamp01(double value) => value.clamp(0.0, 1.0).toDouble();
double _lerpHue(double from, double to, double t, bool shortest) {
  var delta = to - from;
  if (shortest) delta = (delta + 180.0) % 360.0 - 180.0;
  var hue = (from + delta * t) % 360.0;
  if (hue < 0.0) hue += 360.0;
  return hue;
}

/// Compatibility implementation for package-internal legacy adapters. The
/// public barrel intentionally does not export this extension.
extension GraphXColorRuntimeCompat on GraphXMotion {
  MotionHandle toColor(
    ui.Color Function() read,
    void Function(ui.Color value) write,
    ui.Color target, {
    ui.Color? from,
    double duration = .3,
    EaseFunction ease = Ease.quadOut,
    double delay = 0.0,
    int repeat = 0,
    bool yoyo = false,
    Overwrite overwrite = Overwrite.auto,
    Object? owner,
    Object? hook,
    MotionPropertyKey? property,
    MotionColorSpace mode = MotionColorSpace.rgb,
    bool shortestHue = true,
    bool paint = false,
    void Function()? invalidate,
    void Function()? onStart,
    void Function()? onUpdate,
    void Function(int iteration)? onRepeat,
    void Function()? onComplete,
    void Function(MotionCancelReason reason)? onCancel,
  }) {
    final start = from ?? read();
    return engine.toDouble(
      () => 0.0,
      (t) {
        write(MotionColors.lerp(start, target, t, space: mode, shortestHue: shortestHue));
        invalidate?.call();
        if (paint) stage.requestPaint();
      },
      1.0,
      duration: duration,
      ease: ease,
      delay: delay,
      repeat: repeat,
      yoyo: yoyo,
      overwrite: overwrite,
      owner: owner,
      hook: hook,
      property: property,
      onStart: onStart,
      onUpdate: onUpdate,
      onRepeat: onRepeat,
      onComplete: onComplete,
      onCancel: onCancel,
    );
  }

  MotionHandle springColor(
    ui.Color Function() read,
    void Function(ui.Color value) write,
    ui.Color target, {
    Spring spring = Spring.snappy,
    double delay = 0.0,
    Overwrite overwrite = Overwrite.auto,
    Object? owner,
    Object? hook,
    MotionPropertyKey? property,
    MotionColorSpace mode = MotionColorSpace.rgb,
    bool shortestHue = true,
    void Function()? onSettled,
    void Function()? onComplete,
    void Function(MotionCancelReason reason)? onCancel,
  }) {
    final start = read();
    return engine.springDouble(
      () => 0.0,
      (t) => write(MotionColors.lerp(start, target, t, space: mode, shortestHue: shortestHue)),
      1.0,
      spring: spring,
      delay: delay,
      overwrite: overwrite,
      owner: owner,
      hook: hook,
      property: property,
      inheritVelocity: false,
      onSettled: onSettled,
      onComplete: onComplete,
      onCancel: onCancel,
    );
  }

  MotionHandle dampColor(
    ui.Color Function() read,
    void Function(ui.Color value) write,
    ui.Color target, {
    Damp damp = const Damp(),
    double delay = 0.0,
    Overwrite overwrite = Overwrite.auto,
    Object? owner,
    Object? hook,
    MotionPropertyKey? property,
    MotionColorSpace mode = MotionColorSpace.rgb,
    bool shortestHue = true,
    void Function()? onSettled,
    void Function()? onComplete,
    void Function(MotionCancelReason reason)? onCancel,
  }) {
    final start = read();
    return engine.dampDouble(
      () => 0.0,
      (t) => write(MotionColors.lerp(start, target, t, space: mode, shortestHue: shortestHue)),
      1.0,
      damp: damp,
      delay: delay,
      overwrite: overwrite,
      owner: owner,
      hook: hook,
      property: property,
      onSettled: onSettled,
      onComplete: onComplete,
      onCancel: onCancel,
    );
  }
}

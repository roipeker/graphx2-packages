import 'package:graphx_motion/motion.dart';

import 'filter_motion.dart';
import 'node_motion.dart';

/// Passive node motion definitions for Timeline composition.
///
/// `node.motion.to(...)` starts immediately; `node.motion.clip(...)` describes
/// the equivalent target values without starting a runtime.
extension GNodeMotionClipExtension on GNodeMotion {
  MotionClip clip({
    double? x,
    double? y,
    double? scale,
    double? scaleX,
    double? scaleY,
    double? rotation,
    double? skewX,
    double? skewY,
    double? pivotX,
    double? pivotY,
    double? alpha,
    MotionSpec? motion,
    double? duration,
    EaseFunction? ease,
    double? delay,
    int? repeat,
    double? repeatDelay,
    bool? yoyo,
    Overwrite? overwrite,
    bool shortest = false,
    double period = 6.283185307179586,
  }) {
    if (scale != null && (scaleX != null || scaleY != null)) {
      throw ArgumentError('Use scale or scaleX/scaleY, not both.');
    }
    final properties = <DoubleMotionProperty>[];
    void add(
      MotionPropertyKey key,
      double Function() read,
      void Function(double) write,
      double target, {
      bool circular = false,
    }) {
      properties.add(
        DoubleMotionProperty(
          property: key,
          read: read,
          write: write,
          to: target,
          shortest: circular && shortest,
          period: period,
        ),
      );
    }

    if (x != null) add(GNodeMotionProperties.x, () => node.x, (v) => node.x = v, x);
    if (y != null) add(GNodeMotionProperties.y, () => node.y, (v) => node.y = v, y);
    if (scale != null) {
      add(GNodeMotionProperties.scaleX, () => node.scaleX, (v) => node.scaleX = v, scale);
      add(GNodeMotionProperties.scaleY, () => node.scaleY, (v) => node.scaleY = v, scale);
    } else {
      if (scaleX != null) {
        add(GNodeMotionProperties.scaleX, () => node.scaleX, (v) => node.scaleX = v, scaleX);
      }
      if (scaleY != null) {
        add(GNodeMotionProperties.scaleY, () => node.scaleY, (v) => node.scaleY = v, scaleY);
      }
    }
    if (rotation != null) {
      add(
        GNodeMotionProperties.rotation,
        () => node.rotation,
        (v) => node.rotation = v,
        rotation,
        circular: true,
      );
    }
    if (skewX != null)
      add(GNodeMotionProperties.skewX, () => node.skewX, (v) => node.skewX = v, skewX);
    if (skewY != null)
      add(GNodeMotionProperties.skewY, () => node.skewY, (v) => node.skewY = v, skewY);
    if (pivotX != null)
      add(GNodeMotionProperties.pivotX, () => node.pivotX, (v) => node.pivotX = v, pivotX);
    if (pivotY != null)
      add(GNodeMotionProperties.pivotY, () => node.pivotY, (v) => node.pivotY = v, pivotY);
    if (alpha != null)
      add(GNodeMotionProperties.alpha, () => node.alpha, (v) => node.alpha = v, alpha);

    return _propertiesClip(
      node,
      properties,
      motion: motion,
      duration: duration,
      ease: ease,
      delay: delay,
      repeat: repeat,
      repeatDelay: repeatDelay,
      yoyo: yoyo,
      overwrite: overwrite,
    );
  }
}

/// Passive counterpart to [GBlurFilterMotion.to].
extension GBlurFilterMotionClipExtension on GBlurFilterMotion {
  MotionClip clip({
    double? blurX,
    double? blurY,
    MotionSpec? motion,
    double? duration,
    EaseFunction? ease,
    double? delay,
    int? repeat,
    double? repeatDelay,
    bool? yoyo,
    Overwrite? overwrite,
  }) => _propertiesClip(
    filter,
    _blurProperties(
      readX: () => filter.blurX,
      writeX: (v) => filter.blurX = v,
      readY: () => filter.blurY,
      writeY: (v) => filter.blurY = v,
      blurX: blurX,
      blurY: blurY,
    ),
    motion: motion,
    duration: duration,
    ease: ease,
    delay: delay,
    repeat: repeat,
    repeatDelay: repeatDelay,
    yoyo: yoyo,
    overwrite: overwrite,
  );
}

/// Passive counterpart to [GDropShadowFilterMotion.to].
extension GDropShadowFilterMotionClipExtension on GDropShadowFilterMotion {
  MotionClip clip({
    double? offsetX,
    double? offsetY,
    double? blurX,
    double? blurY,
    MotionSpec? motion,
    double? duration,
    EaseFunction? ease,
    double? delay,
    int? repeat,
    double? repeatDelay,
    bool? yoyo,
    Overwrite? overwrite,
  }) => _propertiesClip(
    filter,
    [
      if (offsetX != null)
        _field(
          GFilterMotionProperties.offsetX,
          () => filter.offsetX,
          (v) => filter.offsetX = v,
          offsetX,
          'offsetX',
        ),
      if (offsetY != null)
        _field(
          GFilterMotionProperties.offsetY,
          () => filter.offsetY,
          (v) => filter.offsetY = v,
          offsetY,
          'offsetY',
        ),
      ..._blurProperties(
        readX: () => filter.blurX,
        writeX: (v) => filter.blurX = v,
        readY: () => filter.blurY,
        writeY: (v) => filter.blurY = v,
        blurX: blurX,
        blurY: blurY,
      ),
    ],
    motion: motion,
    duration: duration,
    ease: ease,
    delay: delay,
    repeat: repeat,
    repeatDelay: repeatDelay,
    yoyo: yoyo,
    overwrite: overwrite,
  );
}

/// Passive counterpart to [GGlowFilterMotion.to].
extension GGlowFilterMotionClipExtension on GGlowFilterMotion {
  MotionClip clip({
    double? blurX,
    double? blurY,
    double? spread,
    MotionSpec? motion,
    double? duration,
    EaseFunction? ease,
    double? delay,
    int? repeat,
    double? repeatDelay,
    bool? yoyo,
    Overwrite? overwrite,
  }) => _propertiesClip(
    filter,
    [
      ..._blurProperties(
        readX: () => filter.blurX,
        writeX: (v) => filter.blurX = v,
        readY: () => filter.blurY,
        writeY: (v) => filter.blurY = v,
        blurX: blurX,
        blurY: blurY,
      ),
      if (spread != null)
        _field(
          GFilterMotionProperties.spread,
          () => filter.spread,
          (v) => filter.spread = v,
          spread,
          'spread',
          nonNegative: true,
        ),
    ],
    motion: motion,
    duration: duration,
    ease: ease,
    delay: delay,
    repeat: repeat,
    repeatDelay: repeatDelay,
    yoyo: yoyo,
    overwrite: overwrite,
  );
}

/// Passive counterpart to [GBevelFilterMotion.to].
extension GBevelFilterMotionClipExtension on GBevelFilterMotion {
  MotionClip clip({
    double? offsetX,
    double? offsetY,
    double? blurX,
    double? blurY,
    MotionSpec? motion,
    double? duration,
    EaseFunction? ease,
    double? delay,
    int? repeat,
    double? repeatDelay,
    bool? yoyo,
    Overwrite? overwrite,
  }) => _propertiesClip(
    filter,
    [
      if (offsetX != null)
        _field(
          GFilterMotionProperties.offsetX,
          () => filter.offsetX,
          (v) => filter.offsetX = v,
          offsetX,
          'offsetX',
        ),
      if (offsetY != null)
        _field(
          GFilterMotionProperties.offsetY,
          () => filter.offsetY,
          (v) => filter.offsetY = v,
          offsetY,
          'offsetY',
        ),
      ..._blurProperties(
        readX: () => filter.blurX,
        writeX: (v) => filter.blurX = v,
        readY: () => filter.blurY,
        writeY: (v) => filter.blurY = v,
        blurX: blurX,
        blurY: blurY,
      ),
    ],
    motion: motion,
    duration: duration,
    ease: ease,
    delay: delay,
    repeat: repeat,
    repeatDelay: repeatDelay,
    yoyo: yoyo,
    overwrite: overwrite,
  );
}

/// Passive counterpart to [GOutlineFilterMotion.to].
extension GOutlineFilterMotionClipExtension on GOutlineFilterMotion {
  MotionClip clip({
    double? width,
    double? softness,
    MotionSpec? motion,
    double? duration,
    EaseFunction? ease,
    double? delay,
    int? repeat,
    double? repeatDelay,
    bool? yoyo,
    Overwrite? overwrite,
  }) => _propertiesClip(
    filter,
    [
      if (width != null)
        _field(
          GFilterMotionProperties.width,
          () => filter.width,
          (v) => filter.width = v,
          width,
          'width',
          nonNegative: true,
        ),
      if (softness != null)
        _field(
          GFilterMotionProperties.softness,
          () => filter.softness,
          (v) => filter.softness = v,
          softness,
          'softness',
          nonNegative: true,
        ),
    ],
    motion: motion,
    duration: duration,
    ease: ease,
    delay: delay,
    repeat: repeat,
    repeatDelay: repeatDelay,
    yoyo: yoyo,
    overwrite: overwrite,
  );
}

/// Passive counterpart to [GShaderFilterMotion.to].
extension GShaderFilterMotionClipExtension on GShaderFilterMotion {
  MotionClip clip(
    double padding, {
    MotionSpec? motion,
    double? duration,
    EaseFunction? ease,
    double? delay,
    int? repeat,
    double? repeatDelay,
    bool? yoyo,
    Overwrite? overwrite,
  }) => _propertiesClip(
    filter,
    [
      _field(
        GFilterMotionProperties.padding,
        () => filter.padding,
        (v) => filter.padding = v,
        padding,
        'padding',
        nonNegative: true,
      ),
    ],
    motion: motion,
    duration: duration,
    ease: ease,
    delay: delay,
    repeat: repeat,
    repeatDelay: repeatDelay,
    yoyo: yoyo,
    overwrite: overwrite,
  );
}

/// Universal passive custom-value definition.
///
/// Any object can participate in Timeline composition by exposing its mutable
/// state through a [MotionProperty]. No Timeline or GraphX adapter changes are
/// required for custom domain objects.
extension MotionPropertyClipExtension<T> on MotionProperty<T> {
  MotionClip clip(
    T target, {
    MotionSpec? motion,
    MotionInterpolator<T>? interpolate,
    double? duration,
    EaseFunction? ease,
    double? delay,
    int? repeat,
    double? repeatDelay,
    bool? yoyo,
    Overwrite? overwrite,
  }) => MotionClip.property<T>(
    this,
    target,
    motion: motion,
    interpolate: interpolate,
    duration: duration,
    ease: ease,
    delay: delay,
    repeat: repeat,
    repeatDelay: repeatDelay,
    yoyo: yoyo,
    overwrite: overwrite,
  );
}

MotionClip _propertiesClip(
  Object owner,
  Iterable<DoubleMotionProperty> properties, {
  required MotionSpec? motion,
  required double? duration,
  required EaseFunction? ease,
  required double? delay,
  required int? repeat,
  required double? repeatDelay,
  required bool? yoyo,
  required Overwrite? overwrite,
}) => MotionClip.properties(
  properties,
  owner: owner,
  motion: motion,
  duration: duration,
  ease: ease,
  delay: delay,
  repeat: repeat,
  repeatDelay: repeatDelay,
  yoyo: yoyo,
  overwrite: overwrite,
);

List<DoubleMotionProperty> _blurProperties({
  required double Function() readX,
  required void Function(double) writeX,
  required double Function() readY,
  required void Function(double) writeY,
  required double? blurX,
  required double? blurY,
}) => [
  if (blurX != null)
    _field(
      GFilterMotionProperties.blurX,
      readX,
      writeX,
      blurX,
      'blurX',
      nonNegative: true,
    ),
  if (blurY != null)
    _field(
      GFilterMotionProperties.blurY,
      readY,
      writeY,
      blurY,
      'blurY',
      nonNegative: true,
    ),
];

DoubleMotionProperty _field(
  MotionPropertyKey property,
  double Function() read,
  void Function(double) write,
  double target,
  String name, {
  bool nonNegative = false,
}) {
  if (!target.isFinite || (nonNegative && target < 0.0)) {
    throw ArgumentError.value(
      target,
      name,
      nonNegative ? 'Must be finite and >= 0.' : 'Must be finite.',
    );
  }
  final safeWrite = nonNegative ? (double value) => write(value < 0.0 ? 0.0 : value) : write;
  return DoubleMotionProperty(
    property: property,
    read: read,
    write: safeWrite,
    to: target,
  );
}

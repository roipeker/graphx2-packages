import 'package:graphx/graphx_extension.dart';
import 'package:graphx_motion/motion.dart';

import 'stage_motion.dart';

abstract final class GFilterMotionProperties {
  static const blurX = MotionPropertyKey('GFilter.blurX');
  static const blurY = MotionPropertyKey('GFilter.blurY');
  static const offsetX = MotionPropertyKey('GFilter.offsetX');
  static const offsetY = MotionPropertyKey('GFilter.offsetY');
  static const spread = MotionPropertyKey('GFilter.spread');
  static const width = MotionPropertyKey('GFilter.width');
  static const softness = MotionPropertyKey('GFilter.softness');
  static const padding = MotionPropertyKey('GFilter.padding');
}

final Expando<GBlurFilterMotion> _blurMotion = Expando('graphx.motion.blur');
final Expando<GDropShadowFilterMotion> _shadowMotion = Expando('graphx.motion.shadow');
final Expando<GGlowFilterMotion> _glowMotion = Expando('graphx.motion.glow');
final Expando<GBevelFilterMotion> _bevelMotion = Expando('graphx.motion.bevel');
final Expando<GOutlineFilterMotion> _outlineMotion = Expando('graphx.motion.outline');
final Expando<GShaderFilterMotion> _shaderFilterMotion = Expando('graphx.motion.shaderFilter');

extension GBlurFilterMotionExtension on GBlurFilter {
  GBlurFilterMotion get motion => _blurMotion[this] ??= GBlurFilterMotion._(this);
}

extension GDropShadowFilterMotionExtension on GDropShadowFilter {
  GDropShadowFilterMotion get motion => _shadowMotion[this] ??= GDropShadowFilterMotion._(this);
}

extension GGlowFilterMotionExtension on GGlowFilter {
  GGlowFilterMotion get motion => _glowMotion[this] ??= GGlowFilterMotion._(this);
}

extension GBevelFilterMotionExtension on GBevelFilter {
  GBevelFilterMotion get motion => _bevelMotion[this] ??= GBevelFilterMotion._(this);
}

extension GOutlineFilterMotionExtension on GOutlineFilter {
  GOutlineFilterMotion get motion => _outlineMotion[this] ??= GOutlineFilterMotion._(this);
}

extension GShaderFilterMotionExtension on GShaderFilter {
  GShaderFilterMotion get motion => _shaderFilterMotion[this] ??= GShaderFilterMotion._(this);
}

final class GBlurFilterMotion {
  GBlurFilterMotion._(this.filter);
  final GBlurFilter filter;

  List<DoubleMotionProperty> _properties(double? x, double? y) => _blurPair(
    readX: () => filter.blurX,
    writeX: (v) => filter.blurX = v,
    readY: () => filter.blurY,
    writeY: (v) => filter.blurY = v,
    blurX: x,
    blurY: y,
  );

  MotionHandle to({
    double? blurX,
    double? blurY,
    MotionSpec? motion,
    double? duration,
    EaseFunction? ease,
    Object? hook,
    Overwrite? overwrite,
  }) => _filterTween(
    filter,
    _properties(blurX, blurY),
    motion: motion,
    duration: duration,
    ease: ease,
    hook: hook,
    overwrite: overwrite,
  );

  MotionHandle spring({
    double? blurX,
    double? blurY,
    Spring spring = Spring.snappy,
    Object? hook,
    Overwrite overwrite = Overwrite.auto,
  }) => _filterSpring(
    filter,
    _properties(blurX, blurY),
    spring: spring,
    hook: hook,
    overwrite: overwrite,
  );

  MotionHandle damp({
    double? blurX,
    double? blurY,
    Damp damp = const Damp(),
    Object? hook,
    Overwrite overwrite = Overwrite.auto,
  }) => _filterDamp(
    filter,
    _properties(blurX, blurY),
    damp: damp,
    hook: hook,
    overwrite: overwrite,
  );
}

final class GDropShadowFilterMotion {
  GDropShadowFilterMotion._(this.filter);
  final GDropShadowFilter filter;

  List<DoubleMotionProperty> _properties({
    double? offsetX,
    double? offsetY,
    double? blurX,
    double? blurY,
  }) => [
    if (offsetX != null)
      _field(
        GFilterMotionProperties.offsetX,
        () => filter.offsetX,
        (v) => filter.offsetX = v,
        offsetX,
        name: 'offsetX',
      ),
    if (offsetY != null)
      _field(
        GFilterMotionProperties.offsetY,
        () => filter.offsetY,
        (v) => filter.offsetY = v,
        offsetY,
        name: 'offsetY',
      ),
    ..._blurPair(
      readX: () => filter.blurX,
      writeX: (v) => filter.blurX = v,
      readY: () => filter.blurY,
      writeY: (v) => filter.blurY = v,
      blurX: blurX,
      blurY: blurY,
    ),
  ];

  MotionHandle to({
    double? offsetX,
    double? offsetY,
    double? blurX,
    double? blurY,
    MotionSpec? motion,
    double? duration,
    EaseFunction? ease,
    Object? hook,
    Overwrite? overwrite,
  }) => _filterTween(
    filter,
    _properties(
      offsetX: offsetX,
      offsetY: offsetY,
      blurX: blurX,
      blurY: blurY,
    ),
    motion: motion,
    duration: duration,
    ease: ease,
    hook: hook,
    overwrite: overwrite,
  );

  MotionHandle spring({
    double? offsetX,
    double? offsetY,
    double? blurX,
    double? blurY,
    Spring spring = Spring.snappy,
    Object? hook,
    Overwrite overwrite = Overwrite.auto,
  }) => _filterSpring(
    filter,
    _properties(
      offsetX: offsetX,
      offsetY: offsetY,
      blurX: blurX,
      blurY: blurY,
    ),
    spring: spring,
    hook: hook,
    overwrite: overwrite,
  );

  MotionHandle damp({
    double? offsetX,
    double? offsetY,
    double? blurX,
    double? blurY,
    Damp damp = const Damp(),
    Object? hook,
    Overwrite overwrite = Overwrite.auto,
  }) => _filterDamp(
    filter,
    _properties(
      offsetX: offsetX,
      offsetY: offsetY,
      blurX: blurX,
      blurY: blurY,
    ),
    damp: damp,
    hook: hook,
    overwrite: overwrite,
  );
}

final class GGlowFilterMotion {
  GGlowFilterMotion._(this.filter);
  final GGlowFilter filter;

  List<DoubleMotionProperty> _properties({
    double? blurX,
    double? blurY,
    double? spread,
  }) => [
    ..._blurPair(
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
        name: 'spread',
        nonNegative: true,
      ),
  ];

  MotionHandle to({
    double? blurX,
    double? blurY,
    double? spread,
    MotionSpec? motion,
    double? duration,
    EaseFunction? ease,
    Object? hook,
    Overwrite? overwrite,
  }) => _filterTween(
    filter,
    _properties(blurX: blurX, blurY: blurY, spread: spread),
    motion: motion,
    duration: duration,
    ease: ease,
    hook: hook,
    overwrite: overwrite,
  );

  MotionHandle spring({
    double? blurX,
    double? blurY,
    double? spread,
    Spring spring = Spring.snappy,
    Object? hook,
    Overwrite overwrite = Overwrite.auto,
  }) => _filterSpring(
    filter,
    _properties(blurX: blurX, blurY: blurY, spread: spread),
    spring: spring,
    hook: hook,
    overwrite: overwrite,
  );

  MotionHandle damp({
    double? blurX,
    double? blurY,
    double? spread,
    Damp damp = const Damp(),
    Object? hook,
    Overwrite overwrite = Overwrite.auto,
  }) => _filterDamp(
    filter,
    _properties(blurX: blurX, blurY: blurY, spread: spread),
    damp: damp,
    hook: hook,
    overwrite: overwrite,
  );
}

final class GBevelFilterMotion {
  GBevelFilterMotion._(this.filter);
  final GBevelFilter filter;

  List<DoubleMotionProperty> _properties({
    double? offsetX,
    double? offsetY,
    double? blurX,
    double? blurY,
  }) => [
    if (offsetX != null)
      _field(
        GFilterMotionProperties.offsetX,
        () => filter.offsetX,
        (v) => filter.offsetX = v,
        offsetX,
        name: 'offsetX',
      ),
    if (offsetY != null)
      _field(
        GFilterMotionProperties.offsetY,
        () => filter.offsetY,
        (v) => filter.offsetY = v,
        offsetY,
        name: 'offsetY',
      ),
    ..._blurPair(
      readX: () => filter.blurX,
      writeX: (v) => filter.blurX = v,
      readY: () => filter.blurY,
      writeY: (v) => filter.blurY = v,
      blurX: blurX,
      blurY: blurY,
    ),
  ];

  MotionHandle to({
    double? offsetX,
    double? offsetY,
    double? blurX,
    double? blurY,
    MotionSpec? motion,
    double? duration,
    EaseFunction? ease,
    Object? hook,
    Overwrite? overwrite,
  }) => _filterTween(
    filter,
    _properties(
      offsetX: offsetX,
      offsetY: offsetY,
      blurX: blurX,
      blurY: blurY,
    ),
    motion: motion,
    duration: duration,
    ease: ease,
    hook: hook,
    overwrite: overwrite,
  );

  MotionHandle spring({
    double? offsetX,
    double? offsetY,
    double? blurX,
    double? blurY,
    Spring spring = Spring.snappy,
    Object? hook,
    Overwrite overwrite = Overwrite.auto,
  }) => _filterSpring(
    filter,
    _properties(
      offsetX: offsetX,
      offsetY: offsetY,
      blurX: blurX,
      blurY: blurY,
    ),
    spring: spring,
    hook: hook,
    overwrite: overwrite,
  );

  MotionHandle damp({
    double? offsetX,
    double? offsetY,
    double? blurX,
    double? blurY,
    Damp damp = const Damp(),
    Object? hook,
    Overwrite overwrite = Overwrite.auto,
  }) => _filterDamp(
    filter,
    _properties(
      offsetX: offsetX,
      offsetY: offsetY,
      blurX: blurX,
      blurY: blurY,
    ),
    damp: damp,
    hook: hook,
    overwrite: overwrite,
  );
}

final class GOutlineFilterMotion {
  GOutlineFilterMotion._(this.filter);
  final GOutlineFilter filter;

  List<DoubleMotionProperty> _properties(double? width, double? softness) => [
    if (width != null)
      _field(
        GFilterMotionProperties.width,
        () => filter.width,
        (v) => filter.width = v,
        width,
        name: 'width',
        nonNegative: true,
      ),
    if (softness != null)
      _field(
        GFilterMotionProperties.softness,
        () => filter.softness,
        (v) => filter.softness = v,
        softness,
        name: 'softness',
        nonNegative: true,
      ),
  ];

  MotionHandle to({
    double? width,
    double? softness,
    MotionSpec? motion,
    double? duration,
    EaseFunction? ease,
    Object? hook,
    Overwrite? overwrite,
  }) => _filterTween(
    filter,
    _properties(width, softness),
    motion: motion,
    duration: duration,
    ease: ease,
    hook: hook,
    overwrite: overwrite,
  );

  MotionHandle spring({
    double? width,
    double? softness,
    Spring spring = Spring.snappy,
    Object? hook,
    Overwrite overwrite = Overwrite.auto,
  }) => _filterSpring(
    filter,
    _properties(width, softness),
    spring: spring,
    hook: hook,
    overwrite: overwrite,
  );

  MotionHandle damp({
    double? width,
    double? softness,
    Damp damp = const Damp(),
    Object? hook,
    Overwrite overwrite = Overwrite.auto,
  }) => _filterDamp(
    filter,
    _properties(width, softness),
    damp: damp,
    hook: hook,
    overwrite: overwrite,
  );
}

final class GShaderFilterMotion {
  GShaderFilterMotion._(this.filter);
  final GShaderFilter filter;

  List<DoubleMotionProperty> _properties(double padding) => [
    _field(
      GFilterMotionProperties.padding,
      () => filter.padding,
      (v) => filter.padding = v,
      padding,
      name: 'padding',
      nonNegative: true,
    ),
  ];

  MotionHandle to(
    double padding, {
    MotionSpec? motion,
    double? duration,
    EaseFunction? ease,
    Object? hook,
    Overwrite? overwrite,
  }) => _filterTween(
    filter,
    _properties(padding),
    motion: motion,
    duration: duration,
    ease: ease,
    hook: hook,
    overwrite: overwrite,
  );

  MotionHandle spring(
    double padding, {
    Spring spring = Spring.snappy,
    Object? hook,
    Overwrite overwrite = Overwrite.auto,
  }) => _filterSpring(
    filter,
    _properties(padding),
    spring: spring,
    hook: hook,
    overwrite: overwrite,
  );

  MotionHandle damp(
    double padding, {
    Damp damp = const Damp(),
    Object? hook,
    Overwrite overwrite = Overwrite.auto,
  }) => _filterDamp(
    filter,
    _properties(padding),
    damp: damp,
    hook: hook,
    overwrite: overwrite,
  );
}

List<DoubleMotionProperty> _blurPair({
  required double Function() readX,
  required void Function(double value) writeX,
  required double Function() readY,
  required void Function(double value) writeY,
  required double? blurX,
  required double? blurY,
}) => [
  if (blurX != null)
    _field(
      GFilterMotionProperties.blurX,
      readX,
      writeX,
      blurX,
      name: 'blurX',
      nonNegative: true,
    ),
  if (blurY != null)
    _field(
      GFilterMotionProperties.blurY,
      readY,
      writeY,
      blurY,
      name: 'blurY',
      nonNegative: true,
    ),
];

DoubleMotionProperty _field(
  MotionPropertyKey property,
  double Function() read,
  void Function(double value) write,
  double target, {
  required String name,
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

GraphXMotion _filterStageMotion(GFilter filter) {
  final owner = filter.owner;
  if (owner == null || !owner.isAttached) {
    throw StateError('Attach the filter to a live node before starting motion.');
  }
  return owner.stage.motion;
}

MotionHandle _filterTween(
  GFilter filter,
  List<DoubleMotionProperty> properties, {
  required MotionSpec? motion,
  required double? duration,
  required EaseFunction? ease,
  required Object? hook,
  required Overwrite? overwrite,
}) => _filterStageMotion(filter).engine.toConfiguredProperties(
  properties,
  owner: filter,
  hook: hook,
  motion: motion,
  duration: duration,
  ease: ease,
  overwrite: overwrite,
);

MotionHandle _filterSpring(
  GFilter filter,
  List<DoubleMotionProperty> properties, {
  required Spring spring,
  required Object? hook,
  required Overwrite overwrite,
}) => _filterStageMotion(filter).engine.springProperties(
  properties,
  owner: filter,
  hook: hook,
  spring: spring,
  overwrite: overwrite,
);

MotionHandle _filterDamp(
  GFilter filter,
  List<DoubleMotionProperty> properties, {
  required Damp damp,
  required Object? hook,
  required Overwrite overwrite,
}) => _filterStageMotion(filter).engine.dampProperties(
  properties,
  owner: filter,
  hook: hook,
  damp: damp,
  overwrite: overwrite,
);

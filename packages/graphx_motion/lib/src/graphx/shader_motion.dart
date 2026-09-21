import 'package:graphx/graphx.dart';
import 'package:graphx_motion/motion.dart';

import 'stage_motion.dart';

final Expando<GShaderNodeMotion> _shaderMotionByNode = Expando('graphx.motion.shaderNode');

extension GShaderNodeMotionExtension on GShaderNode {
  /// Node-bound so Motion can resolve Stage time and lifecycle. When one shader
  /// instance is intentionally shared, keep one node as animation authority.
  GShaderNodeMotion get shaderMotion => _shaderMotionByNode[this] ??= GShaderNodeMotion._(this);
}

final class GShaderNodeMotion {
  GShaderNodeMotion._(this.node);
  final GShaderNode node;

  MotionHandle toFloat(
    String name,
    double to, {
    MotionSpec? motion,
    double? duration,
    EaseFunction? ease,
    Object? hook,
    Overwrite? overwrite,
  }) {
    final binding = node.shader.float(name);
    return _motion.engine.toConfiguredDouble(
      () => binding.value,
      (value) => binding.value = value,
      to,
      owner: node,
      hook: hook,
      property: _key(name, 'f'),
      motion: motion,
      duration: duration,
      ease: ease,
      overwrite: overwrite,
    );
  }

  MotionHandle springFloat(
    String name,
    double to, {
    Spring spring = Spring.snappy,
    Object? hook,
    Overwrite overwrite = Overwrite.auto,
    bool inheritVelocity = true,
  }) {
    final binding = node.shader.float(name);
    return _motion.engine.springDouble(
      () => binding.value,
      (value) => binding.value = value,
      to,
      owner: node,
      hook: hook,
      property: _key(name, 'f'),
      spring: spring,
      overwrite: overwrite,
      inheritVelocity: inheritVelocity,
    );
  }

  MotionHandle dampFloat(
    String name,
    double to, {
    Damp damp = const Damp(),
    Object? hook,
    Overwrite overwrite = Overwrite.auto,
  }) {
    final binding = node.shader.float(name);
    return _motion.engine.dampDouble(
      () => binding.value,
      (value) => binding.value = value,
      to,
      owner: node,
      hook: hook,
      property: _key(name, 'f'),
      damp: damp,
      overwrite: overwrite,
    );
  }

  MotionHandle inertiaFloat(
    String name, {
    required double velocity,
    Inertia inertia = const Inertia(),
    Object? hook,
    Overwrite overwrite = Overwrite.auto,
  }) {
    final binding = node.shader.float(name);
    return _motion.engine.inertiaDouble(
      () => binding.value,
      (value) => binding.value = value,
      velocity: velocity,
      inertia: inertia,
      owner: node,
      hook: hook,
      property: _key(name, 'f'),
      overwrite: overwrite,
    );
  }

  MotionHandle toVec2(
    String name, {
    double? x,
    double? y,
    MotionSpec? motion,
    double? duration,
    EaseFunction? ease,
    Object? hook,
    Overwrite? overwrite,
  }) => _to(
    _vec2(name, x: x, y: y),
    motion: motion,
    duration: duration,
    ease: ease,
    hook: hook,
    overwrite: overwrite,
  );

  MotionHandle springVec2(
    String name, {
    double? x,
    double? y,
    Spring spring = Spring.snappy,
    Object? hook,
    Overwrite overwrite = Overwrite.auto,
  }) => _spring(
    _vec2(name, x: x, y: y),
    spring: spring,
    hook: hook,
    overwrite: overwrite,
  );

  MotionHandle dampVec2(
    String name, {
    double? x,
    double? y,
    Damp damp = const Damp(),
    Object? hook,
    Overwrite overwrite = Overwrite.auto,
  }) => _damp(
    _vec2(name, x: x, y: y),
    damp: damp,
    hook: hook,
    overwrite: overwrite,
  );

  MotionHandle toVec3(
    String name, {
    double? x,
    double? y,
    double? z,
    MotionSpec? motion,
    double? duration,
    EaseFunction? ease,
    Object? hook,
    Overwrite? overwrite,
  }) => _to(
    _vec3(name, x: x, y: y, z: z),
    motion: motion,
    duration: duration,
    ease: ease,
    hook: hook,
    overwrite: overwrite,
  );

  MotionHandle springVec3(
    String name, {
    double? x,
    double? y,
    double? z,
    Spring spring = Spring.snappy,
    Object? hook,
    Overwrite overwrite = Overwrite.auto,
  }) => _spring(
    _vec3(name, x: x, y: y, z: z),
    spring: spring,
    hook: hook,
    overwrite: overwrite,
  );

  MotionHandle dampVec3(
    String name, {
    double? x,
    double? y,
    double? z,
    Damp damp = const Damp(),
    Object? hook,
    Overwrite overwrite = Overwrite.auto,
  }) => _damp(
    _vec3(name, x: x, y: y, z: z),
    damp: damp,
    hook: hook,
    overwrite: overwrite,
  );

  MotionHandle toVec4(
    String name, {
    double? x,
    double? y,
    double? z,
    double? w,
    MotionSpec? motion,
    double? duration,
    EaseFunction? ease,
    Object? hook,
    Overwrite? overwrite,
  }) => _to(
    _vec4(name, x: x, y: y, z: z, w: w),
    motion: motion,
    duration: duration,
    ease: ease,
    hook: hook,
    overwrite: overwrite,
  );

  MotionHandle springVec4(
    String name, {
    double? x,
    double? y,
    double? z,
    double? w,
    Spring spring = Spring.snappy,
    Object? hook,
    Overwrite overwrite = Overwrite.auto,
  }) => _spring(
    _vec4(name, x: x, y: y, z: z, w: w),
    spring: spring,
    hook: hook,
    overwrite: overwrite,
  );

  MotionHandle dampVec4(
    String name, {
    double? x,
    double? y,
    double? z,
    double? w,
    Damp damp = const Damp(),
    Object? hook,
    Overwrite overwrite = Overwrite.auto,
  }) => _damp(
    _vec4(name, x: x, y: y, z: z, w: w),
    damp: damp,
    hook: hook,
    overwrite: overwrite,
  );

  MotionHandle toSize({
    double? width,
    double? height,
    MotionSpec? motion,
    double? duration,
    EaseFunction? ease,
    Object? hook,
    Overwrite? overwrite,
  }) => _to(
    _size(width: width, height: height),
    motion: motion,
    duration: duration,
    ease: ease,
    hook: hook,
    overwrite: overwrite,
  );

  MotionHandle springSize({
    double? width,
    double? height,
    Spring spring = Spring.snappy,
    Object? hook,
    Overwrite overwrite = Overwrite.auto,
  }) => _spring(
    _size(width: width, height: height),
    spring: spring,
    hook: hook,
    overwrite: overwrite,
  );

  MotionHandle dampSize({
    double? width,
    double? height,
    Damp damp = const Damp(),
    Object? hook,
    Overwrite overwrite = Overwrite.auto,
  }) => _damp(
    _size(width: width, height: height),
    damp: damp,
    hook: hook,
    overwrite: overwrite,
  );

  MotionHandle _to(
    List<DoubleMotionProperty> properties, {
    required MotionSpec? motion,
    required double? duration,
    required EaseFunction? ease,
    required Object? hook,
    required Overwrite? overwrite,
  }) => _motion.engine.toConfiguredProperties(
    properties,
    owner: node,
    hook: hook,
    motion: motion,
    duration: duration,
    ease: ease,
    overwrite: overwrite,
  );

  MotionHandle _spring(
    List<DoubleMotionProperty> properties, {
    required Spring spring,
    required Object? hook,
    required Overwrite overwrite,
  }) => _motion.engine.springProperties(
    properties,
    owner: node,
    hook: hook,
    spring: spring,
    overwrite: overwrite,
  );

  MotionHandle _damp(
    List<DoubleMotionProperty> properties, {
    required Damp damp,
    required Object? hook,
    required Overwrite overwrite,
  }) => _motion.engine.dampProperties(
    properties,
    owner: node,
    hook: hook,
    damp: damp,
    overwrite: overwrite,
  );

  List<DoubleMotionProperty> _vec2(
    String name, {
    double? x,
    double? y,
  }) {
    final value = node.shader.vec2(name);
    return [
      if (x != null)
        DoubleMotionProperty(
          property: _key(name, 'x'),
          read: () => value.x,
          write: (next) => value.set(next, value.y),
          to: x,
        ),
      if (y != null)
        DoubleMotionProperty(
          property: _key(name, 'y'),
          read: () => value.y,
          write: (next) => value.set(value.x, next),
          to: y,
        ),
    ];
  }

  List<DoubleMotionProperty> _vec3(
    String name, {
    double? x,
    double? y,
    double? z,
  }) {
    final value = node.shader.vec3(name);
    return [
      if (x != null)
        DoubleMotionProperty(
          property: _key(name, 'x'),
          read: () => value.x,
          write: (next) => value.set(next, value.y, value.z),
          to: x,
        ),
      if (y != null)
        DoubleMotionProperty(
          property: _key(name, 'y'),
          read: () => value.y,
          write: (next) => value.set(value.x, next, value.z),
          to: y,
        ),
      if (z != null)
        DoubleMotionProperty(
          property: _key(name, 'z'),
          read: () => value.z,
          write: (next) => value.set(value.x, value.y, next),
          to: z,
        ),
    ];
  }

  List<DoubleMotionProperty> _vec4(
    String name, {
    double? x,
    double? y,
    double? z,
    double? w,
  }) {
    final value = node.shader.vec4(name);
    return [
      if (x != null)
        DoubleMotionProperty(
          property: _key(name, 'x'),
          read: () => value.x,
          write: (next) => value.set(next, value.y, value.z, value.w),
          to: x,
        ),
      if (y != null)
        DoubleMotionProperty(
          property: _key(name, 'y'),
          read: () => value.y,
          write: (next) => value.set(value.x, next, value.z, value.w),
          to: y,
        ),
      if (z != null)
        DoubleMotionProperty(
          property: _key(name, 'z'),
          read: () => value.z,
          write: (next) => value.set(value.x, value.y, next, value.w),
          to: z,
        ),
      if (w != null)
        DoubleMotionProperty(
          property: _key(name, 'w'),
          read: () => value.w,
          write: (next) => value.set(value.x, value.y, value.z, next),
          to: w,
        ),
    ];
  }

  List<DoubleMotionProperty> _size({double? width, double? height}) => [
    if (width != null)
      DoubleMotionProperty(
        property: const MotionPropertyKey('GShaderNode.width'),
        read: () => node.width,
        write: (value) => node.width = value < 0.0 ? 0.0 : value,
        to: _sizeTarget(width, 'width'),
      ),
    if (height != null)
      DoubleMotionProperty(
        property: const MotionPropertyKey('GShaderNode.height'),
        read: () => node.height,
        write: (value) => node.height = value < 0.0 ? 0.0 : value,
        to: _sizeTarget(height, 'height'),
      ),
  ];

  GraphXMotion get _motion {
    if (!node.isAttached) {
      throw StateError('Attach the shader node before starting motion.');
    }
    return node.stage.motion;
  }
}

MotionPropertyKey _key(String name, String component) =>
    MotionPropertyKey('GShader.$name.$component');

double _sizeTarget(double value, String name) {
  if (!value.isFinite || value < 0.0) {
    throw ArgumentError.value(value, name, 'Must be finite and >= 0.');
  }
  return value;
}

import 'package:graphx/graphx.dart';
import 'package:graphx_motion/motion.dart';

import 'node_motion.dart';
import 'stage_motion.dart';

extension GraphXPhysicsMotion on GraphXMotion {
  MotionHandle spring(
    double from,
    double to, {
    required void Function(double value) onValue,
    Spring spring = Spring.snappy,
    double initialVelocity = 0.0,
    double delay = 0.0,
    Object? owner,
    Object? hook,
    bool paint = false,
    void Function()? invalidate,
    MotionSample? sample,
    MotionSnap? snap,
    MotionClamp? clamp,
    void Function()? onStart,
    void Function()? onUpdate,
    void Function()? onSettled,
    void Function()? onComplete,
    void Function(MotionCancelReason reason)? onCancel,
  }) => springDouble(
    () => from,
    onValue,
    to,
    from: from,
    spring: spring,
    initialVelocity: initialVelocity,
    delay: delay,
    owner: owner,
    hook: hook,
    paint: paint,
    invalidate: invalidate,
    sample: sample,
    snap: snap,
    clamp: clamp,
    onStart: onStart,
    onUpdate: onUpdate,
    onSettled: onSettled,
    onComplete: onComplete,
    onCancel: onCancel,
  );

  MotionHandle springDouble(
    double Function() read,
    void Function(double value) write,
    double to, {
    double? from,
    Spring spring = Spring.snappy,
    double initialVelocity = 0.0,
    double delay = 0.0,
    Overwrite overwrite = Overwrite.auto,
    Object? owner,
    Object? hook,
    MotionPropertyKey? property,
    bool shortest = false,
    double period = 6.283185307179586,
    bool inheritVelocity = true,
    bool paint = false,
    void Function()? invalidate,
    MotionSample? sample,
    MotionSnap? snap,
    MotionClamp? clamp,
    void Function()? onStart,
    void Function()? onUpdate,
    void Function()? onSettled,
    void Function()? onComplete,
    void Function(MotionCancelReason reason)? onCancel,
  }) {
    final start = from ?? read();
    return engine.springDouble(
      () => start,
      _motionWriter(this, write, paint: paint, invalidate: invalidate),
      to,
      spring: spring,
      initialVelocity: initialVelocity,
      delay: delay,
      overwrite: overwrite,
      owner: owner,
      hook: hook,
      property: property,
      shortest: shortest,
      period: period,
      inheritVelocity: inheritVelocity,
      sample: sample,
      snap: snap,
      clamp: clamp,
      onStart: onStart,
      onUpdate: onUpdate,
      onSettled: onSettled,
      onComplete: onComplete,
      onCancel: onCancel,
    );
  }

  MotionHandle damp(
    double from,
    double to, {
    required void Function(double value) onValue,
    Damp damp = const Damp(),
    double delay = 0.0,
    Object? owner,
    Object? hook,
    bool paint = false,
    void Function()? invalidate,
    MotionSample? sample,
    MotionSnap? snap,
    MotionClamp? clamp,
    void Function()? onStart,
    void Function()? onUpdate,
    void Function()? onSettled,
    void Function()? onComplete,
    void Function(MotionCancelReason reason)? onCancel,
  }) => dampDouble(
    () => from,
    onValue,
    to,
    from: from,
    damp: damp,
    delay: delay,
    owner: owner,
    hook: hook,
    paint: paint,
    invalidate: invalidate,
    sample: sample,
    snap: snap,
    clamp: clamp,
    onStart: onStart,
    onUpdate: onUpdate,
    onSettled: onSettled,
    onComplete: onComplete,
    onCancel: onCancel,
  );

  MotionHandle dampDouble(
    double Function() read,
    void Function(double value) write,
    double to, {
    double? from,
    Damp damp = const Damp(),
    double delay = 0.0,
    Overwrite overwrite = Overwrite.auto,
    Object? owner,
    Object? hook,
    MotionPropertyKey? property,
    bool shortest = false,
    double period = 6.283185307179586,
    bool paint = false,
    void Function()? invalidate,
    MotionSample? sample,
    MotionSnap? snap,
    MotionClamp? clamp,
    void Function()? onStart,
    void Function()? onUpdate,
    void Function()? onSettled,
    void Function()? onComplete,
    void Function(MotionCancelReason reason)? onCancel,
  }) {
    final start = from ?? read();
    return engine.dampDouble(
      () => start,
      _motionWriter(this, write, paint: paint, invalidate: invalidate),
      to,
      damp: damp,
      delay: delay,
      overwrite: overwrite,
      owner: owner,
      hook: hook,
      property: property,
      shortest: shortest,
      period: period,
      sample: sample,
      snap: snap,
      clamp: clamp,
      onStart: onStart,
      onUpdate: onUpdate,
      onSettled: onSettled,
      onComplete: onComplete,
      onCancel: onCancel,
    );
  }

  MotionHandle inertia(
    double from, {
    required double velocity,
    required void Function(double value) onValue,
    Inertia inertia = const Inertia(),
    double delay = 0.0,
    Object? owner,
    Object? hook,
    bool paint = false,
    void Function()? invalidate,
    MotionSample? sample,
    MotionSnap? snap,
    MotionClamp? clamp,
    void Function()? onStart,
    void Function()? onUpdate,
    void Function()? onSettled,
    void Function()? onComplete,
    void Function(MotionCancelReason reason)? onCancel,
  }) => inertiaDouble(
    () => from,
    onValue,
    velocity: velocity,
    inertia: inertia,
    delay: delay,
    owner: owner,
    hook: hook,
    paint: paint,
    invalidate: invalidate,
    sample: sample,
    snap: snap,
    clamp: clamp,
    onStart: onStart,
    onUpdate: onUpdate,
    onSettled: onSettled,
    onComplete: onComplete,
    onCancel: onCancel,
  );

  MotionHandle inertiaDouble(
    double Function() read,
    void Function(double value) write, {
    required double velocity,
    Inertia inertia = const Inertia(),
    double delay = 0.0,
    Overwrite overwrite = Overwrite.auto,
    Object? owner,
    Object? hook,
    MotionPropertyKey? property,
    bool paint = false,
    void Function()? invalidate,
    MotionSample? sample,
    MotionSnap? snap,
    MotionClamp? clamp,
    void Function()? onStart,
    void Function()? onUpdate,
    void Function()? onSettled,
    void Function()? onComplete,
    void Function(MotionCancelReason reason)? onCancel,
  }) => engine.inertiaDouble(
    read,
    _motionWriter(this, write, paint: paint, invalidate: invalidate),
    velocity: velocity,
    inertia: inertia,
    delay: delay,
    overwrite: overwrite,
    owner: owner,
    hook: hook,
    property: property,
    sample: sample,
    snap: snap,
    clamp: clamp,
    onStart: onStart,
    onUpdate: onUpdate,
    onSettled: onSettled,
    onComplete: onComplete,
    onCancel: onCancel,
  );
}

extension GNodePhysicsMotion on GNodeMotion {
  MotionHandle spring({
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
    Spring spring = Spring.snappy,
    double initialVelocity = 0.0,
    double delay = 0.0,
    Overwrite overwrite = Overwrite.auto,
    Object? hook,
    bool shortest = false,
    double period = 6.283185307179586,
    bool inheritVelocity = true,
    MotionSample? sample,
    MotionSnap? snap,
    MotionClamp? clamp,
    void Function()? onStart,
    void Function()? onUpdate,
    void Function()? onSettled,
    void Function()? onComplete,
    void Function(MotionCancelReason reason)? onCancel,
  }) => _nodeMotion.springProperties(
    _nodeTargetProperties(
      node,
      x: x,
      y: y,
      scale: scale,
      scaleX: scaleX,
      scaleY: scaleY,
      rotation: rotation,
      skewX: skewX,
      skewY: skewY,
      pivotX: pivotX,
      pivotY: pivotY,
      alpha: alpha,
      shortest: shortest,
      period: period,
    ),
    owner: node,
    hook: hook,
    spring: spring,
    initialVelocity: initialVelocity,
    delay: delay,
    overwrite: overwrite,
    inheritVelocity: inheritVelocity,
    sample: sample,
    snap: snap,
    clamp: clamp,
    onStart: onStart,
    onUpdate: onUpdate,
    onSettled: onSettled,
    onComplete: onComplete,
    onCancel: onCancel,
  );

  MotionHandle damp({
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
    Damp damp = const Damp(),
    double delay = 0.0,
    Overwrite overwrite = Overwrite.auto,
    Object? hook,
    bool shortest = false,
    double period = 6.283185307179586,
    MotionSample? sample,
    MotionSnap? snap,
    MotionClamp? clamp,
    void Function()? onStart,
    void Function()? onUpdate,
    void Function()? onSettled,
    void Function()? onComplete,
    void Function(MotionCancelReason reason)? onCancel,
  }) => _nodeMotion.dampProperties(
    _nodeTargetProperties(
      node,
      x: x,
      y: y,
      scale: scale,
      scaleX: scaleX,
      scaleY: scaleY,
      rotation: rotation,
      skewX: skewX,
      skewY: skewY,
      pivotX: pivotX,
      pivotY: pivotY,
      alpha: alpha,
      shortest: shortest,
      period: period,
    ),
    owner: node,
    hook: hook,
    damp: damp,
    delay: delay,
    overwrite: overwrite,
    sample: sample,
    snap: snap,
    clamp: clamp,
    onStart: onStart,
    onUpdate: onUpdate,
    onSettled: onSettled,
    onComplete: onComplete,
    onCancel: onCancel,
  );

  MotionHandle inertia({
    double? velocityX,
    double? velocityY,
    double? velocityRotation,
    MotionBounds? xBounds,
    MotionBounds? yBounds,
    MotionBounds? rotationBounds,
    double friction = 5.0,
    double tolerance = 0.01,
    double delay = 0.0,
    Overwrite overwrite = Overwrite.auto,
    Object? hook,
    void Function()? onStart,
    void Function()? onUpdate,
    void Function()? onSettled,
    void Function()? onComplete,
    void Function(MotionCancelReason reason)? onCancel,
  }) {
    final properties = <DoubleInertiaProperty>[];
    if (velocityX != null) {
      properties.add(
        DoubleInertiaProperty(
          property: GNodeMotionProperties.x,
          read: () => node.x,
          write: (value) => node.x = value,
          velocity: velocityX,
          inertia: _axisInertia(xBounds, friction, tolerance),
        ),
      );
    }
    if (velocityY != null) {
      properties.add(
        DoubleInertiaProperty(
          property: GNodeMotionProperties.y,
          read: () => node.y,
          write: (value) => node.y = value,
          velocity: velocityY,
          inertia: _axisInertia(yBounds, friction, tolerance),
        ),
      );
    }
    if (velocityRotation != null) {
      properties.add(
        DoubleInertiaProperty(
          property: GNodeMotionProperties.rotation,
          read: () => node.rotation,
          write: (value) => node.rotation = value,
          velocity: velocityRotation,
          inertia: _axisInertia(rotationBounds, friction, tolerance),
        ),
      );
    }
    return _nodeMotion.inertiaProperties(
      properties,
      owner: node,
      hook: hook,
      delay: delay,
      overwrite: overwrite,
      onStart: onStart,
      onUpdate: onUpdate,
      onSettled: onSettled,
      onComplete: onComplete,
      onCancel: onCancel,
    );
  }

  MotionEngine get _nodeMotion {
    if (!node.isAttached) {
      throw StateError('Attach the node to a stage before starting motion.');
    }
    return node.stage.motion.engine;
  }
}

List<DoubleMotionProperty> _nodeTargetProperties(
  GNode node, {
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
  required bool shortest,
  required double period,
}) {
  if (scale != null && (scaleX != null || scaleY != null)) {
    throw ArgumentError('Use scale or scaleX/scaleY, not both.');
  }
  final properties = <DoubleMotionProperty>[];
  void add(
    MotionPropertyKey property,
    double Function() read,
    void Function(double value) write,
    double? target, {
    bool circular = false,
  }) {
    if (target == null) return;
    properties.add(
      DoubleMotionProperty(
        property: property,
        read: read,
        write: write,
        to: target,
        shortest: circular && shortest,
        period: period,
      ),
    );
  }

  add(GNodeMotionProperties.x, () => node.x, (v) => node.x = v, x);
  add(GNodeMotionProperties.y, () => node.y, (v) => node.y = v, y);
  if (scale != null) {
    add(GNodeMotionProperties.scaleX, () => node.scaleX, (v) => node.scaleX = v, scale);
    add(GNodeMotionProperties.scaleY, () => node.scaleY, (v) => node.scaleY = v, scale);
  } else {
    add(GNodeMotionProperties.scaleX, () => node.scaleX, (v) => node.scaleX = v, scaleX);
    add(GNodeMotionProperties.scaleY, () => node.scaleY, (v) => node.scaleY = v, scaleY);
  }
  add(
    GNodeMotionProperties.rotation,
    () => node.rotation,
    (v) => node.rotation = v,
    rotation,
    circular: true,
  );
  add(GNodeMotionProperties.skewX, () => node.skewX, (v) => node.skewX = v, skewX);
  add(GNodeMotionProperties.skewY, () => node.skewY, (v) => node.skewY = v, skewY);
  add(GNodeMotionProperties.pivotX, () => node.pivotX, (v) => node.pivotX = v, pivotX);
  add(GNodeMotionProperties.pivotY, () => node.pivotY, (v) => node.pivotY = v, pivotY);
  add(GNodeMotionProperties.alpha, () => node.alpha, (v) => node.alpha = v, alpha);
  return properties;
}

Inertia _axisInertia(MotionBounds? bounds, double friction, double tolerance) => bounds == null
    ? Inertia(friction: friction, tolerance: tolerance)
    : bounds.inertia(friction: friction, tolerance: tolerance);

void Function(double value) _motionWriter(
  GraphXMotion motion,
  void Function(double value) write, {
  required bool paint,
  required void Function()? invalidate,
}) {
  if (!paint && invalidate == null) return write;
  return (value) {
    write(value);
    invalidate?.call();
    if (paint) motion.stage.requestPaint();
  };
}

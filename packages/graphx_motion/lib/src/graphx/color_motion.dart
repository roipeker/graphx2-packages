import 'package:graphx/graphx.dart';
import 'package:graphx_motion/motion.dart';

import 'stage_motion.dart';

abstract final class GColorTransformMotionProperties {
  static const transform = MotionPropertyKey('GNode.colorTransform');
}

/// Motion for a detached [GColorTransform] value with an explicit GraphX
/// owner that receives the interpolated transform.
extension GColorTransformMotionExtension on GColorTransform {
  GColorTransformMotion motion({required GNode owner}) => GColorTransformMotion._(owner, this);
}

final class GColorTransformMotion {
  GColorTransformMotion._(this.owner, this.source);

  final GNode owner;
  final GColorTransform source;

  MotionHandle to(
    GColorTransform target, {
    MotionSpec? motion,
    double? duration,
    EaseFunction? ease,
    Object? hook,
    Overwrite? overwrite,
    void Function()? onStart,
    void Function()? onUpdate,
    void Function()? onComplete,
    void Function(MotionCancelReason reason)? onCancel,
  }) => _motion.engine.toConfiguredDouble(
    () => 0.0,
    _writer(source, target),
    1.0,
    owner: owner,
    hook: hook,
    property: GColorTransformMotionProperties.transform,
    motion: motion,
    duration: duration,
    ease: ease,
    overwrite: overwrite,
    onStart: onStart,
    onUpdate: onUpdate,
    onComplete: onComplete,
    onCancel: onCancel,
  );

  MotionHandle spring(
    GColorTransform target, {
    Spring spring = Spring.snappy,
    Object? hook,
    Overwrite overwrite = Overwrite.auto,
    void Function()? onStart,
    void Function()? onUpdate,
    void Function()? onSettled,
    void Function()? onComplete,
    void Function(MotionCancelReason reason)? onCancel,
  }) => _motion.engine.springDouble(
    () => 0.0,
    _writer(source, target),
    1.0,
    owner: owner,
    hook: hook,
    property: GColorTransformMotionProperties.transform,
    spring: spring,
    overwrite: overwrite,
    inheritVelocity: false,
    onStart: onStart,
    onUpdate: onUpdate,
    onSettled: onSettled,
    onComplete: onComplete,
    onCancel: onCancel,
  );

  MotionHandle damp(
    GColorTransform target, {
    Damp damp = const Damp(),
    Object? hook,
    Overwrite overwrite = Overwrite.auto,
    void Function()? onStart,
    void Function()? onUpdate,
    void Function()? onSettled,
    void Function()? onComplete,
    void Function(MotionCancelReason reason)? onCancel,
  }) => _motion.engine.dampDouble(
    () => 0.0,
    _writer(source, target),
    1.0,
    owner: owner,
    hook: hook,
    property: GColorTransformMotionProperties.transform,
    damp: damp,
    overwrite: overwrite,
    onStart: onStart,
    onUpdate: onUpdate,
    onSettled: onSettled,
    onComplete: onComplete,
    onCancel: onCancel,
  );

  void cancel({Object? hook, bool complete = false}) =>
      _motion.cancel(owner: owner, hook: hook, complete: complete);

  GraphXMotion get _motion {
    if (!owner.isAttached) {
      throw StateError(
        'Attach the owner node to a stage before starting color-transform motion.',
      );
    }
    return owner.stage.motion;
  }

  void Function(double value) _writer(
    GColorTransform from,
    GColorTransform to,
  ) => (t) {
    owner.setColorTransformValues(
      _lerp(from.redMultiplier, to.redMultiplier, t),
      _lerp(from.greenMultiplier, to.greenMultiplier, t),
      _lerp(from.blueMultiplier, to.blueMultiplier, t),
      _lerp(from.alphaMultiplier, to.alphaMultiplier, t),
      _lerp(from.redOffset, to.redOffset, t),
      _lerp(from.greenOffset, to.greenOffset, t),
      _lerp(from.blueOffset, to.blueOffset, t),
      _lerp(from.alphaOffset, to.alphaOffset, t),
    );
  };
}

double _lerp(double a, double b, double t) => a + (b - a) * t;

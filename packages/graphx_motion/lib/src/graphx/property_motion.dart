import 'package:graphx_motion/motion.dart';

import 'stage_motion.dart';

/// Generic typed property entry point on the GraphX-owned Motion clock.
///
/// This is the escape hatch for values that do not have dedicated GraphX
/// facade sugar. Known retained GraphX properties should keep using their
/// specialized facade so hot paths stay optimized.
extension GraphXMotionPropertyExtension on GraphXMotion {
  MotionHandle to<T>(
    MotionProperty<T> property,
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
    Object? hook,
    void Function()? onStart,
    void Function()? onUpdate,
    void Function(int iteration)? onRepeat,
    void Function()? onComplete,
    void Function(MotionCancelReason reason)? onCancel,
  }) => engine.to<T>(
    property,
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
    hook: hook,
    onStart: onStart,
    onUpdate: onUpdate,
    onRepeat: onRepeat,
    onComplete: onComplete,
    onCancel: onCancel,
  );

  MotionHandle from<T>(
    MotionProperty<T> property,
    T source, {
    MotionSpec? motion,
    MotionInterpolator<T>? interpolate,
    double? duration,
    EaseFunction? ease,
    double? delay,
    int? repeat,
    double? repeatDelay,
    bool? yoyo,
    Overwrite? overwrite,
    Object? hook,
    void Function()? onStart,
    void Function()? onUpdate,
    void Function(int iteration)? onRepeat,
    void Function()? onComplete,
    void Function(MotionCancelReason reason)? onCancel,
  }) => engine.from<T>(
    property,
    source,
    motion: motion,
    interpolate: interpolate,
    duration: duration,
    ease: ease,
    delay: delay,
    repeat: repeat,
    repeatDelay: repeatDelay,
    yoyo: yoyo,
    overwrite: overwrite,
    hook: hook,
    onStart: onStart,
    onUpdate: onUpdate,
    onRepeat: onRepeat,
    onComplete: onComplete,
    onCancel: onCancel,
  );
}

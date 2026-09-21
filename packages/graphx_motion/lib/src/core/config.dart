part of '../../motion.dart';

final Expando<MotionSpec> _motionDefaultsByEngine = Expando<MotionSpec>('graphx.motion.defaults');

/// Reusable duration defaults and configured duration entry points.
///
/// Resolution precedence is:
///
/// engine defaults -> call [motion] -> explicit named arguments.
///
/// The result is resolved once before a runtime is acquired, so cascading
/// defaults add no sampling-time work.
extension MotionEngineConfiguration on MotionEngine {
  MotionSpec get defaults => _motionDefaultsByEngine[this] ?? const MotionSpec();

  set defaults(MotionSpec value) {
    _validateMotionSpec(value);
    _motionDefaultsByEngine[this] = value;
  }

  MotionHandle toConfiguredDouble(
    double Function() read,
    void Function(double value) write,
    double to, {
    double? from,
    MotionSpec? motion,
    double? duration,
    EaseFunction? ease,
    double? delay,
    int? repeat,
    double? repeatDelay,
    bool? yoyo,
    Overwrite? overwrite,
    Object? owner,
    Object? hook,
    MotionPropertyKey? property,
    bool shortest = false,
    double period = math.pi * 2.0,
    MotionSample? sample,
    MotionSnap? snap,
    MotionClamp? clamp,
    void Function()? onStart,
    void Function()? onUpdate,
    void Function(int iteration)? onRepeat,
    void Function()? onComplete,
    void Function(MotionCancelReason reason)? onCancel,
  }) {
    final resolved = _resolved(
      motion: motion,
      duration: duration,
      ease: ease,
      delay: delay,
      repeat: repeat,
      repeatDelay: repeatDelay,
      yoyo: yoyo,
      overwrite: overwrite,
    );
    return toDouble(
      read,
      write,
      to,
      from: from,
      duration: resolved.duration,
      ease: resolved.ease,
      delay: resolved.delay,
      repeat: resolved.repeat,
      repeatDelay: resolved.repeatDelay,
      yoyo: resolved.yoyo,
      overwrite: resolved.overwrite,
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
      onRepeat: onRepeat,
      onComplete: onComplete,
      onCancel: onCancel,
    );
  }

  MotionHandle toConfiguredProperties(
    Iterable<DoubleMotionProperty> properties, {
    Object? owner,
    Object? hook,
    MotionSpec? motion,
    double? duration,
    EaseFunction? ease,
    double? delay,
    int? repeat,
    double? repeatDelay,
    bool? yoyo,
    Overwrite? overwrite,
    MotionSample? sample,
    MotionSnap? snap,
    MotionClamp? clamp,
    void Function()? onStart,
    void Function()? onUpdate,
    void Function(int iteration)? onRepeat,
    void Function()? onComplete,
    void Function(MotionCancelReason reason)? onCancel,
  }) {
    final resolved = _resolved(
      motion: motion,
      duration: duration,
      ease: ease,
      delay: delay,
      repeat: repeat,
      repeatDelay: repeatDelay,
      yoyo: yoyo,
      overwrite: overwrite,
    );
    return toProperties(
      properties,
      owner: owner,
      hook: hook,
      duration: resolved.duration,
      ease: resolved.ease,
      delay: resolved.delay,
      repeat: resolved.repeat,
      repeatDelay: resolved.repeatDelay,
      yoyo: resolved.yoyo,
      overwrite: resolved.overwrite,
      sample: sample,
      snap: snap,
      clamp: clamp,
      onStart: onStart,
      onUpdate: onUpdate,
      onRepeat: onRepeat,
      onComplete: onComplete,
      onCancel: onCancel,
    );
  }

  _ResolvedMotionSpec _resolved({
    MotionSpec? motion,
    double? duration,
    EaseFunction? ease,
    double? delay,
    int? repeat,
    double? repeatDelay,
    bool? yoyo,
    Overwrite? overwrite,
  }) {
    final result = _resolveMotionSpec(
      defaults: defaults,
      motion: motion,
      duration: duration,
      ease: ease,
      delay: delay,
      repeat: repeat,
      repeatDelay: repeatDelay,
      yoyo: yoyo,
      overwrite: overwrite,
    );
    _validateResolvedSpec(result);
    return result;
  }

  void _reverseRuntime(_MotionRuntime runtime) {
    if (runtime.isPhysics) {
      throw UnsupportedError('Physics motion cannot reverse its playhead.');
    }
    if (!_isLive(runtime, runtime.generation)) return;
    if (!runtime.started || runtime.duration <= 0.0) return;

    // cycleElapsed always advances toward duration. Flip the orientation and
    // mirror elapsed time so the directed/eased sample is unchanged at the
    // instant reverse() is called.
    runtime.cycleElapsed = runtime.duration - runtime.cycleElapsed;
    runtime.forward = !runtime.forward;

    _applyDurationRuntime(
      runtime,
      runtime.cycleElapsed / runtime.duration,
      runtime.generation,
    );
  }
}

void _validateMotionSpec(MotionSpec value) {
  final duration = value.duration;
  if (duration != null && (!duration.isFinite || duration < 0.0)) {
    throw ArgumentError.value(duration, 'duration');
  }
  final delay = value.delay;
  if (delay != null && (!delay.isFinite || delay < 0.0)) {
    throw ArgumentError.value(delay, 'delay');
  }
  final repeat = value.repeat;
  if (repeat != null && repeat < -1) {
    throw ArgumentError.value(repeat, 'repeat');
  }
  final repeatDelay = value.repeatDelay;
  if (repeatDelay != null && (!repeatDelay.isFinite || repeatDelay < 0.0)) {
    throw ArgumentError.value(repeatDelay, 'repeatDelay');
  }
}

void _validateResolvedSpec(_ResolvedMotionSpec value) {
  _validateMotionSpec(
    MotionSpec(
      duration: value.duration,
      delay: value.delay,
      repeat: value.repeat,
      repeatDelay: value.repeatDelay,
      yoyo: value.yoyo,
      ease: value.ease,
      overwrite: value.overwrite,
    ),
  );
  if (value.duration == 0.0 && value.repeat != 0) {
    throw ArgumentError('A zero-duration motion cannot repeat.');
  }
}

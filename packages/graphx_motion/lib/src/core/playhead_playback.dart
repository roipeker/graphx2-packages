part of '../../motion.dart';

/// Ergonomic playback policy for any deterministic finite [MotionPlayhead].
///
/// This is intentionally implemented as an ordinary Motion tween over the
/// playhead's time property. Timeline and finite tween playback therefore share
/// one repeat/yoyo/easing scheduler instead of maintaining parallel state
/// machines.
extension MotionPlayheadPlaybackExtension on MotionPlayheadMotion {
  /// Drives the playhead from its current [MotionPlayhead.time] to its end.
  ///
  /// [timeScale] controls wall-clock playback speed relative to authored
  /// seconds. A value of `2` runs twice as fast; `.5` runs at half speed.
  /// Repeat/yoyo semantics are the normal Motion duration semantics and repeat
  /// the segment beginning at the playhead's current time.
  MotionHandle play({
    double timeScale = 1.0,
    MotionSpec? motion,
    EaseFunction ease = Ease.linear,
    double delay = 0.0,
    int repeat = 0,
    double repeatDelay = 0.0,
    bool yoyo = false,
    Overwrite? overwrite,
    Object? hook,
    void Function()? onStart,
    void Function()? onUpdate,
    void Function(int iteration)? onRepeat,
    void Function()? onComplete,
    void Function(MotionCancelReason reason)? onCancel,
  }) {
    if (!timeScale.isFinite || timeScale <= 0.0) {
      throw ArgumentError.value(
        timeScale,
        'timeScale',
        'Must be finite and > 0.',
      );
    }

    final target = playhead.duration;
    final remaining = (target - playhead.time).abs();
    final resolvedDuration = remaining / timeScale;

    return to(
      time: target,
      motion: motion,
      duration: resolvedDuration,
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
}

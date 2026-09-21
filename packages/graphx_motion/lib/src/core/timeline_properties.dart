part of '../../motion.dart';

/// Low-level retained scalar bridge used by typed host facades such as GraphX.
extension MotionTimelinePropertiesExtension on MotionTimeline {
  MotionTimeline toProperties(
    Iterable<DoubleMotionProperty> properties, {
    required Object owner,
    Object? at,
    MotionSpec? motion,
    double? duration,
    EaseFunction? ease,
    double? delay,
    int? repeat,
    double? repeatDelay,
    bool? yoyo,
    Overwrite? overwrite,
  }) => add(
    MotionClip.properties(
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
    ),
    at: at,
  );
}

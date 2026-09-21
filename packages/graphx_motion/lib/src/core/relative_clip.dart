part of '../../motion.dart';

/// Retained relative motion for numeric properties.
///
/// The delta is resolved from the property's value at the clip's actual local
/// start, so sequential composition, nested timelines and deterministic seek
/// all share the same start-capture semantics as ordinary retained clips.
extension MotionDoublePropertyRelativeClipExtension on MotionProperty<double> {
  MotionClip clipBy(
    double delta, {
    MotionSpec? motion,
    double? duration,
    EaseFunction? ease,
    double? delay,
    int? repeat,
    double? repeatDelay,
    bool? yoyo,
    Overwrite? overwrite,
  }) {
    if (!delta.isFinite) {
      throw ArgumentError.value(delta, 'delta', 'Must be finite.');
    }
    return _RelativeDoublePropertyClip(
      this,
      delta,
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

final class _RelativeDoublePropertyClip extends _ConfiguredMotionClip {
  const _RelativeDoublePropertyClip(
    this.property,
    this.delta, {
    super.motion,
    super.duration,
    super.ease,
    super.delay,
    super.repeat,
    super.repeatDelay,
    super.yoyo,
    super.overwrite,
  });

  final MotionProperty<double> property;
  final double delta;

  @override
  _BoundMotionClip _bind(MotionTimeline timeline) =>
      _BoundRelativeDoublePropertyClip(property, delta, resolve(timeline));
}

final class _BoundRelativeDoublePropertyClip with _ResolvedClipSpan implements _BoundMotionClip {
  const _BoundRelativeDoublePropertyClip(
    this.property,
    this.delta,
    this.spec,
  );

  final MotionProperty<double> property;
  final double delta;

  @override
  final _ResolvedMotionSpec spec;

  @override
  void schedule(
    MotionEngine engine, {
    required double offset,
    required List<MotionHandle> handles,
    required List<_TimelineCall> calls,
  }) {
    double? start;
    final descriptor = DoubleMotionProperty(
      property: property.motionKey,
      read: () => 0.0,
      write: (t) {
        start ??= property.read();
        property.set(start! + delta * t);
      },
      from: 0.0,
      to: 1.0,
    );
    _scheduleTimelineProperties(
      engine,
      handles,
      [descriptor],
      owner: property.motionOwner,
      offset: offset,
      spec: spec,
    );
  }
}

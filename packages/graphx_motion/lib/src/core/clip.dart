part of '../../motion.dart';

/// Passive retained motion definition.
///
/// A clip never owns a clock or runtime state. [MotionTimeline.add] binds it to
/// timeline defaults and, when the root timeline is prepared, compiles it into
/// ordinary pooled MotionEngine runtimes controlled by the root playhead.
abstract interface class MotionClip {
  _BoundMotionClip _bind(MotionTimeline timeline);

  static MotionClip property<T>(
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
  }) => _PropertyMotionClip<T>(
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
  );

  static MotionClip targets(
    Iterable<MotionTarget> targets, {
    MotionSpec? motion,
    double? duration,
    EaseFunction? ease,
    double? delay,
    int? repeat,
    double? repeatDelay,
    bool? yoyo,
    Overwrite? overwrite,
  }) => _TargetGroupMotionClip(
    targets,
    motion: motion,
    duration: duration,
    ease: ease,
    delay: delay,
    repeat: repeat,
    repeatDelay: repeatDelay,
    yoyo: yoyo,
    overwrite: overwrite,
  );

  static MotionClip properties(
    Iterable<DoubleMotionProperty> properties, {
    required Object owner,
    MotionSpec? motion,
    double? duration,
    EaseFunction? ease,
    double? delay,
    int? repeat,
    double? repeatDelay,
    bool? yoyo,
    Overwrite? overwrite,
  }) => _DoublePropertiesMotionClip(
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

  /// Groups passive clips at the same local start position.
  ///
  /// This is authoring composition only; it does not add a runtime layer.
  static MotionClip parallel(Iterable<MotionClip> clips) => _ParallelMotionClip(clips);
}

abstract class _ConfiguredMotionClip implements MotionClip {
  const _ConfiguredMotionClip({
    this.motion,
    this.duration,
    this.ease,
    this.delay,
    this.repeat,
    this.repeatDelay,
    this.yoyo,
    this.overwrite,
  });

  final MotionSpec? motion;
  final double? duration;
  final EaseFunction? ease;
  final double? delay;
  final int? repeat;
  final double? repeatDelay;
  final bool? yoyo;
  final Overwrite? overwrite;

  _ResolvedMotionSpec resolve(MotionTimeline timeline) {
    final spec = timeline._resolved(
      motion: motion,
      duration: duration,
      ease: ease,
      delay: delay,
      repeat: repeat,
      repeatDelay: repeatDelay,
      yoyo: yoyo,
      overwrite: overwrite,
    );
    _validateTimelineSpec(spec);
    return spec;
  }
}

final class _PropertyMotionClip<T> extends _ConfiguredMotionClip {
  const _PropertyMotionClip(
    this.property,
    this.target, {
    super.motion,
    this.interpolate,
    super.duration,
    super.ease,
    super.delay,
    super.repeat,
    super.repeatDelay,
    super.yoyo,
    super.overwrite,
  });

  final MotionProperty<T> property;
  final T target;
  final MotionInterpolator<T>? interpolate;

  @override
  _BoundMotionClip _bind(MotionTimeline timeline) => _BoundPropertyMotionClip<T>(
    property,
    target,
    interpolate,
    resolve(timeline),
  );
}

final class _TargetGroupMotionClip extends _ConfiguredMotionClip {
  _TargetGroupMotionClip(
    Iterable<MotionTarget> targets, {
    super.motion,
    super.duration,
    super.ease,
    super.delay,
    super.repeat,
    super.repeatDelay,
    super.yoyo,
    super.overwrite,
  }) : targets = targets.toList(growable: false);

  final List<MotionTarget> targets;

  @override
  _BoundMotionClip _bind(MotionTimeline timeline) {
    if (targets.isEmpty) return const _BoundEmptyMotionClip();
    final owner = targets.first._owner;
    for (final target in targets.skip(1)) {
      if (!identical(target._owner, owner)) {
        throw ArgumentError(
          'MotionClip.targets values must share one owner. '
          'Declare related MotionProperty values with the same owner.',
        );
      }
    }
    return _BoundTargetGroupMotionClip(targets, resolve(timeline));
  }
}

final class _DoublePropertiesMotionClip extends _ConfiguredMotionClip {
  _DoublePropertiesMotionClip(
    Iterable<DoubleMotionProperty> properties, {
    required this.owner,
    super.motion,
    super.duration,
    super.ease,
    super.delay,
    super.repeat,
    super.repeatDelay,
    super.yoyo,
    super.overwrite,
  }) : properties = properties.toList(growable: false);

  final Object owner;
  final List<DoubleMotionProperty> properties;

  @override
  _BoundMotionClip _bind(MotionTimeline timeline) => properties.isEmpty
      ? const _BoundEmptyMotionClip()
      : _BoundDoublePropertiesMotionClip(owner, properties, resolve(timeline));
}

abstract interface class _BoundMotionClip {
  double get span;

  void schedule(
    MotionEngine engine, {
    required double offset,
    required List<MotionHandle> handles,
    required List<_TimelineCall> calls,
  });
}

mixin _ResolvedClipSpan {
  _ResolvedMotionSpec get spec;

  double get span =>
      spec.delay + spec.duration * (spec.repeat + 1) + spec.repeatDelay * spec.repeat;
}

void _scheduleTimelineProperties(
  MotionEngine engine,
  List<MotionHandle> handles,
  List<DoubleMotionProperty> properties, {
  required Object owner,
  required double offset,
  required _ResolvedMotionSpec spec,
}) {
  final handle = engine.toProperties(
    properties,
    owner: owner,
    duration: spec.duration,
    ease: spec.ease,
    delay: offset + spec.delay,
    repeat: spec.repeat,
    repeatDelay: spec.repeatDelay,
    yoyo: spec.yoyo,
    overwrite: Overwrite.none,
  );
  _registerTimelineProperties(handle, properties, spec.overwrite);
  handle.pause();
  handles.add(handle);
}

final class _BoundPropertyMotionClip<T> with _ResolvedClipSpan implements _BoundMotionClip {
  const _BoundPropertyMotionClip(
    this.property,
    this.target,
    this.interpolate,
    this.spec,
  );

  final MotionProperty<T> property;
  final T target;
  final MotionInterpolator<T>? interpolate;
  @override
  final _ResolvedMotionSpec spec;

  @override
  void schedule(
    MotionEngine engine, {
    required double offset,
    required List<MotionHandle> handles,
    required List<_TimelineCall> calls,
  }) {
    final lerp = interpolate ?? property.interpolate;
    T? start;
    final descriptor = DoubleMotionProperty(
      read: () => 0.0,
      write: (t) {
        start ??= property.read();
        property.set(lerp(start as T, target, t));
      },
      from: 0.0,
      to: 1.0,
      property: property.motionKey,
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

final class _BoundTargetGroupMotionClip with _ResolvedClipSpan implements _BoundMotionClip {
  const _BoundTargetGroupMotionClip(this.targets, this.spec);

  final List<MotionTarget> targets;
  @override
  final _ResolvedMotionSpec spec;

  @override
  void schedule(
    MotionEngine engine, {
    required double offset,
    required List<MotionHandle> handles,
    required List<_TimelineCall> calls,
  }) {
    if (targets.isEmpty) return;
    final properties = targets.map((target) => target._compile()).toList(growable: false);
    _scheduleTimelineProperties(
      engine,
      handles,
      properties,
      owner: targets.first._owner,
      offset: offset,
      spec: spec,
    );
  }
}

final class _BoundDoublePropertiesMotionClip with _ResolvedClipSpan implements _BoundMotionClip {
  const _BoundDoublePropertiesMotionClip(this.owner, this.properties, this.spec);

  final Object owner;
  final List<DoubleMotionProperty> properties;
  @override
  final _ResolvedMotionSpec spec;

  @override
  void schedule(
    MotionEngine engine, {
    required double offset,
    required List<MotionHandle> handles,
    required List<_TimelineCall> calls,
  }) {
    _scheduleTimelineProperties(
      engine,
      handles,
      properties,
      owner: owner,
      offset: offset,
      spec: spec,
    );
  }
}

final class _BoundEmptyMotionClip implements _BoundMotionClip {
  const _BoundEmptyMotionClip();

  @override
  double get span => 0.0;

  @override
  void schedule(
    MotionEngine engine, {
    required double offset,
    required List<MotionHandle> handles,
    required List<_TimelineCall> calls,
  }) {}
}

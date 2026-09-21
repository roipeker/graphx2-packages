part of '../../motion.dart';

/// Mutable authoring clip for one strongly typed keyframe track.
///
/// Frames use normalized positions in 0..1. The ease on a frame controls the
/// segment ending at that frame. The builder is passive and owns no runtime.
/// A missing frame at 0 starts from the property's value at local start; a
/// missing frame at 1 holds the last authored value through the clip end.
final class MotionKeyframes<T> implements MotionClip {
  MotionKeyframes._(
    this.property,
    this.duration, {
    this.ease,
    this.interpolate,
  });

  final MotionProperty<T> property;
  final double duration;
  final EaseFunction? ease;
  final MotionInterpolator<T>? interpolate;
  final List<_MotionKeyframe<T>> _frames = <_MotionKeyframe<T>>[];

  MotionKeyframes<T> at(
    double position,
    T value, {
    EaseFunction? ease,
  }) {
    if (!position.isFinite || position < 0.0 || position > 1.0) {
      throw ArgumentError.value(position, 'position', 'Must be finite and within 0..1.');
    }
    if (_frames.isNotEmpty && position <= _frames.last.position) {
      throw ArgumentError('Keyframe positions must be strictly increasing.');
    }
    _frames.add(_MotionKeyframe<T>(position, value, ease));
    return this;
  }

  @override
  _BoundMotionClip _bind(MotionTimeline timeline) {
    if (_frames.isEmpty) {
      throw StateError('Keyframes require at least one authored frame.');
    }
    final resolvedEase = ease ?? timeline._resolved(duration: duration).ease;
    return _BoundPropertyKeyframesClip<T>(
      property,
      duration,
      List<_MotionKeyframe<T>>.of(_frames, growable: false),
      resolvedEase,
      interpolate,
    );
  }
}

final class _MotionKeyframe<T> {
  const _MotionKeyframe(this.position, this.value, this.ease);

  final double position;
  final T value;
  final EaseFunction? ease;
}

extension MotionPropertyKeyframesExtension<T> on MotionProperty<T> {
  MotionKeyframes<T> keyframes({
    required double duration,
    EaseFunction? ease,
    MotionInterpolator<T>? interpolate,
  }) {
    if (!duration.isFinite || duration <= 0.0) {
      throw ArgumentError.value(duration, 'duration', 'Must be finite and > 0.');
    }
    return MotionKeyframes<T>._(
      this,
      duration,
      ease: ease,
      interpolate: interpolate,
    );
  }
}

final class _BoundPropertyKeyframesClip<T> implements _BoundMotionClip {
  const _BoundPropertyKeyframesClip(
    this.property,
    this.duration,
    this.frames,
    this.ease,
    this.interpolate,
  );

  final MotionProperty<T> property;
  final double duration;
  final List<_MotionKeyframe<T>> frames;
  final EaseFunction ease;
  final MotionInterpolator<T>? interpolate;

  @override
  double get span => duration;

  @override
  void schedule(
    MotionEngine engine, {
    required double offset,
    required List<MotionHandle> handles,
    required List<_TimelineCall> calls,
  }) {
    final lerp = interpolate ?? property.interpolate;
    var previousPosition = 0.0;
    T? previousValue;

    for (var i = 0; i < frames.length; ++i) {
      final frame = frames[i];
      if (frame.position == 0.0) {
        previousValue = frame.value;
        previousPosition = 0.0;
        if (frames.length == 1) {
          _scheduleSegment(
            engine,
            handles,
            offset: offset,
            startPosition: 0.0,
            endPosition: 1.0,
            from: frame.value,
            to: frame.value,
            ease: Ease.linear,
            lerp: lerp,
          );
        }
        continue;
      }

      if (previousValue == null) {
        T? captured;
        _scheduleDynamicSegment(
          engine,
          handles,
          offset: offset,
          startPosition: 0.0,
          endPosition: frame.position,
          readStart: () => captured ??= property.read(),
          to: frame.value,
          ease: frame.ease ?? ease,
          lerp: lerp,
        );
      } else {
        _scheduleSegment(
          engine,
          handles,
          offset: offset,
          startPosition: previousPosition,
          endPosition: frame.position,
          from: previousValue,
          to: frame.value,
          ease: frame.ease ?? ease,
          lerp: lerp,
        );
      }
      previousPosition = frame.position;
      previousValue = frame.value;
    }

    if (previousValue != null && previousPosition < 1.0) {
      _scheduleSegment(
        engine,
        handles,
        offset: offset,
        startPosition: previousPosition,
        endPosition: 1.0,
        from: previousValue,
        to: previousValue,
        ease: Ease.linear,
        lerp: lerp,
      );
    }
  }

  void _scheduleSegment(
    MotionEngine engine,
    List<MotionHandle> handles, {
    required double offset,
    required double startPosition,
    required double endPosition,
    required T from,
    required T to,
    required EaseFunction ease,
    required MotionInterpolator<T> lerp,
  }) {
    _schedule(
      engine,
      handles,
      offset: offset,
      startPosition: startPosition,
      endPosition: endPosition,
      write: (t) => property.set(lerp(from, to, t)),
      ease: ease,
    );
  }

  void _scheduleDynamicSegment(
    MotionEngine engine,
    List<MotionHandle> handles, {
    required double offset,
    required double startPosition,
    required double endPosition,
    required T Function() readStart,
    required T to,
    required EaseFunction ease,
    required MotionInterpolator<T> lerp,
  }) {
    _schedule(
      engine,
      handles,
      offset: offset,
      startPosition: startPosition,
      endPosition: endPosition,
      write: (t) => property.set(lerp(readStart(), to, t)),
      ease: ease,
    );
  }

  void _schedule(
    MotionEngine engine,
    List<MotionHandle> handles, {
    required double offset,
    required double startPosition,
    required double endPosition,
    required void Function(double t) write,
    required EaseFunction ease,
  }) {
    final descriptor = DoubleMotionProperty(
      read: () => 0.0,
      write: write,
      from: 0.0,
      to: 1.0,
      property: property.motionKey,
    );
    final spec = _ResolvedMotionSpec(
      duration: (endPosition - startPosition) * duration,
      delay: 0.0,
      repeat: 0,
      repeatDelay: 0.0,
      yoyo: false,
      ease: ease,
      overwrite: Overwrite.auto,
    );
    _scheduleTimelineProperties(
      engine,
      handles,
      [descriptor],
      owner: property.motionOwner,
      offset: offset + startPosition * duration,
      spec: spec,
    );
  }
}

/// Parallel retained composition used by typed facade keyframe builders.
final class _ParallelMotionClip implements MotionClip {
  _ParallelMotionClip(Iterable<MotionClip> clips) : clips = clips.toList(growable: false);

  final List<MotionClip> clips;

  @override
  _BoundMotionClip _bind(MotionTimeline timeline) => _BoundParallelMotionClip(
    clips.map((clip) => clip._bind(timeline)).toList(growable: false),
  );
}

final class _BoundParallelMotionClip implements _BoundMotionClip {
  const _BoundParallelMotionClip(this.clips);

  final List<_BoundMotionClip> clips;

  @override
  double get span {
    var result = 0.0;
    for (final clip in clips) {
      if (clip.span > result) result = clip.span;
    }
    return result;
  }

  @override
  void schedule(
    MotionEngine engine, {
    required double offset,
    required List<MotionHandle> handles,
    required List<_TimelineCall> calls,
  }) {
    for (final clip in clips) {
      clip.schedule(engine, offset: offset, handles: handles, calls: calls);
    }
  }
}

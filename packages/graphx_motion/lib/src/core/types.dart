part of '../../motion.dart';

/// How a new motion interacts with existing motion on the same owner.
enum Overwrite { none, auto, all }

/// Runtime family represented by a [MotionHandle].
enum MotionKind { tween, spring, damp, inertia }

/// Lifecycle state retained by a public [MotionHandle].
enum MotionStatus { idle, active, paused, completed, cancelled }

/// Why a motion stopped without completing naturally.
enum MotionCancelReason { cancelled, overwritten, ownerDisposed, engineDisposed }

/// Reusable duration-motion defaults.
///
/// Null fields mean "inherit". A host such as `stage.motion` can provide a
/// cascading [MotionSpec], a call may provide another spec, and explicit named
/// arguments win last. Specs are resolved once at setup; the runtime never
/// consults them while sampling.
final class MotionSpec {
  const MotionSpec({
    this.duration,
    this.delay,
    this.repeat,
    this.repeatDelay,
    this.yoyo,
    this.ease,
    this.overwrite,
  });

  final double? duration;
  final double? delay;
  final int? repeat;
  final double? repeatDelay;
  final bool? yoyo;
  final EaseFunction? ease;
  final Overwrite? overwrite;

  MotionSpec copyWith({
    double? duration,
    double? delay,
    int? repeat,
    double? repeatDelay,
    bool? yoyo,
    EaseFunction? ease,
    Overwrite? overwrite,
  }) => MotionSpec(
    duration: duration ?? this.duration,
    delay: delay ?? this.delay,
    repeat: repeat ?? this.repeat,
    repeatDelay: repeatDelay ?? this.repeatDelay,
    yoyo: yoyo ?? this.yoyo,
    ease: ease ?? this.ease,
    overwrite: overwrite ?? this.overwrite,
  );
}

const MotionSpec _builtinMotionSpec = MotionSpec(
  duration: 0.3,
  delay: 0.0,
  repeat: 0,
  repeatDelay: 0.0,
  yoyo: false,
  ease: Ease.quadOut,
  overwrite: Overwrite.auto,
);

final class _ResolvedMotionSpec {
  const _ResolvedMotionSpec({
    required this.duration,
    required this.delay,
    required this.repeat,
    required this.repeatDelay,
    required this.yoyo,
    required this.ease,
    required this.overwrite,
  });

  final double duration;
  final double delay;
  final int repeat;
  final double repeatDelay;
  final bool yoyo;
  final EaseFunction ease;
  final Overwrite overwrite;
}

_ResolvedMotionSpec _resolveMotionSpec({
  required MotionSpec defaults,
  MotionSpec? motion,
  double? duration,
  double? delay,
  int? repeat,
  double? repeatDelay,
  bool? yoyo,
  EaseFunction? ease,
  Overwrite? overwrite,
}) => _ResolvedMotionSpec(
  duration: duration ?? motion?.duration ?? defaults.duration ?? _builtinMotionSpec.duration!,
  delay: delay ?? motion?.delay ?? defaults.delay ?? _builtinMotionSpec.delay!,
  repeat: repeat ?? motion?.repeat ?? defaults.repeat ?? _builtinMotionSpec.repeat!,
  repeatDelay:
      repeatDelay ?? motion?.repeatDelay ?? defaults.repeatDelay ?? _builtinMotionSpec.repeatDelay!,
  yoyo: yoyo ?? motion?.yoyo ?? defaults.yoyo ?? _builtinMotionSpec.yoyo!,
  ease: ease ?? motion?.ease ?? defaults.ease ?? _builtinMotionSpec.ease!,
  overwrite: overwrite ?? motion?.overwrite ?? defaults.overwrite ?? _builtinMotionSpec.overwrite!,
);

/// Stable identity for one animatable property on an owner.
///
/// Property identity is deliberately separate from [MotionHandle.hook]:
/// properties drive overwrite semantics; hooks are user-facing lookup/group tags.
final class MotionPropertyKey {
  const MotionPropertyKey(this.debugName);

  final String debugName;

  @override
  bool operator ==(Object other) => other is MotionPropertyKey && other.debugName == debugName;

  @override
  int get hashCode => debugName.hashCode;

  @override
  String toString() => 'MotionPropertyKey($debugName)';
}

typedef MotionSample = double Function(double value);
typedef MotionSnap = double Function(double value);

abstract final class MotionSnaps {
  static double round(double value) => value.roundToDouble();
  static double floor(double value) => value.floorToDouble();
  static double ceil(double value) => value.ceilToDouble();

  static MotionSnap step(double size) {
    if (!size.isFinite || size == 0.0) return (value) => value;
    return (value) => (value / size).round() * size;
  }
}

final class MotionClamp {
  const MotionClamp(this.min, this.max);

  final double min;
  final double max;

  double apply(double value) => value.clamp(min, max).toDouble();
}

/// One typed scalar property used by grouped duration/spring/damp motion.
final class DoubleMotionProperty {
  const DoubleMotionProperty({
    required this.read,
    required this.write,
    required this.to,
    this.property,
    this.from,
    this.shortest = false,
    this.period = math.pi * 2.0,
  });

  final double Function() read;
  final void Function(double value) write;
  final double to;
  final double? from;
  final MotionPropertyKey? property;
  final bool shortest;
  final double period;
}

/// One free-running inertia channel. Grouped channels may use independent
/// bounds/acceleration while sharing one public handle.
final class DoubleInertiaProperty {
  const DoubleInertiaProperty({
    required this.read,
    required this.write,
    required this.velocity,
    this.property,
    this.inertia = const Inertia(),
  });

  final double Function() read;
  final void Function(double value) write;
  final double velocity;
  final MotionPropertyKey? property;
  final Inertia inertia;
}

/// Stable control handle for one grouped motion runtime.
///
/// Duration handles implement [MotionPlayhead]. Physics handles intentionally
/// reject deterministic playhead APIs because they have no finite duration.
final class MotionHandle implements MotionPlayhead {
  MotionHandle._(this._engine, this._runtime, this._generation, this._kind)
    : _status = MotionStatus.idle,
      _terminalProgress = 0.0,
      _duration = _runtime?.duration ?? 0.0;

  MotionHandle._completed()
    : _engine = null,
      _runtime = null,
      _generation = 0,
      _kind = MotionKind.tween,
      _status = MotionStatus.completed,
      _terminalProgress = 1.0,
      _duration = 0.0;

  MotionEngine? _engine;
  _MotionRuntime? _runtime;
  final int _generation;
  final MotionKind _kind;
  final double _duration;
  MotionStatus _status;
  double _terminalProgress;

  MotionKind get kind => _kind;
  MotionStatus get status => _status;
  bool get isActive => _status == MotionStatus.active || _status == MotionStatus.paused;
  bool get isPaused => _status == MotionStatus.paused;
  bool get isCompleted => _status == MotionStatus.completed;
  bool get isCancelled => _status == MotionStatus.cancelled;
  bool get isPhysics => _kind != MotionKind.tween;

  Object? get owner => _liveRuntime?.owner;
  Object? get hook => _liveRuntime?.hook;

  @override
  MotionEngine get _playheadEngine {
    final engine = _engine;
    if (engine == null) {
      throw StateError('This MotionHandle no longer owns a live runtime.');
    }
    return engine;
  }

  @override
  double get duration {
    _checkDurationPlayhead();
    return _liveRuntime?.duration ?? _duration;
  }

  @override
  double get time {
    _checkDurationPlayhead();
    final runtime = _liveRuntime;
    return runtime?.cycleElapsed ?? _duration * _terminalProgress;
  }

  @override
  set time(double value) => seekTime(value);

  /// Normalized 0..1 progress for the current duration cycle only.
  @override
  double get progress {
    _checkDurationPlayhead();
    return _liveRuntime?.progress ?? _terminalProgress;
  }

  @override
  set progress(double value) => seek(value);

  /// Silently seeks the current duration cycle to normalized [value].
  @override
  void seek(double value) {
    _checkDurationPlayhead();
    if (!value.isFinite) {
      throw ArgumentError.value(value, 'progress', 'Must be finite.');
    }
    final runtime = _liveRuntime;
    if (runtime == null) return;
    _engine?._seekRuntimeSilent(runtime, value);
  }

  /// Silently seeks the current duration cycle in seconds.
  @override
  void seekTime(double value) {
    _checkDurationPlayhead();
    if (!value.isFinite) {
      throw ArgumentError.value(value, 'time', 'Must be finite.');
    }
    final d = duration;
    seek(d <= 0.0 ? 1.0 : value / d);
  }

  /// Reverses a live duration tween from its current visual position.
  @override
  void reverse() {
    _checkDurationPlayhead();
    final runtime = _liveRuntime;
    if (runtime == null) return;
    _engine?._reverseRuntime(runtime);
  }

  @override
  void _pauseForDrive() => pause();

  @override
  void _driveProgress(double value) {
    _checkDurationPlayhead();
    final runtime = _liveRuntime;
    if (runtime == null) return;
    _engine?._seekRuntime(runtime, value);
  }

  @override
  void _driveTime(double value) {
    final d = duration;
    _driveProgress(d <= 0.0 ? 1.0 : value / d);
  }

  /// Velocity for a live single-channel physics handle, otherwise null.
  double? get velocity {
    final runtime = _liveRuntime;
    if (runtime == null || runtime.tracks.length != 1) return null;
    return runtime.tracks.first.velocity;
  }

  double? velocityFor(MotionPropertyKey property) {
    final runtime = _liveRuntime;
    if (runtime == null) return null;
    for (var i = 0; i < runtime.tracks.length; ++i) {
      final track = runtime.tracks[i];
      if (track.property == property) return track.velocity;
    }
    return null;
  }

  _MotionRuntime? get _liveRuntime {
    final runtime = _runtime;
    if (runtime == null || runtime.generation != _generation) return null;
    if (!identical(runtime.handle, this)) return null;
    return runtime;
  }

  void pause() {
    final runtime = _liveRuntime;
    if (runtime != null) _engine?._pauseRuntime(runtime);
  }

  void resume() {
    final runtime = _liveRuntime;
    if (runtime != null) _engine?._resumeRuntime(runtime);
  }

  /// With [complete], tween/spring/damp tracks jump to their terminal target;
  /// inertia stops at its current value.
  void cancel({bool complete = false}) {
    final runtime = _liveRuntime;
    if (runtime == null) return;
    _engine?._cancelRuntime(
      runtime,
      complete: complete,
      reason: MotionCancelReason.cancelled,
    );
  }

  void dispose() => cancel();

  void _checkDurationPlayhead() {
    if (isPhysics) {
      throw UnsupportedError(
        'Deterministic playhead control is duration-tween only; physics motion has no finite playhead.',
      );
    }
  }

  void _markActive() => _status = MotionStatus.active;
  void _markPaused() => _status = MotionStatus.paused;

  void _markCompleted(double progress) {
    _terminalProgress = progress;
    _status = MotionStatus.completed;
    _runtime = null;
    _engine = null;
  }

  void _markCancelled(double progress) {
    _terminalProgress = progress;
    _status = MotionStatus.cancelled;
    _runtime = null;
    _engine = null;
  }
}

double _resolveCircularEnd(
  double start,
  double end,
  bool shortest,
  double period,
) {
  if (!shortest || !period.isFinite || period <= 0.0) return end;
  var delta = (end - start) % period;
  final half = period * 0.5;
  if (delta > half) delta -= period;
  if (delta < -half) delta += period;
  return start + delta;
}

double _postProcess(
  double value,
  MotionSample? sample,
  MotionSnap? snap,
  MotionClamp? clamp,
) {
  var result = value;
  if (sample != null) result = sample(result);
  if (snap != null) result = snap(result);
  if (clamp != null) result = clamp.apply(result);
  return result;
}

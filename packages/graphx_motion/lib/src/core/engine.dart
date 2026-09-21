part of '../../motion.dart';

final class _DoubleTrack {
  MotionPropertyKey? property;
  late void Function(double value) write;
  double start = 0.0;
  double end = 0.0;
  double value = 0.0;
  double velocity = 0.0;
  MotionPhysics? physics;
  MotionSample? sample;
  MotionSnap? snap;
  MotionClamp? clamp;
  int sampleToken = 0;
  bool physicsAlive = false;
  bool inheritedVelocity = false;

  void applyDuration(double t) {
    final next = start + (end - start) * t;
    write(_postProcess(next, sample, snap, clamp));
  }

  void writePhysics() => write(_postProcess(value, sample, snap, clamp));

  void reset() {
    property = null;
    start = 0.0;
    end = 0.0;
    value = 0.0;
    velocity = 0.0;
    physics = null;
    sample = null;
    snap = null;
    clamp = null;
    sampleToken = 0;
    physicsAlive = false;
    inheritedVelocity = false;
  }
}

final class _MotionRuntime {
  final List<_DoubleTrack> tracks = <_DoubleTrack>[];

  Object? owner;
  Object? hook;
  MotionKind kind = MotionKind.tween;
  EaseFunction ease = Ease.quadOut;
  double duration = 0.3;
  double delay = 0.0;
  double delayElapsed = 0.0;
  double cycleElapsed = 0.0;
  int repeat = 0;
  double repeatDelay = 0.0;
  double repeatDelayElapsed = 0.0;
  int iteration = 0;
  bool yoyo = false;
  bool forward = true;
  bool inheritVelocity = false;
  bool active = false;
  bool paused = false;
  bool started = false;
  bool terminal = false;
  int activeIndex = -1;
  int generation = 0;

  MotionHandle? handle;
  void Function()? onStart;
  void Function()? onUpdate;
  void Function(int iteration)? onRepeat;
  void Function()? onComplete;
  void Function()? onSettled;
  void Function(MotionCancelReason reason)? onCancel;

  bool get isPhysics => kind != MotionKind.tween;

  double get progress {
    if (duration <= 0.0) return started ? 1.0 : 0.0;
    return (cycleElapsed / duration).clamp(0.0, 1.0).toDouble();
  }

  void reset() {
    owner = null;
    hook = null;
    kind = MotionKind.tween;
    ease = Ease.quadOut;
    duration = 0.3;
    delay = 0.0;
    delayElapsed = 0.0;
    cycleElapsed = 0.0;
    repeat = 0;
    repeatDelay = 0.0;
    repeatDelayElapsed = 0.0;
    iteration = 0;
    yoyo = false;
    forward = true;
    inheritVelocity = false;
    active = false;
    paused = false;
    started = false;
    terminal = false;
    activeIndex = -1;
    handle = null;
    onStart = null;
    onUpdate = null;
    onRepeat = null;
    onComplete = null;
    onSettled = null;
    onCancel = null;
  }
}

/// Generic allocation-aware duration/physics scheduler.
///
/// The engine has no GraphX, Flutter, rendering, or widget dependency. A host
/// supplies ticks through [tick] and uses [onWake]/[onIdle] for demand gating.
final class MotionEngine {
  final List<_MotionRuntime?> _active = <_MotionRuntime?>[];
  final List<_MotionRuntime> _runtimePool = <_MotionRuntime>[];
  final List<_DoubleTrack> _trackPool = <_DoubleTrack>[];
  final Map<Object, Set<_MotionRuntime>> _byOwner = <Object, Set<_MotionRuntime>>{};

  static const int _maxRuntimePool = 128;
  static const int _maxTrackPool = 512;

  int _activeCount = 0;
  int _runningCount = 0;
  int _sampleSequence = 0;
  int _demandBatchDepth = 0;
  bool _disposed = false;
  double _timeScale = 1.0;

  double get timeScale => _timeScale;
  set timeScale(double value) {
    if (!value.isFinite || value < 0.0) {
      throw ArgumentError.value(value, 'timeScale', 'Must be finite and >= 0.');
    }
    if (_timeScale == value) return;
    final wasUpdating = wantsUpdate;
    _timeScale = value;
    _notifyDemandTransition(wasUpdating);
  }

  /// Host hitch clamp before [timeScale]. Set to infinity to disable.
  double maxDelta = 1.0 / 15.0;

  /// Preferred collision subdivision for bounded inertia only.
  double physicsStep = 1.0 / 120.0;

  /// Maximum bounded-inertia collision subdivisions per host tick.
  int maxPhysicsSteps = 8;

  void Function()? onWake;
  void Function()? onIdle;
  void Function(Object owner)? onOwnerActivated;
  void Function(Object owner)? onOwnerIdle;
  bool Function(Object owner)? isOwnerDisposed;

  int get activeCount => _activeCount;
  int get runningCount => _runningCount;
  int get pooledRuntimeCount => _runtimePool.length;
  int get pooledTrackCount => _trackPool.length;
  bool get isDisposed => _disposed;
  bool get wantsUpdate => !_disposed && _runningCount != 0 && _timeScale > 0.0;

  MotionHandle toDouble(
    double Function() read,
    void Function(double value) write,
    double to, {
    double duration = 0.3,
    double? from,
    EaseFunction ease = Ease.quadOut,
    double delay = 0.0,
    int repeat = 0,
    double repeatDelay = 0.0,
    bool yoyo = false,
    Overwrite overwrite = Overwrite.auto,
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
    _checkAlive();
    _validateTiming(duration, delay, repeat, repeatDelay);
    if (overwrite == Overwrite.all && owner == null) {
      throw ArgumentError('Overwrite.all requires an owner.');
    }

    final runtime = _acquireRuntime();
    _configureRuntime(
      runtime,
      owner: owner,
      hook: hook,
      duration: duration,
      ease: ease,
      delay: delay,
      repeat: repeat,
      repeatDelay: repeatDelay,
      yoyo: yoyo,
      onStart: onStart,
      onUpdate: onUpdate,
      onRepeat: onRepeat,
      onComplete: onComplete,
      onSettled: null,
      onCancel: onCancel,
    );

    final start = from ?? read();
    final track = _acquireTrack();
    track.property = property;
    track.write = write;
    track.start = start;
    track.end = _resolveCircularEnd(start, to, shortest, period);
    track.value = start;
    track.sample = sample;
    track.snap = snap;
    track.clamp = clamp;
    runtime.tracks.add(track);

    final handle = _bind(runtime);
    _start(runtime, overwrite);
    return handle;
  }

  MotionHandle byDouble(
    double Function() read,
    void Function(double value) write,
    double delta, {
    double duration = 0.3,
    EaseFunction ease = Ease.quadOut,
    double delay = 0.0,
    int repeat = 0,
    double repeatDelay = 0.0,
    bool yoyo = false,
    Overwrite overwrite = Overwrite.auto,
    Object? owner,
    Object? hook,
    MotionPropertyKey? property,
    MotionSample? sample,
    MotionSnap? snap,
    MotionClamp? clamp,
    void Function()? onStart,
    void Function()? onUpdate,
    void Function(int iteration)? onRepeat,
    void Function()? onComplete,
    void Function(MotionCancelReason reason)? onCancel,
  }) {
    final start = read();
    return toDouble(
      read,
      write,
      start + delta,
      from: start,
      duration: duration,
      ease: ease,
      delay: delay,
      repeat: repeat,
      repeatDelay: repeatDelay,
      yoyo: yoyo,
      overwrite: overwrite,
      owner: owner,
      hook: hook,
      property: property,
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

  MotionHandle toProperties(
    Iterable<DoubleMotionProperty> properties, {
    Object? owner,
    Object? hook,
    double duration = 0.3,
    EaseFunction ease = Ease.quadOut,
    double delay = 0.0,
    int repeat = 0,
    double repeatDelay = 0.0,
    bool yoyo = false,
    Overwrite overwrite = Overwrite.auto,
    MotionSample? sample,
    MotionSnap? snap,
    MotionClamp? clamp,
    void Function()? onStart,
    void Function()? onUpdate,
    void Function(int iteration)? onRepeat,
    void Function()? onComplete,
    void Function(MotionCancelReason reason)? onCancel,
  }) {
    _checkAlive();
    _validateTiming(duration, delay, repeat, repeatDelay);
    if (overwrite == Overwrite.all && owner == null) {
      throw ArgumentError('Overwrite.all requires an owner.');
    }

    final runtime = _acquireRuntime();
    _configureRuntime(
      runtime,
      owner: owner,
      hook: hook,
      duration: duration,
      ease: ease,
      delay: delay,
      repeat: repeat,
      repeatDelay: repeatDelay,
      yoyo: yoyo,
      onStart: onStart,
      onUpdate: onUpdate,
      onRepeat: onRepeat,
      onComplete: onComplete,
      onSettled: null,
      onCancel: onCancel,
    );

    for (final descriptor in properties) {
      final start = descriptor.from ?? descriptor.read();
      final track = _acquireTrack();
      track.property = descriptor.property;
      track.write = descriptor.write;
      track.start = start;
      track.end = _resolveCircularEnd(
        start,
        descriptor.to,
        descriptor.shortest,
        descriptor.period,
      );
      track.value = start;
      track.sample = sample;
      track.snap = snap;
      track.clamp = clamp;
      runtime.tracks.add(track);
    }

    if (runtime.tracks.isEmpty) {
      _releaseRuntime(runtime);
      onComplete?.call();
      return MotionHandle._completed();
    }

    final handle = _bind(runtime);
    _start(runtime, overwrite);
    return handle;
  }

  MotionHandle? find({required Object owner, required Object hook}) {
    final runtimes = _byOwner[owner];
    if (runtimes == null) return null;
    MotionHandle? result;
    for (final runtime in runtimes) {
      if (!runtime.terminal && runtime.hook == hook) result = runtime.handle;
    }
    return result;
  }

  bool has({Object? owner, Object? hook, MotionPropertyKey? property}) =>
      count(owner: owner, hook: hook, property: property) != 0;

  int count({Object? owner, Object? hook, MotionPropertyKey? property}) {
    var result = 0;
    final candidates = owner == null ? null : _byOwner[owner];
    if (candidates != null) {
      for (final runtime in candidates) {
        if (_matches(runtime, hook: hook, property: property)) result++;
      }
      return result;
    }
    for (var i = 0; i < _active.length; i++) {
      final runtime = _active[i];
      if (runtime != null && _matches(runtime, hook: hook, property: property)) {
        result++;
      }
    }
    return result;
  }

  /// Terminates every live runtime owned by [owner] because the host owner
  /// crossed its disposal boundary.
  ///
  /// Hosts with explicit lifecycle notifications should call this immediately;
  /// [isOwnerDisposed] remains the defensive tick-time fallback.
  void ownerDisposed(Object owner) {
    final runtimes = _byOwner[owner];
    if (runtimes == null || runtimes.isEmpty) return;
    final snapshot = runtimes.toList(growable: false);
    for (final runtime in snapshot) {
      if (!runtime.active || runtime.terminal) continue;
      _cancelRuntime(
        runtime,
        complete: false,
        reason: MotionCancelReason.ownerDisposed,
      );
    }
  }

  void cancel({
    Object? owner,
    Object? hook,
    Set<MotionPropertyKey>? properties,
    bool complete = false,
  }) {
    if (owner == null && hook == null) return;
    for (var i = _active.length - 1; i >= 0; i--) {
      final runtime = _active[i];
      if (runtime == null) continue;
      if (owner != null && !identical(runtime.owner, owner)) continue;
      if (hook != null && runtime.hook != hook) continue;
      if (properties != null && !_hasAnyProperty(runtime, properties)) continue;
      _cancelRuntime(
        runtime,
        complete: complete,
        reason: MotionCancelReason.cancelled,
      );
    }
  }

  void cancelAll({bool complete = false}) {
    for (var i = _active.length - 1; i >= 0; i--) {
      final runtime = _active[i];
      if (runtime != null) {
        _cancelRuntime(
          runtime,
          complete: complete,
          reason: MotionCancelReason.cancelled,
        );
      }
    }
  }

  void pause({Object? owner, Object? hook}) =>
      _forEachMatch(owner: owner, hook: hook, action: _pauseRuntime);

  void resume({Object? owner, Object? hook}) =>
      _forEachMatch(owner: owner, hook: hook, action: _resumeRuntime);

  void tick(double rawDeltaSeconds) {
    if (!wantsUpdate) return;
    var dt = rawDeltaSeconds;
    if (!dt.isFinite || dt < 0.0) dt = 0.0;
    if (maxDelta.isFinite && maxDelta > 0.0 && dt > maxDelta) dt = maxDelta;
    dt *= _timeScale;

    final end = _active.length;
    for (var i = 0; i < end; i++) {
      final runtime = _active[i];
      if (runtime == null || runtime.paused || runtime.terminal) continue;
      _advance(runtime, dt);
    }
    _compactIfNeeded();
  }

  void _advance(_MotionRuntime runtime, double dt) {
    final generation = runtime.generation;
    final owner = runtime.owner;
    if (owner != null && (isOwnerDisposed?.call(owner) ?? false)) {
      _cancelRuntime(
        runtime,
        complete: false,
        reason: MotionCancelReason.ownerDisposed,
      );
      return;
    }
    if (!_isLive(runtime, generation)) return;

    var remaining = dt;
    if (runtime.delayElapsed < runtime.delay) {
      final needed = runtime.delay - runtime.delayElapsed;
      if (remaining < needed) {
        runtime.delayElapsed += remaining;
        return;
      }
      runtime.delayElapsed = runtime.delay;
      remaining -= needed;
    }

    if (!runtime.started) {
      runtime.started = true;
      runtime.onStart?.call();
      if (!_isLive(runtime, generation)) return;
    }

    if (runtime.isPhysics) {
      _advancePhysics(runtime, remaining, generation);
      return;
    }

    if (runtime.duration <= 0.0) {
      if (!_applyDurationRuntime(runtime, 1.0, generation)) return;
      _completeRuntime(runtime);
      return;
    }

    while (_isLive(runtime, generation)) {
      if (runtime.iteration > 0 && runtime.repeatDelayElapsed < runtime.repeatDelay) {
        final needed = runtime.repeatDelay - runtime.repeatDelayElapsed;
        if (remaining < needed) {
          runtime.repeatDelayElapsed += remaining;
          return;
        }
        runtime.repeatDelayElapsed = runtime.repeatDelay;
        remaining -= needed;
      }

      final needed = runtime.duration - runtime.cycleElapsed;
      if (remaining < needed) {
        runtime.cycleElapsed += remaining;
        _applyDurationRuntime(
          runtime,
          runtime.cycleElapsed / runtime.duration,
          generation,
        );
        return;
      }

      runtime.cycleElapsed = runtime.duration;
      if (!_applyDurationRuntime(runtime, 1.0, generation)) return;
      remaining -= needed;

      if (runtime.repeat < 0 || runtime.iteration < runtime.repeat) {
        runtime.iteration++;
        runtime.onRepeat?.call(runtime.iteration);
        if (!_isLive(runtime, generation)) return;
        runtime.cycleElapsed = 0.0;
        runtime.repeatDelayElapsed = 0.0;
        if (runtime.yoyo) runtime.forward = !runtime.forward;
        if (remaining <= 0.0) return;
        continue;
      }

      _completeRuntime(runtime);
      return;
    }
  }

  bool _applyDurationRuntime(
    _MotionRuntime runtime,
    double normalized,
    int generation,
  ) {
    if (!_isLive(runtime, generation)) return false;
    final directed = runtime.forward ? normalized : 1.0 - normalized;
    final eased = runtime.ease(directed.clamp(0.0, 1.0).toDouble());
    final token = ++_sampleSequence;

    var index = 0;
    while (index < runtime.tracks.length) {
      final track = runtime.tracks[index];
      if (track.sampleToken == token) {
        index++;
        continue;
      }
      track.sampleToken = token;
      track.applyDuration(eased);
      if (!_isLive(runtime, generation)) return false;
      if (index >= runtime.tracks.length || !identical(runtime.tracks[index], track)) {
        index = 0;
      } else {
        index++;
      }
    }

    runtime.onUpdate?.call();
    return _isLive(runtime, generation);
  }

  void _advancePhysics(_MotionRuntime runtime, double dt, int generation) {
    if (!_isLive(runtime, generation)) return;
    final token = ++_sampleSequence;
    var index = 0;

    while (index < runtime.tracks.length) {
      final track = runtime.tracks[index];
      if (track.sampleToken == token) {
        index++;
        continue;
      }
      track.sampleToken = token;
      final physics = track.physics!;
      track.physicsAlive = physics._step(
        track,
        dt,
        physicsStep: physicsStep,
        maxPhysicsSteps: maxPhysicsSteps,
      );
      track.writePhysics();
      if (!_isLive(runtime, generation)) return;
      if (index >= runtime.tracks.length || !identical(runtime.tracks[index], track)) {
        index = 0;
      } else {
        index++;
      }
    }

    runtime.onUpdate?.call();
    if (!_isLive(runtime, generation)) return;

    for (var i = 0; i < runtime.tracks.length; ++i) {
      if (runtime.tracks[i].physicsAlive) return;
    }
    _completeRuntime(runtime, settled: true);
  }

  void _seekRuntime(_MotionRuntime runtime, double value) {
    if (runtime.isPhysics) {
      throw UnsupportedError('Physics motion cannot seek.');
    }
    final generation = runtime.generation;
    if (!_isLive(runtime, generation)) return;
    final t = value.clamp(0.0, 1.0).toDouble();
    if (!runtime.started) {
      runtime.started = true;
      runtime.onStart?.call();
      if (!_isLive(runtime, generation)) return;
    }
    runtime.delayElapsed = runtime.delay;
    runtime.cycleElapsed = runtime.duration * t;
    runtime.repeatDelayElapsed = runtime.repeatDelay;
    _applyDurationRuntime(runtime, t, generation);
  }

  void _start(_MotionRuntime runtime, Overwrite overwrite) {
    final wasUpdating = wantsUpdate;
    _demandBatchDepth++;
    try {
      _applyOverwrite(runtime, overwrite);
      runtime.active = true;
      runtime.activeIndex = _active.length;
      _active.add(runtime);
      _activeCount++;
      _runningCount++;
      final owner = runtime.owner;
      var ownerActivated = false;
      if (owner != null) {
        final existing = _byOwner[owner];
        if (existing == null) {
          _byOwner[owner] = <_MotionRuntime>{runtime};
          ownerActivated = true;
        } else {
          existing.add(runtime);
        }
      }
      runtime.handle?._markActive();
      if (ownerActivated) onOwnerActivated?.call(owner!);
    } finally {
      _demandBatchDepth--;
    }
    _notifyDemandTransition(wasUpdating);
  }

  void _applyOverwrite(_MotionRuntime incoming, Overwrite overwrite) {
    if (overwrite == Overwrite.none || incoming.owner == null) return;

    for (var i = _active.length - 1; i >= 0; i--) {
      final existing = _active[i];
      if (existing == null || existing.terminal) continue;
      if (!identical(existing.owner, incoming.owner)) continue;

      if (overwrite == Overwrite.all) {
        _cancelRuntime(
          existing,
          complete: false,
          reason: MotionCancelReason.overwritten,
        );
        continue;
      }

      for (var j = existing.tracks.length - 1; j >= 0; j--) {
        final removed = existing.tracks[j];
        final property = removed.property;
        if (property == null) continue;
        final replacement = _trackForProperty(incoming, property);
        if (replacement == null) continue;
        if (incoming.inheritVelocity &&
            replacement.physics is Spring &&
            !replacement.inheritedVelocity) {
          replacement.velocity = removed.velocity;
          replacement.inheritedVelocity = true;
        }
        existing.tracks.removeAt(j);
        _releaseTrack(removed);
      }

      if (existing.tracks.isEmpty) {
        _cancelRuntime(
          existing,
          complete: false,
          reason: MotionCancelReason.overwritten,
        );
      }
    }
  }

  _DoubleTrack? _trackForProperty(
    _MotionRuntime runtime,
    MotionPropertyKey property,
  ) {
    for (var i = 0; i < runtime.tracks.length; ++i) {
      final track = runtime.tracks[i];
      if (track.property == property) return track;
    }
    return null;
  }

  bool _containsProperty(_MotionRuntime runtime, MotionPropertyKey property) =>
      _trackForProperty(runtime, property) != null;

  bool _hasAnyProperty(
    _MotionRuntime runtime,
    Set<MotionPropertyKey> properties,
  ) {
    for (var i = 0; i < runtime.tracks.length; i++) {
      final property = runtime.tracks[i].property;
      if (property != null && properties.contains(property)) return true;
    }
    return false;
  }

  bool _matches(
    _MotionRuntime runtime, {
    Object? hook,
    MotionPropertyKey? property,
  }) {
    if (runtime.terminal) return false;
    if (hook != null && runtime.hook != hook) return false;
    if (property != null && !_containsProperty(runtime, property)) return false;
    return true;
  }

  void _forEachMatch({
    Object? owner,
    Object? hook,
    required void Function(_MotionRuntime runtime) action,
  }) {
    if (owner == null && hook == null) return;
    final end = _active.length;
    for (var i = 0; i < end; i++) {
      final runtime = _active[i];
      if (runtime == null || runtime.terminal) continue;
      if (owner != null && !identical(runtime.owner, owner)) continue;
      if (hook != null && runtime.hook != hook) continue;
      action(runtime);
    }
  }

  void _pauseRuntime(_MotionRuntime runtime) {
    if (!runtime.active || runtime.paused || runtime.terminal) return;
    final wasUpdating = wantsUpdate;
    runtime.paused = true;
    _runningCount--;
    runtime.handle?._markPaused();
    _notifyDemandTransition(wasUpdating);
  }

  void _resumeRuntime(_MotionRuntime runtime) {
    if (!runtime.active || !runtime.paused || runtime.terminal) return;
    final wasUpdating = wantsUpdate;
    runtime.paused = false;
    _runningCount++;
    runtime.handle?._markActive();
    _notifyDemandTransition(wasUpdating);
  }

  void _cancelRuntime(
    _MotionRuntime runtime, {
    required bool complete,
    required MotionCancelReason reason,
  }) {
    if (!runtime.active || runtime.terminal) return;
    if (complete) {
      final generation = runtime.generation;
      if (runtime.isPhysics) {
        if (!_applyPhysicsTerminal(runtime, generation)) return;
      } else {
        final finalForward = !runtime.yoyo || runtime.repeat < 0 || runtime.repeat.isEven;
        runtime.forward = finalForward;
        if (!_applyDurationRuntime(runtime, 1.0, generation)) return;
      }
      _completeRuntime(runtime);
      return;
    }

    final callback = runtime.onCancel;
    final handle = runtime.handle;
    final progress = _handleProgress(runtime);
    _detach(runtime);
    handle?._markCancelled(progress);
    _releaseRuntime(runtime);
    callback?.call(reason);
  }

  bool _applyPhysicsTerminal(_MotionRuntime runtime, int generation) {
    final token = ++_sampleSequence;
    var index = 0;
    while (index < runtime.tracks.length) {
      final track = runtime.tracks[index];
      if (track.sampleToken == token) {
        index++;
        continue;
      }
      track.sampleToken = token;
      track.physics!._terminal(track);
      track.writePhysics();
      if (!_isLive(runtime, generation)) return false;
      if (index >= runtime.tracks.length || !identical(runtime.tracks[index], track)) {
        index = 0;
      } else {
        index++;
      }
    }
    runtime.onUpdate?.call();
    return _isLive(runtime, generation);
  }

  void _completeRuntime(_MotionRuntime runtime, {bool settled = false}) {
    if (!runtime.active || runtime.terminal) return;
    final callback = settled ? runtime.onSettled : runtime.onComplete;
    final handle = runtime.handle;
    runtime.terminal = true;
    _detach(runtime);
    handle?._markCompleted(1.0);
    _releaseRuntime(runtime);
    callback?.call();
  }

  double _handleProgress(_MotionRuntime runtime) => runtime.isPhysics ? 0.0 : runtime.progress;

  void _detach(_MotionRuntime runtime) {
    final wasUpdating = wantsUpdate;
    final index = runtime.activeIndex;
    if (index >= 0 && index < _active.length && identical(_active[index], runtime)) {
      _active[index] = null;
    }
    runtime.activeIndex = -1;
    if (runtime.active) {
      _activeCount--;
      if (!runtime.paused) _runningCount--;
    }
    runtime.active = false;

    final owner = runtime.owner;
    if (owner != null) {
      final set = _byOwner[owner];
      set?.remove(runtime);
      if (set != null && set.isEmpty) {
        _byOwner.remove(owner);
        onOwnerIdle?.call(owner);
      }
    }

    _notifyDemandTransition(wasUpdating);
  }

  bool _isLive(_MotionRuntime runtime, int generation) =>
      runtime.active &&
      !runtime.terminal &&
      runtime.generation == generation &&
      identical(runtime.handle?._runtime, runtime);

  void _notifyDemandTransition(bool wasUpdating) {
    if (_demandBatchDepth != 0) return;
    final updating = wantsUpdate;
    if (wasUpdating == updating) return;
    if (updating) {
      onWake?.call();
    } else {
      onIdle?.call();
    }
  }

  _MotionRuntime _acquireRuntime() {
    final runtime = _runtimePool.isEmpty ? _MotionRuntime() : _runtimePool.removeLast();
    runtime.generation++;
    return runtime;
  }

  _DoubleTrack _acquireTrack() => _trackPool.isEmpty ? _DoubleTrack() : _trackPool.removeLast();

  MotionHandle _bind(_MotionRuntime runtime) {
    final handle = MotionHandle._(
      this,
      runtime,
      runtime.generation,
      runtime.kind,
    );
    runtime.handle = handle;
    return handle;
  }

  void _configureRuntime(
    _MotionRuntime runtime, {
    required Object? owner,
    required Object? hook,
    required double duration,
    required EaseFunction ease,
    required double delay,
    required int repeat,
    required double repeatDelay,
    required bool yoyo,
    required void Function()? onStart,
    required void Function()? onUpdate,
    required void Function(int iteration)? onRepeat,
    required void Function()? onComplete,
    required void Function()? onSettled,
    required void Function(MotionCancelReason reason)? onCancel,
  }) {
    runtime.owner = owner;
    runtime.hook = hook;
    runtime.kind = MotionKind.tween;
    runtime.duration = duration;
    runtime.ease = ease;
    runtime.delay = delay;
    runtime.repeat = repeat;
    runtime.repeatDelay = repeatDelay;
    runtime.yoyo = yoyo;
    runtime.onStart = onStart;
    runtime.onUpdate = onUpdate;
    runtime.onRepeat = onRepeat;
    runtime.onComplete = onComplete;
    runtime.onSettled = onSettled;
    runtime.onCancel = onCancel;
  }

  void _releaseTrack(_DoubleTrack track) {
    track.reset();
    if (_trackPool.length < _maxTrackPool) _trackPool.add(track);
  }

  void _releaseRuntime(_MotionRuntime runtime) {
    while (runtime.tracks.isNotEmpty) {
      _releaseTrack(runtime.tracks.removeLast());
    }
    runtime.reset();
    if (!_disposed && _runtimePool.length < _maxRuntimePool) {
      _runtimePool.add(runtime);
    }
  }

  void _validateTiming(
    double duration,
    double delay,
    int repeat,
    double repeatDelay,
  ) {
    if (!duration.isFinite || duration < 0.0) {
      throw ArgumentError.value(duration, 'duration');
    }
    if (!delay.isFinite || delay < 0.0) {
      throw ArgumentError.value(delay, 'delay');
    }
    if (repeat < -1) throw ArgumentError.value(repeat, 'repeat');
    if (!repeatDelay.isFinite || repeatDelay < 0.0) {
      throw ArgumentError.value(repeatDelay, 'repeatDelay');
    }
    if (duration == 0.0 && repeat != 0) {
      throw ArgumentError('A zero-duration motion cannot repeat.');
    }
  }

  void _compactIfNeeded() {
    if (_active.length < 32 || _activeCount * 2 > _active.length) return;
    var write = 0;
    for (var read = 0; read < _active.length; read++) {
      final runtime = _active[read];
      if (runtime == null) continue;
      if (write != read) _active[write] = runtime;
      runtime.activeIndex = write++;
    }
    _active.length = write;
  }

  void _checkAlive() {
    if (_disposed) throw StateError('MotionEngine is disposed.');
  }

  void dispose() {
    if (_disposed) return;
    final wasUpdating = wantsUpdate;
    _disposed = true;
    for (var i = _active.length - 1; i >= 0; i--) {
      final runtime = _active[i];
      if (runtime == null) continue;
      final callback = runtime.onCancel;
      final handle = runtime.handle;
      final progress = _handleProgress(runtime);
      final index = runtime.activeIndex;
      if (index >= 0 && index < _active.length) _active[index] = null;
      runtime.active = false;
      runtime.activeIndex = -1;
      handle?._markCancelled(progress);
      _releaseRuntime(runtime);
      callback?.call(MotionCancelReason.engineDisposed);
    }
    _active.clear();
    _runtimePool.clear();
    _trackPool.clear();
    _byOwner.clear();
    _activeCount = 0;
    _runningCount = 0;
    if (wasUpdating) onIdle?.call();
    onWake = null;
    onIdle = null;
    onOwnerActivated = null;
    onOwnerIdle = null;
    isOwnerDisposed = null;
  }
}

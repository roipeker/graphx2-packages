part of '../../motion.dart';

/// Deterministic retained orchestration over normal Motion runtimes.
///
/// A timeline is itself a [MotionClip], so timelines may be nested arbitrarily.
/// The root owns one active playhead clock. Leaf runtimes remain ordinary Motion
/// runtimes for overwrite/ownership identity, but are paused and sampled from
/// the root playhead so seek/reverse/scrub are deterministic.
final class MotionTimeline implements MotionClip, MotionPlayhead {
  MotionTimeline._(
    this.engine, {
    MotionSpec? defaults,
    this.onStart,
    this.onComplete,
    this.onCancel,
  }) : defaults = defaults ?? const MotionSpec();

  final MotionEngine engine;
  final MotionSpec defaults;
  final void Function()? onStart;
  final void Function()? onComplete;
  final void Function()? onCancel;

  final List<_TimelineClipEntry> _entries = <_TimelineClipEntry>[];
  final List<MotionHandle> _handles = <MotionHandle>[];
  final List<_TimelineCall> _calls = <_TimelineCall>[];
  final List<_TimelineCall> _activeCalls = <_TimelineCall>[];
  final Map<Object, double> _labels = <Object, double>{};

  MotionHandle? _clock;
  MotionTimeline? _parent;
  double _parentStart = 0.0;
  double _cursor = 0.0;
  double _duration = 0.0;
  double _time = 0.0;
  int _direction = 1;
  bool _prepared = false;
  bool _started = false;
  bool _completed = false;
  bool _completionNotified = false;
  bool _cancelled = false;
  bool _disposed = false;

  @override
  MotionEngine get _playheadEngine => engine;

  @override
  double get time {
    final parent = _parent;
    if (parent == null) return _time;
    return (parent.time - _parentStart).clamp(0.0, _duration).toDouble();
  }

  @override
  set time(double value) => seekTime(value);

  @override
  double get duration => _duration;

  @override
  double get progress => _duration <= 0.0
      ? (time >= _duration ? 1.0 : 0.0)
      : (time / _duration).clamp(0.0, 1.0).toDouble();

  @override
  set progress(double value) => seek(value);

  int get direction => _direction;
  bool get isReversed => _direction < 0;

  bool get isPlaying {
    final parent = _parent;
    if (parent != null) {
      return parent.isPlaying && time > 0.0 && time < _duration;
    }
    return _clock?.status == MotionStatus.active;
  }

  bool get isPaused => _parent?.isPaused ?? (_clock?.isPaused ?? false);
  bool get isCompleted => _parent == null ? _completed : time >= _duration;
  bool get isCancelled => _cancelled;
  bool get isDisposed => _disposed;
  bool get isNested => _parent != null;
  bool get isPrepared => _prepared;

  MotionTimeline label(Object name) {
    _checkMutable();
    _labels[name] = _cursor;
    return this;
  }

  MotionTimeline wait(double seconds) {
    _checkMutable();
    if (!seconds.isFinite || seconds < 0.0) {
      throw ArgumentError.value(seconds, 'seconds', 'Must be finite and >= 0.');
    }
    _cursor += seconds;
    if (_cursor > _duration) _duration = _cursor;
    return this;
  }

  MotionTimeline call(void Function() callback, {Object? at}) {
    _checkMutable();
    final start = _resolveAt(at, fallback: _cursor);
    _calls.add(_TimelineCall(start, callback));
    if (start > _duration) _duration = start;
    return this;
  }

  /// Universal composition primitive.
  MotionTimeline add(MotionClip clip, {Object? at}) {
    _checkMutable();
    if (identical(clip, this)) {
      throw ArgumentError('A MotionTimeline cannot contain itself.');
    }
    if (clip is MotionTimeline) _adoptTimeline(clip);
    final bound = clip._bind(this);
    if (bound.span <= 0.0 && clip is! MotionTimeline) return this;
    final start = _resolveAt(at, fallback: _cursor);
    if (clip is MotionTimeline) clip._parentStart = start;
    _entries.add(_TimelineClipEntry(start, bound));
    _advanceCursor(start, bound.span);
    return this;
  }

  MotionTimeline to<T>(
    MotionProperty<T> property,
    T target, {
    Object? at,
    MotionSpec? motion,
    MotionInterpolator<T>? interpolate,
    double? duration,
    EaseFunction? ease,
    double? delay,
    int? repeat,
    double? repeatDelay,
    bool? yoyo,
    Overwrite? overwrite,
  }) => add(
    MotionClip.property<T>(
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
    ),
    at: at,
  );

  MotionTimeline toMany(
    Iterable<MotionTarget> targets, {
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
    MotionClip.targets(
      targets,
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

  /// Starts/resumes forward playback from the current playhead position.
  MotionTimeline play() {
    _checkAlive();
    _checkRootControl('play');
    _direction = 1;
    if (_duration <= 0.0) {
      _time = 0.0;
      if (!_started) {
        _started = true;
        onStart?.call();
      }
      _finish();
      return this;
    }
    if (_time >= _duration) {
      _sampleAt(0.0, events: false);
    }
    if (!_started) {
      _started = true;
      _cancelled = false;
      onStart?.call();
    }
    _prepare();
    _sampleLeaves(_time);
    if (_time == 0.0) _fireCalls(0.0, 0.0);
    _startClock();
    return this;
  }

  MotionTimeline pause() {
    _checkRootControl('pause');
    _clock?.pause();
    return this;
  }

  MotionTimeline resume() {
    _checkRootControl('resume');
    if (_clock != null && _clock!.isPaused) {
      _clock!.resume();
    } else if (!_completed && !_cancelled) {
      _prepare();
      _startClock();
    }
    return this;
  }

  /// Reverses autonomous playback from the exact current sample.
  @override
  void reverse() {
    _checkAlive();
    _checkRootControl('reverse');
    _prepare();
    final wasPaused = isPaused;
    _direction = -_direction;
    if (_time < _duration) {
      _completed = false;
      _completionNotified = false;
    }
    _cancelClock();
    if ((_direction < 0 && _time <= 0.0) || (_direction > 0 && _time >= _duration)) {
      return;
    }
    _startClock();
    if (wasPaused) _clock?.pause();
  }

  /// Silently samples the normalized playhead.
  @override
  void seek(double value) {
    if (!value.isFinite) {
      throw ArgumentError.value(value, 'progress', 'Must be finite.');
    }
    seekTime(_duration * value.clamp(0.0, 1.0).toDouble());
  }

  /// Silently samples the playhead in seconds.
  @override
  void seekTime(double value) {
    _checkAlive();
    _checkRootControl('seek');
    if (!value.isFinite) {
      throw ArgumentError.value(value, 'time', 'Must be finite.');
    }
    final wasPlaying = isPlaying;
    final wasPaused = isPaused;
    _cancelClock();
    _sampleAt(value, events: false);
    if (wasPlaying || wasPaused) {
      _startClock();
      if (wasPaused) _clock?.pause();
    }
  }

  MotionTimeline restart() {
    _checkAlive();
    _checkRootControl('restart');
    _cancelPrepared();
    _time = 0.0;
    _direction = 1;
    _started = false;
    _completed = false;
    _completionNotified = false;
    _cancelled = false;
    _resetTreeState();
    return play();
  }

  MotionTimeline cancel() {
    _checkRootControl('cancel');
    if (_cancelled) return this;
    _cancelInternal();
    return this;
  }

  @override
  void _pauseForDrive() {
    _checkRootControl('drive');
    _prepare();
    _cancelClock();
  }

  @override
  void _driveProgress(double value) => _driveTime(_duration * value.clamp(0.0, 1.0).toDouble());

  @override
  void _driveTime(double value) {
    _checkAlive();
    _checkRootControl('drive');
    _prepare();
    _sampleAt(value, events: true);
  }

  void dispose() {
    if (_disposed) return;
    if (_parent == null) _cancelPrepared();
    _disposed = true;
    _entries.clear();
    _calls.clear();
    _activeCalls.clear();
    _labels.clear();
  }

  @override
  _BoundMotionClip _bind(MotionTimeline timeline) => _BoundTimelineClip(this);

  /// Prepares retained leaves and resolves every leaf's start state at its exact
  /// local start time. The process is silent and restores the timeline baseline
  /// before returning, so arbitrary first seek is independent of destination.
  void _prepare() {
    if (_prepared) return;
    _activeCalls.clear();
    _collectCalls(0.0, _activeCalls, includeOwnLifecycle: false);
    for (final entry in _entries) {
      entry.schedule(
        engine,
        offset: 0.0,
        handles: _handles,
        calls: _activeCalls,
      );
    }

    final handleOrder = <MotionHandle, int>{};
    for (var i = 0; i < _handles.length; ++i) {
      handleOrder[_handles[i]] = i;
    }
    _handles.sort((a, b) {
      final cmp = (a._liveRuntime?.delay ?? 0.0).compareTo(b._liveRuntime?.delay ?? 0.0);
      return cmp != 0 ? cmp : handleOrder[a]!.compareTo(handleOrder[b]!);
    });

    final callOrder = <_TimelineCall, int>{};
    for (var i = 0; i < _activeCalls.length; ++i) {
      callOrder[_activeCalls[i]] = i;
    }
    _activeCalls.sort((a, b) {
      final cmp = a.time.compareTo(b.time);
      return cmp != 0 ? cmp : callOrder[a]!.compareTo(callOrder[b]!);
    });

    _prepared = true;

    for (var i = 0; i < _handles.length; ++i) {
      engine._restoreTimelineBaseline(_handles, i);
      final start = _handles[i]._liveRuntime?.delay ?? 0.0;
      for (var j = 0; j < i; ++j) {
        engine._sampleTimelineHandle(
          _handles[j],
          start,
          applyOverwrite: false,
        );
      }
      engine._initializeTimelineHandle(_handles[i]);
    }

    engine._restoreTimelineBaseline(_handles);
    _syncCallState(_time);
  }

  void _startClock() {
    if (_duration <= 0.0) return;
    final target = _direction > 0 ? _duration : 0.0;
    final distance = (target - _time).abs();
    if (distance <= 0.0) return;
    _cancelClock();
    _clock = engine.toDouble(
      () => _time,
      (value) => _sampleAt(value, events: true),
      target,
      from: _time,
      duration: distance,
      ease: Ease.linear,
      overwrite: Overwrite.none,
      owner: this,
      property: const MotionPropertyKey('MotionTimeline.clock'),
      onComplete: () {
        _clock = null;
        if (_direction > 0) {
          _finish();
        } else {
          _time = 0.0;
          _completed = false;
          _completionNotified = false;
        }
      },
    );
  }

  void _sampleAt(double value, {required bool events}) {
    _prepare();
    final next = value.clamp(0.0, _duration).toDouble();
    final previous = _time;
    _sampleLeaves(next);
    _time = next;
    if (next < _duration) {
      _completed = false;
      _completionNotified = false;
    } else {
      _completed = _duration > 0.0;
    }
    if (events) {
      _fireCalls(previous, next);
      if (next >= _duration && previous < _duration) _finish();
    } else {
      _syncCallState(next);
    }
  }

  void _sampleLeaves(double absoluteTime) {
    engine._restoreTimelineBaseline(_handles);
    for (final handle in _handles) {
      engine._sampleTimelineHandle(handle, absoluteTime);
    }
  }

  void _adoptTimeline(MotionTimeline child) {
    if (!identical(child.engine, engine)) {
      throw ArgumentError('Nested MotionTimeline values must use the same MotionEngine.');
    }
    if (child._started || child._disposed) {
      throw StateError('Only an unplayed, live MotionTimeline can be nested.');
    }
    if (child._parent != null) {
      throw StateError('A MotionTimeline can have only one parent.');
    }
    MotionTimeline? cursor = this;
    while (cursor != null) {
      if (identical(cursor, child)) {
        throw ArgumentError('MotionTimeline nesting cannot contain a cycle.');
      }
      cursor = cursor._parent;
    }
    child._parent = this;
  }

  void _collectCalls(
    double offset,
    List<_TimelineCall> out, {
    required bool includeOwnLifecycle,
  }) {
    if (includeOwnLifecycle && onStart != null) {
      out.add(
        _TimelineCall(offset, () {
          _started = true;
          onStart?.call();
        }),
      );
    }
    for (final call in _calls) {
      out.add(_TimelineCall(offset + call.time, call.callback));
    }
    for (final entry in _entries) {
      entry.collectCalls(offset: offset, calls: out);
    }
    if (includeOwnLifecycle && onComplete != null) {
      out.add(
        _TimelineCall(offset + _duration, () {
          _completed = true;
          onComplete?.call();
        }),
      );
    }
  }

  void _scheduleNested(
    MotionEngine engine, {
    required double offset,
    required List<MotionHandle> handles,
    required List<_TimelineCall> calls,
  }) {
    for (final entry in _entries) {
      entry.schedule(engine, offset: offset, handles: handles, calls: calls);
    }
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
    final inherited = MotionSpec(
      duration: defaults.duration ?? engine.defaults.duration,
      delay: defaults.delay ?? engine.defaults.delay,
      repeat: defaults.repeat ?? engine.defaults.repeat,
      repeatDelay: defaults.repeatDelay ?? engine.defaults.repeatDelay,
      yoyo: defaults.yoyo ?? engine.defaults.yoyo,
      ease: defaults.ease ?? engine.defaults.ease,
      overwrite: defaults.overwrite ?? engine.defaults.overwrite,
    );
    return _resolveMotionSpec(
      defaults: inherited,
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

  void _advanceCursor(double start, double span) {
    final end = start + span;
    if (end > _duration) _duration = end;
    _cursor = math.max(_cursor, end);
  }

  double _resolveAt(Object? at, {required double fallback}) {
    if (at == null) return fallback;
    if (at is num) {
      final value = at.toDouble();
      if (!value.isFinite || value < 0.0) {
        throw ArgumentError.value(at, 'at', 'Must be finite and >= 0.');
      }
      return value;
    }
    final value = _labels[at];
    if (value == null) {
      throw ArgumentError.value(at, 'at', 'Unknown timeline label');
    }
    return value;
  }

  void _fireCalls(double previous, double current) {
    if (current >= previous) {
      for (final call in _activeCalls) {
        if (call.fired) continue;
        final crossed =
            (call.time == 0.0 && previous == 0.0) || (previous < call.time && current >= call.time);
        if (!crossed) continue;
        call.fired = true;
        call.callback();
      }
      return;
    }

    // Reverse traversal rewinds callback state without invoking callbacks.
    // A later forward traversal fires them again when crossed.
    for (final call in _activeCalls) {
      if (current < call.time && previous >= call.time) call.fired = false;
    }
  }

  void _syncCallState(double value) {
    for (final call in _activeCalls) {
      call.fired = value == 0.0 ? false : call.time <= value;
    }
  }

  void _finish() {
    if (_cancelled || _disposed || _completionNotified) return;
    _time = _duration;
    _completed = true;
    _completionNotified = true;
    onComplete?.call();
  }

  void _cancelInternal() {
    if (_cancelled) return;
    _cancelled = true;
    _cancelNested(this);
    _cancelPrepared();
    onCancel?.call();
  }

  static void _cancelNested(MotionTimeline timeline) {
    for (final entry in timeline._entries) {
      final child = entry.childTimeline;
      if (child == null) continue;
      if (!child._cancelled) {
        child._cancelled = true;
        child.onCancel?.call();
      }
      _cancelNested(child);
    }
  }

  void _cancelClock() {
    final clock = _clock;
    _clock = null;
    if (clock != null && clock.isActive) clock.cancel();
  }

  void _cancelPrepared() {
    _cancelClock();
    final handles = List<MotionHandle>.of(_handles);
    _handles.clear();
    for (final handle in handles) {
      if (handle.isActive) handle.cancel();
    }
    _prepared = false;
  }

  void _resetTreeState() {
    for (final call in _activeCalls) call.fired = false;
    for (final entry in _entries) {
      final child = entry.childTimeline;
      if (child == null) continue;
      child._started = false;
      child._completed = false;
      child._completionNotified = false;
      child._cancelled = false;
      child._resetTreeState();
    }
  }

  void _checkMutable() {
    _checkAlive();
    if (_parent != null) {
      throw StateError('Cannot modify a MotionTimeline after it is nested.');
    }
    if (_prepared || _started) {
      throw StateError('Cannot modify a MotionTimeline after playback/seek preparation.');
    }
  }

  void _checkRootControl(String operation) {
    if (_parent != null) {
      throw StateError(
        'Cannot $operation a nested MotionTimeline directly; control its root timeline.',
      );
    }
  }

  void _checkAlive() {
    if (_disposed) throw StateError('MotionTimeline is disposed.');
  }
}

extension MotionEngineTimelineExtension on MotionEngine {
  MotionTimeline timeline({
    MotionSpec? defaults,
    void Function()? onStart,
    void Function()? onComplete,
    void Function()? onCancel,
  }) => MotionTimeline._(
    this,
    defaults: defaults,
    onStart: onStart,
    onComplete: onComplete,
    onCancel: onCancel,
  );
}

final class _TimelineCall {
  _TimelineCall(this.time, this.callback);
  final double time;
  final void Function() callback;
  bool fired = false;
}

final class _TimelineClipEntry {
  const _TimelineClipEntry(this.start, this.clip);

  final double start;
  final _BoundMotionClip clip;

  MotionTimeline? get childTimeline =>
      clip is _BoundTimelineClip ? (clip as _BoundTimelineClip).timeline : null;

  void schedule(
    MotionEngine engine, {
    required double offset,
    required List<MotionHandle> handles,
    required List<_TimelineCall> calls,
  }) => clip.schedule(
    engine,
    offset: offset + start,
    handles: handles,
    calls: calls,
  );

  void collectCalls({
    required double offset,
    required List<_TimelineCall> calls,
  }) {
    final child = childTimeline;
    child?._collectCalls(offset + start, calls, includeOwnLifecycle: true);
  }
}

final class _BoundTimelineClip implements _BoundMotionClip {
  const _BoundTimelineClip(this.timeline);

  final MotionTimeline timeline;

  @override
  double get span => timeline.duration;

  @override
  void schedule(
    MotionEngine engine, {
    required double offset,
    required List<MotionHandle> handles,
    required List<_TimelineCall> calls,
  }) => timeline._scheduleNested(
    engine,
    offset: offset,
    handles: handles,
    calls: calls,
  );
}

void _validateTimelineSpec(_ResolvedMotionSpec spec) {
  _validateResolvedSpec(spec);
  if (spec.repeat < 0) {
    throw ArgumentError(
      'Timeline children cannot repeat forever because the timeline needs a '
      'finite duration. Use a finite repeat or loop the timeline externally.',
    );
  }
}

part of '../../motion.dart';

/// Shared deterministic playhead contract for finite duration motion.
///
/// [time] is expressed in seconds and [progress] is normalized to 0..1.
/// Direct setters/seek operations sample silently. Playback or a motion driving
/// the playhead uses the same state but emits normal traversal/update events.
abstract interface class MotionPlayhead {
  MotionEngine get _playheadEngine;

  double get time;
  set time(double value);

  double get duration;

  double get progress;
  set progress(double value);

  void seek(double progress);
  void seekTime(double seconds);
  void reverse();

  void _pauseForDrive();
  void _driveProgress(double value);
  void _driveTime(double value);
}

final Expando<MotionPlayheadMotion> _motionByPlayhead = Expando<MotionPlayheadMotion>(
  'graphx.motion.playhead',
);

extension MotionPlayheadExtension on MotionPlayhead {
  /// Animates this playhead using the same MotionEngine as ordinary values.
  MotionPlayheadMotion get motion => _motionByPlayhead[this] ??= MotionPlayheadMotion._(this);
}

/// Motion facade for any deterministic playhead.
final class MotionPlayheadMotion {
  MotionPlayheadMotion._(this.playhead)
    : _progress = MotionProperty<double>(
        owner: playhead,
        property: const MotionPropertyKey('MotionPlayhead.progress'),
        read: () => playhead.progress,
        write: playhead._driveProgress,
      ),
      _time = MotionProperty<double>(
        owner: playhead,
        property: const MotionPropertyKey('MotionPlayhead.time'),
        read: () => playhead.time,
        write: playhead._driveTime,
      );

  final MotionPlayhead playhead;
  final MotionProperty<double> _progress;
  final MotionProperty<double> _time;

  MotionHandle to({
    double? progress,
    double? time,
    MotionSpec? motion,
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
  }) {
    if (playhead is MotionHandle && (playhead as MotionHandle).isPhysics) {
      throw UnsupportedError(
        'Physics motion has no deterministic finite playhead to animate.',
      );
    }
    final property = _select(progress: progress, time: time);
    final target = progress ?? time!;
    playhead._pauseForDrive();
    return playhead._playheadEngine.to<double>(
      property,
      target,
      motion: motion,
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

  MotionProperty<double> _select({double? progress, double? time}) {
    if ((progress == null) == (time == null)) {
      throw ArgumentError('Specify exactly one of progress or time.');
    }
    if (progress != null) {
      if (!progress.isFinite) {
        throw ArgumentError.value(progress, 'progress', 'Must be finite.');
      }
      return _progress;
    }
    if (!time!.isFinite) {
      throw ArgumentError.value(time, 'time', 'Must be finite.');
    }
    return _time;
  }
}

final class _TimelineTrackSource {
  _TimelineTrackSource(this.descriptor);

  final DoubleMotionProperty descriptor;
  bool initialized = false;
}

final class _TimelineRuntimeState {
  _TimelineRuntimeState(this.sources, this.overwrite);

  final List<_TimelineTrackSource> sources;
  final Overwrite overwrite;
  bool overwriteApplied = false;
}

final Expando<_TimelineRuntimeState> _timelineRuntimeState = Expando<_TimelineRuntimeState>(
  'graphx.motion.timelineRuntime',
);

void _registerTimelineProperties(
  MotionHandle handle,
  Iterable<DoubleMotionProperty> descriptors,
  Overwrite overwrite,
) {
  _timelineRuntimeState[handle] = _TimelineRuntimeState(
    descriptors.map(_TimelineTrackSource.new).toList(growable: false),
    overwrite,
  );
}

extension _MotionEnginePlayheadSupport on MotionEngine {
  void _seekRuntimeSilent(_MotionRuntime runtime, double value) {
    if (runtime.isPhysics) {
      throw UnsupportedError('Physics motion cannot seek.');
    }
    if (!_isLive(runtime, runtime.generation)) return;
    final t = value.clamp(0.0, 1.0).toDouble();
    runtime.delayElapsed = runtime.delay;
    runtime.cycleElapsed = runtime.duration * t;
    runtime.repeatDelayElapsed = runtime.repeatDelay;
    _applyRuntimeSample(runtime, t, notifyUpdate: false);
  }

  void _applyRuntimeSample(
    _MotionRuntime runtime,
    double normalized, {
    required bool notifyUpdate,
    bool? forward,
  }) {
    if (!_isLive(runtime, runtime.generation)) return;
    final directed = (forward ?? runtime.forward) ? normalized : 1.0 - normalized;
    final eased = runtime.ease(directed.clamp(0.0, 1.0).toDouble());
    final token = ++_sampleSequence;
    for (var i = 0; i < runtime.tracks.length; ++i) {
      final track = runtime.tracks[i];
      if (track.sampleToken == token) continue;
      track.sampleToken = token;
      track.applyDuration(eased);
    }
    if (notifyUpdate) runtime.onUpdate?.call();
  }

  /// Samples one prepared Timeline leaf. Start values must already have been
  /// resolved by [_initializeTimelineHandle] at the leaf's local start time.
  void _sampleTimelineHandle(
    MotionHandle handle,
    double absoluteTime, {
    bool applyOverwrite = true,
  }) {
    final runtime = handle._liveRuntime;
    if (runtime == null || runtime.isPhysics) return;
    final state = _timelineRuntimeState[handle];
    final startTime = runtime.delay;

    if (absoluteTime < startTime) {
      if (state != null) state.overwriteApplied = false;
      return;
    }

    if (state != null && applyOverwrite && !state.overwriteApplied) {
      _applyTimelineOverwrite(runtime, state.overwrite);
      state.overwriteApplied = true;
      if (!_isLive(runtime, runtime.generation)) return;
    }

    final duration = runtime.duration;
    if (duration <= 0.0) {
      _applyRuntimeSample(runtime, 1.0, notifyUpdate: false, forward: true);
      return;
    }

    final elapsed = math.max(0.0, absoluteTime - startTime);
    final repeat = runtime.repeat < 0 ? 0 : runtime.repeat;
    final total = duration * (repeat + 1) + runtime.repeatDelay * repeat;

    var iteration = 0;
    var normalized = 0.0;
    if (elapsed >= total) {
      iteration = repeat;
      normalized = 1.0;
    } else {
      final cycleSpan = duration + runtime.repeatDelay;
      iteration = cycleSpan <= 0.0 ? 0 : math.min(repeat, (elapsed / cycleSpan).floor());
      final within = elapsed - iteration * cycleSpan;
      normalized = within >= duration ? 1.0 : within / duration;
    }

    final forward = !runtime.yoyo || iteration.isEven;
    runtime.started = true;
    runtime.iteration = iteration;
    runtime.forward = forward;
    runtime.delayElapsed = runtime.delay;
    runtime.cycleElapsed = duration * normalized;
    runtime.repeatDelayElapsed = normalized >= 1.0 ? runtime.repeatDelay : 0.0;
    _applyRuntimeSample(
      runtime,
      normalized,
      notifyUpdate: false,
      forward: forward,
    );
  }

  /// Resolves one retained leaf's `from` values at its actual local start.
  void _initializeTimelineHandle(MotionHandle handle) {
    final runtime = handle._liveRuntime;
    if (runtime == null) return;
    final state = _timelineRuntimeState[handle];
    if (state == null) return;
    _initializeTimelineTracks(runtime, state);
    _applyRuntimeSample(runtime, 0.0, notifyUpdate: false, forward: true);
  }

  void _initializeTimelineTracks(
    _MotionRuntime runtime,
    _TimelineRuntimeState state,
  ) {
    for (var i = 0; i < runtime.tracks.length; ++i) {
      final track = runtime.tracks[i];
      _TimelineTrackSource? source;
      final property = track.property;
      if (property != null) {
        for (final candidate in state.sources) {
          if (candidate.descriptor.property == property) {
            source = candidate;
            break;
          }
        }
      } else if (i < state.sources.length) {
        source = state.sources[i];
      }
      if (source == null || source.initialized) continue;
      final descriptor = source.descriptor;
      final start = descriptor.from ?? descriptor.read();
      track.start = start;
      track.end = _resolveCircularEnd(
        start,
        descriptor.to,
        descriptor.shortest,
        descriptor.period,
      );
      track.value = start;
      source.initialized = true;
    }
  }

  /// Restores the earliest surviving Timeline track for each owner/property.
  /// [end] limits restoration to a chronological prefix during start capture.
  void _restoreTimelineBaseline(List<MotionHandle> handles, [int? end]) {
    final owners = <Object, Set<MotionPropertyKey>>{};
    final limit = math.min(end ?? handles.length, handles.length);
    for (var h = 0; h < limit; ++h) {
      final runtime = handles[h]._liveRuntime;
      if (runtime == null) continue;
      final owner = runtime.owner;
      final seen = owner == null ? null : (owners[owner] ??= <MotionPropertyKey>{});
      for (final track in runtime.tracks) {
        final property = track.property;
        if (owner != null && property != null) {
          if (!seen!.add(property)) continue;
        }
        track.applyDuration(0.0);
      }
    }
  }

  void _applyTimelineOverwrite(_MotionRuntime incoming, Overwrite overwrite) {
    if (overwrite == Overwrite.none || incoming.owner == null) return;
    for (var i = _active.length - 1; i >= 0; --i) {
      final existing = _active[i];
      if (existing == null || existing.terminal || identical(existing, incoming)) {
        continue;
      }
      final existingHandle = existing.handle;
      if (existingHandle != null && _timelineRuntimeState[existingHandle] != null) {
        continue;
      }
      if (!identical(existing.owner, incoming.owner)) continue;

      if (overwrite == Overwrite.all) {
        _cancelRuntime(
          existing,
          complete: false,
          reason: MotionCancelReason.overwritten,
        );
        continue;
      }

      for (var j = existing.tracks.length - 1; j >= 0; --j) {
        final property = existing.tracks[j].property;
        if (property == null || !_containsProperty(incoming, property)) continue;
        final removed = existing.tracks.removeAt(j);
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
}

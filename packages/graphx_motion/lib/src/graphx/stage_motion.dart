import 'dart:async';

import 'package:graphx/graphx_extension.dart';
import 'package:graphx_motion/motion.dart';

final Expando<GraphXMotion> _motionByStage = Expando<GraphXMotion>('graphx.motion');

/// Stage-local bridge between GraphX's demand-driven update loop and the
/// generic [MotionEngine].
///
/// The bridge listens to `stage.signals.onUpdate` only while motion actually
/// needs ticks. Free-value motion does not repaint the stage unless [paint] is
/// requested or the supplied writer invalidates a GraphX object itself.
final class GraphXMotion {
  GraphXMotion._(this.stage) : engine = MotionEngine() {
    engine.onWake = _wake;
    engine.onIdle = _sleep;
    engine.onOwnerActivated = _ownerActivated;
    engine.onOwnerIdle = _ownerIdle;
    engine.isOwnerDisposed = _isOwnerDisposed;
    stage.signals.onDispose.add(dispose, key: this);
  }

  final GStage stage;
  final MotionEngine engine;

  GSignalSubscription? _updateSubscription;
  final Map<GNode, GSignalSubscription> _nodeOwnerSubscriptions =
      Map<GNode, GSignalSubscription>.identity();
  bool _sleepScheduled = false;
  bool _disposed = false;

  bool get isDisposed => _disposed;

  int get activeCount => engine.activeCount;
  int get runningCount => engine.runningCount;
  bool get wantsUpdate => engine.wantsUpdate;

  double get timeScale => engine.timeScale;
  set timeScale(double value) => engine.timeScale = value;

  /// Cascading defaults used by duration motion on this Stage.
  MotionSpec get defaults => engine.defaults;
  set defaults(MotionSpec value) => engine.defaults = value;

  MotionHandle tween(
    double from,
    double to, {
    required void Function(double value) onValue,
    MotionSpec? motion,
    double? duration,
    EaseFunction? ease,
    double? delay,
    int? repeat,
    double? repeatDelay,
    bool? yoyo,
    Object? owner,
    Object? hook,
    MotionSample? sample,
    MotionSnap? snap,
    MotionClamp? clamp,
    bool paint = false,
    void Function()? invalidate,
    void Function()? onStart,
    void Function()? onUpdate,
    void Function(int iteration)? onRepeat,
    void Function()? onComplete,
    void Function(MotionCancelReason reason)? onCancel,
  }) {
    return toDouble(
      () => from,
      onValue,
      to,
      from: from,
      motion: motion,
      duration: duration,
      ease: ease,
      delay: delay,
      repeat: repeat,
      repeatDelay: repeatDelay,
      yoyo: yoyo,
      owner: owner,
      hook: hook,
      sample: sample,
      snap: snap,
      clamp: clamp,
      paint: paint,
      invalidate: invalidate,
      onStart: onStart,
      onUpdate: onUpdate,
      onRepeat: onRepeat,
      onComplete: onComplete,
      onCancel: onCancel,
    );
  }

  MotionHandle toDouble(
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
    double period = 6.283185307179586,
    MotionSample? sample,
    MotionSnap? snap,
    MotionClamp? clamp,
    bool paint = false,
    void Function()? invalidate,
    void Function()? onStart,
    void Function()? onUpdate,
    void Function(int iteration)? onRepeat,
    void Function()? onComplete,
    void Function(MotionCancelReason reason)? onCancel,
  }) {
    _checkAlive();
    final writer = _writer(write, paint: paint, invalidate: invalidate);
    return engine.toConfiguredDouble(
      read,
      writer,
      to,
      from: from,
      motion: motion,
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

  MotionHandle fromDouble(
    double Function() read,
    void Function(double value) write,
    double from, {
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
    MotionSample? sample,
    MotionSnap? snap,
    MotionClamp? clamp,
    bool paint = false,
    void Function()? invalidate,
    void Function()? onStart,
    void Function()? onUpdate,
    void Function(int iteration)? onRepeat,
    void Function()? onComplete,
    void Function(MotionCancelReason reason)? onCancel,
  }) {
    final current = read();
    return toDouble(
      read,
      write,
      current,
      from: from,
      motion: motion,
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
      paint: paint,
      invalidate: invalidate,
      onStart: onStart,
      onUpdate: onUpdate,
      onRepeat: onRepeat,
      onComplete: onComplete,
      onCancel: onCancel,
    );
  }

  MotionHandle byDouble(
    double Function() read,
    void Function(double value) write,
    double delta, {
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
    MotionSample? sample,
    MotionSnap? snap,
    MotionClamp? clamp,
    bool paint = false,
    void Function()? invalidate,
    void Function()? onStart,
    void Function()? onUpdate,
    void Function(int iteration)? onRepeat,
    void Function()? onComplete,
    void Function(MotionCancelReason reason)? onCancel,
  }) {
    _checkAlive();
    final start = read();
    return toDouble(
      read,
      write,
      start + delta,
      from: start,
      motion: motion,
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
      paint: paint,
      invalidate: invalidate,
      onStart: onStart,
      onUpdate: onUpdate,
      onRepeat: onRepeat,
      onComplete: onComplete,
      onCancel: onCancel,
    );
  }

  MotionHandle? find({required Object owner, required Object hook}) =>
      engine.find(owner: owner, hook: hook);

  void cancel({
    Object? owner,
    Object? hook,
    Set<MotionPropertyKey>? properties,
    bool complete = false,
  }) {
    engine.cancel(
      owner: owner,
      hook: hook,
      properties: properties,
      complete: complete,
    );
  }

  void cancelAll({bool complete = false}) => engine.cancelAll(complete: complete);

  void pause({Object? owner, Object? hook}) => engine.pause(owner: owner, hook: hook);

  void resume({Object? owner, Object? hook}) => engine.resume(owner: owner, hook: hook);

  void Function(double value) _writer(
    void Function(double value) write, {
    required bool paint,
    required void Function()? invalidate,
  }) {
    if (!paint && invalidate == null) return write;
    return (value) {
      write(value);
      invalidate?.call();
      if (paint) stage.requestPaint();
    };
  }

  void _wake() {
    if (_disposed || stage.isDisposed) return;
    final current = _updateSubscription;
    if (current != null && current.isActive) return;
    _updateSubscription = stage.signals.onUpdate.add(_tick, key: this);
  }

  /// The engine can briefly reach zero active runtimes while synchronously
  /// replacing the last motion through overwrite. Only that zero-runtime case
  /// defers teardown; pause/timeScale sleep remain immediate.
  void _sleep() {
    if (_updateSubscription == null) return;
    if (engine.activeCount != 0) {
      _cancelUpdateSubscription();
      return;
    }
    if (_sleepScheduled) return;
    _sleepScheduled = true;
    scheduleMicrotask(() {
      _sleepScheduled = false;
      if (!_disposed && engine.wantsUpdate) return;
      _cancelUpdateSubscription();
    });
  }

  void _cancelUpdateSubscription() {
    final current = _updateSubscription;
    _updateSubscription = null;
    current?.cancel();
  }

  void _tick(double delta) => engine.tick(delta);

  void _ownerActivated(Object owner) {
    if (owner is! GNode) return;
    if (owner.isDisposed) {
      engine.ownerDisposed(owner);
      return;
    }
    final existing = _nodeOwnerSubscriptions[owner];
    if (existing != null && existing.isActive) return;
    _nodeOwnerSubscriptions[owner] = owner.signals.onDispose.add(
      () => engine.ownerDisposed(owner),
      key: this,
    );
  }

  void _ownerIdle(Object owner) {
    if (owner is! GNode) return;
    _nodeOwnerSubscriptions.remove(owner)?.cancel();
  }

  bool _isOwnerDisposed(Object owner) {
    if (owner is GNode) return owner.isDisposed;
    if (owner is GImageInstance) {
      final batch = owner.batch;
      if (batch == null) return true;
      return batch.isAttached && !identical(batch.stage, stage);
    }
    return false;
  }

  void _checkAlive() {
    if (_disposed) throw StateError('GraphXMotion is disposed.');
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _cancelUpdateSubscription();
    for (final subscription in _nodeOwnerSubscriptions.values) {
      subscription.cancel();
    }
    _nodeOwnerSubscriptions.clear();
    engine.dispose();
  }
}

extension GStageMotionExtension on GStage {
  GraphXMotion get motion {
    final existing = _motionByStage[this];
    if (existing != null && !existing.isDisposed) return existing;
    final value = GraphXMotion._(this);
    _motionByStage[this] = value;
    return value;
  }
}

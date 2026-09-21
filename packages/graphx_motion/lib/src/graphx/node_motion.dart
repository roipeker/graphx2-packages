import 'package:graphx/graphx.dart';
import 'package:graphx_motion/motion.dart';

import 'stage_motion.dart';

final Expando<GNodeMotion> _motionByNode = Expando<GNodeMotion>('graphx.motion.node');

/// Stable property identities used for per-property overwrite.
abstract final class GNodeMotionProperties {
  static const x = MotionPropertyKey('GNode.x');
  static const y = MotionPropertyKey('GNode.y');
  static const scaleX = MotionPropertyKey('GNode.scaleX');
  static const scaleY = MotionPropertyKey('GNode.scaleY');
  static const rotation = MotionPropertyKey('GNode.rotation');
  static const skewX = MotionPropertyKey('GNode.skewX');
  static const skewY = MotionPropertyKey('GNode.skewY');
  static const pivotX = MotionPropertyKey('GNode.pivotX');
  static const pivotY = MotionPropertyKey('GNode.pivotY');
  static const alpha = MotionPropertyKey('GNode.alpha');
}

enum _NodeMotionMode { to, from, by }

/// Ergonomic GraphX facade over the generic property-track engine.
///
/// One call creates one handle and independent internal property tracks:
///
/// ```dart
/// node.motion.to(x: 300, y: 120, rotation: 1.2, alpha: .5);
/// ```
final class GNodeMotion {
  GNodeMotion._(this.node) {
    node.signals.onAttached.add(_onAttached, key: this);
  }

  final GNode node;
  GraphXMotion? _boundMotion;

  MotionHandle to({
    double? x,
    double? y,
    double? scale,
    double? scaleX,
    double? scaleY,
    double? rotation,
    double? skewX,
    double? skewY,
    double? pivotX,
    double? pivotY,
    double? alpha,
    MotionSpec? motion,
    double? duration,
    EaseFunction? ease,
    double? delay,
    int? repeat,
    double? repeatDelay,
    bool? yoyo,
    Overwrite? overwrite,
    Object? hook,
    bool shortest = false,
    double period = 6.283185307179586,
    MotionSample? sample,
    MotionSnap? snap,
    MotionClamp? clamp,
    void Function()? onStart,
    void Function()? onUpdate,
    void Function(int iteration)? onRepeat,
    void Function()? onComplete,
    void Function(MotionCancelReason reason)? onCancel,
  }) => _start(
    _NodeMotionMode.to,
    x: x,
    y: y,
    scale: scale,
    scaleX: scaleX,
    scaleY: scaleY,
    rotation: rotation,
    skewX: skewX,
    skewY: skewY,
    pivotX: pivotX,
    pivotY: pivotY,
    alpha: alpha,
    motion: motion,
    duration: duration,
    ease: ease,
    delay: delay,
    repeat: repeat,
    repeatDelay: repeatDelay,
    yoyo: yoyo,
    overwrite: overwrite,
    hook: hook,
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

  MotionHandle from({
    double? x,
    double? y,
    double? scale,
    double? scaleX,
    double? scaleY,
    double? rotation,
    double? skewX,
    double? skewY,
    double? pivotX,
    double? pivotY,
    double? alpha,
    MotionSpec? motion,
    double? duration,
    EaseFunction? ease,
    double? delay,
    int? repeat,
    double? repeatDelay,
    bool? yoyo,
    Overwrite? overwrite,
    Object? hook,
    bool shortest = false,
    double period = 6.283185307179586,
    MotionSample? sample,
    MotionSnap? snap,
    MotionClamp? clamp,
    void Function()? onStart,
    void Function()? onUpdate,
    void Function(int iteration)? onRepeat,
    void Function()? onComplete,
    void Function(MotionCancelReason reason)? onCancel,
  }) => _start(
    _NodeMotionMode.from,
    x: x,
    y: y,
    scale: scale,
    scaleX: scaleX,
    scaleY: scaleY,
    rotation: rotation,
    skewX: skewX,
    skewY: skewY,
    pivotX: pivotX,
    pivotY: pivotY,
    alpha: alpha,
    motion: motion,
    duration: duration,
    ease: ease,
    delay: delay,
    repeat: repeat,
    repeatDelay: repeatDelay,
    yoyo: yoyo,
    overwrite: overwrite,
    hook: hook,
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

  MotionHandle by({
    double? x,
    double? y,
    double? scale,
    double? scaleX,
    double? scaleY,
    double? rotation,
    double? skewX,
    double? skewY,
    double? pivotX,
    double? pivotY,
    double? alpha,
    MotionSpec? motion,
    double? duration,
    EaseFunction? ease,
    double? delay,
    int? repeat,
    double? repeatDelay,
    bool? yoyo,
    Overwrite? overwrite,
    Object? hook,
    MotionSample? sample,
    MotionSnap? snap,
    MotionClamp? clamp,
    void Function()? onStart,
    void Function()? onUpdate,
    void Function(int iteration)? onRepeat,
    void Function()? onComplete,
    void Function(MotionCancelReason reason)? onCancel,
  }) => _start(
    _NodeMotionMode.by,
    x: x,
    y: y,
    scale: scale,
    scaleX: scaleX,
    scaleY: scaleY,
    rotation: rotation,
    skewX: skewX,
    skewY: skewY,
    pivotX: pivotX,
    pivotY: pivotY,
    alpha: alpha,
    motion: motion,
    duration: duration,
    ease: ease,
    delay: delay,
    repeat: repeat,
    repeatDelay: repeatDelay,
    yoyo: yoyo,
    overwrite: overwrite,
    hook: hook,
    sample: sample,
    snap: snap,
    clamp: clamp,
    onStart: onStart,
    onUpdate: onUpdate,
    onRepeat: onRepeat,
    onComplete: onComplete,
    onCancel: onCancel,
  );

  MotionHandle _start(
    _NodeMotionMode mode, {
    double? x,
    double? y,
    double? scale,
    double? scaleX,
    double? scaleY,
    double? rotation,
    double? skewX,
    double? skewY,
    double? pivotX,
    double? pivotY,
    double? alpha,
    required MotionSpec? motion,
    required double? duration,
    required EaseFunction? ease,
    required double? delay,
    required int? repeat,
    required double? repeatDelay,
    required bool? yoyo,
    required Overwrite? overwrite,
    required Object? hook,
    bool shortest = false,
    double period = 6.283185307179586,
    required MotionSample? sample,
    required MotionSnap? snap,
    required MotionClamp? clamp,
    required void Function()? onStart,
    required void Function()? onUpdate,
    required void Function(int iteration)? onRepeat,
    required void Function()? onComplete,
    required void Function(MotionCancelReason reason)? onCancel,
  }) {
    if (scale != null && (scaleX != null || scaleY != null)) {
      throw ArgumentError('Use scale or scaleX/scaleY, not both.');
    }

    final stageMotion = _motionForStart();
    final properties = <DoubleMotionProperty>[];

    void add(
      MotionPropertyKey property,
      double Function() read,
      void Function(double value) write,
      double value, {
      bool circular = false,
    }) {
      final current = read();
      final (start, end) = switch (mode) {
        _NodeMotionMode.to => (current, value),
        _NodeMotionMode.from => (value, current),
        _NodeMotionMode.by => (current, current + value),
      };
      properties.add(
        DoubleMotionProperty(
          property: property,
          read: read,
          write: write,
          from: start,
          to: end,
          shortest: circular && mode != _NodeMotionMode.by && shortest,
          period: period,
        ),
      );
    }

    if (x != null) add(GNodeMotionProperties.x, () => node.x, (v) => node.x = v, x);
    if (y != null) add(GNodeMotionProperties.y, () => node.y, (v) => node.y = v, y);
    if (scale != null) {
      add(
        GNodeMotionProperties.scaleX,
        () => node.scaleX,
        (v) => node.scaleX = v,
        scale,
      );
      add(
        GNodeMotionProperties.scaleY,
        () => node.scaleY,
        (v) => node.scaleY = v,
        scale,
      );
    } else {
      if (scaleX != null) {
        add(
          GNodeMotionProperties.scaleX,
          () => node.scaleX,
          (v) => node.scaleX = v,
          scaleX,
        );
      }
      if (scaleY != null) {
        add(
          GNodeMotionProperties.scaleY,
          () => node.scaleY,
          (v) => node.scaleY = v,
          scaleY,
        );
      }
    }
    if (rotation != null) {
      add(
        GNodeMotionProperties.rotation,
        () => node.rotation,
        (v) => node.rotation = v,
        rotation,
        circular: true,
      );
    }
    if (skewX != null) {
      add(
        GNodeMotionProperties.skewX,
        () => node.skewX,
        (v) => node.skewX = v,
        skewX,
      );
    }
    if (skewY != null) {
      add(
        GNodeMotionProperties.skewY,
        () => node.skewY,
        (v) => node.skewY = v,
        skewY,
      );
    }
    if (pivotX != null) {
      add(
        GNodeMotionProperties.pivotX,
        () => node.pivotX,
        (v) => node.pivotX = v,
        pivotX,
      );
    }
    if (pivotY != null) {
      add(
        GNodeMotionProperties.pivotY,
        () => node.pivotY,
        (v) => node.pivotY = v,
        pivotY,
      );
    }
    if (alpha != null) {
      add(
        GNodeMotionProperties.alpha,
        () => node.alpha,
        (v) => node.alpha = v,
        alpha,
      );
    }

    return stageMotion.engine.toConfiguredProperties(
      properties,
      owner: node,
      hook: hook,
      motion: motion,
      duration: duration,
      ease: ease,
      delay: delay,
      repeat: repeat,
      repeatDelay: repeatDelay,
      yoyo: yoyo,
      overwrite: overwrite,
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

  /// Looks up the most recently started active motion with [hook].
  MotionHandle? operator [](Object hook) => _motionForControl()?.find(
    owner: node,
    hook: hook,
  );

  bool has(Object hook) => this[hook] != null;

  void cancel({Object? hook, bool complete = false}) {
    _motionForControl()?.cancel(owner: node, hook: hook, complete: complete);
  }

  void cancelAll({bool complete = false}) =>
      _motionForControl()?.cancel(owner: node, complete: complete);

  void pause([Object? hook]) => _motionForControl()?.pause(owner: node, hook: hook);

  void resume([Object? hook]) => _motionForControl()?.resume(owner: node, hook: hook);

  GraphXMotion _motionForStart() {
    if (!node.isAttached) {
      throw StateError('Attach the node to a stage before starting motion.');
    }
    final motion = node.stage.motion;
    final previous = _boundMotion;
    if (previous != null && !identical(previous, motion)) {
      previous.cancel(owner: node);
    }
    _boundMotion = motion;
    return motion;
  }

  GraphXMotion? _motionForControl() {
    if (node.isAttached) {
      final motion = node.stage.motion;
      final previous = _boundMotion;
      if (previous != null && !identical(previous, motion)) {
        previous.cancel(owner: node);
      }
      return _boundMotion = motion;
    }
    return _boundMotion;
  }

  void _onAttached() {
    final previous = _boundMotion;
    if (previous == null) return;
    final current = node.stage.motion;
    if (identical(previous, current)) return;
    previous.cancel(owner: node);
    _boundMotion = current;
  }
}

extension GNodeMotionExtension on GNode {
  GNodeMotion get motion => _motionByNode[this] ??= GNodeMotion._(this);
}

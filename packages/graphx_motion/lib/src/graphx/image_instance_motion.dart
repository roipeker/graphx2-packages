import 'dart:ui' as ui;

import 'package:graphx/graphx_extension.dart';
import 'package:graphx_motion/motion.dart';

import 'color_interpolation.dart';
import 'stage_motion.dart';

final Expando<GImageInstanceMotion> _motionByImageInstance = Expando<GImageInstanceMotion>(
  'graphx.motion.imageInstance',
);

abstract final class GImageInstanceMotionProperties {
  static const x = MotionPropertyKey('GImageInstance.x');
  static const y = MotionPropertyKey('GImageInstance.y');
  static const rotation = MotionPropertyKey('GImageInstance.rotation');
  static const scale = MotionPropertyKey('GImageInstance.scale');
  static const pivotX = MotionPropertyKey('GImageInstance.pivotX');
  static const pivotY = MotionPropertyKey('GImageInstance.pivotY');
  static const alpha = MotionPropertyKey('GImageInstance.alpha');
  static const color = MotionPropertyKey('GImageInstance.color');
}

typedef _ImageValues = ({
  double? x,
  double? y,
  double? rotation,
  double? scale,
  double? pivotX,
  double? pivotY,
  double? alpha,
});

enum _ImageMotionMode { to, from, by }

/// Opt-in Motion facade for one lightweight [GImageInstance].
///
/// Instances remain batch entries rather than scene nodes. Motion allocates
/// state only when this facade is used. Grouped x/y/rotation/scale samples are
/// buffered and committed through one `setTransform` call per runtime sample.
final class GImageInstanceMotion {
  GImageInstanceMotion._(this.instance);

  final GImageInstance instance;
  GraphXMotion? _boundMotion;

  MotionHandle to({
    double? x,
    double? y,
    double? rotation,
    double? scale,
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
  }) => _duration(
    _ImageMotionMode.to,
    (x: x, y: y, rotation: rotation, scale: scale, pivotX: pivotX, pivotY: pivotY, alpha: alpha),
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
    double? rotation,
    double? scale,
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
  }) => _duration(
    _ImageMotionMode.from,
    (x: x, y: y, rotation: rotation, scale: scale, pivotX: pivotX, pivotY: pivotY, alpha: alpha),
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
    double? rotation,
    double? scale,
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
  }) => _duration(
    _ImageMotionMode.by,
    (x: x, y: y, rotation: rotation, scale: scale, pivotX: pivotX, pivotY: pivotY, alpha: alpha),
    motion: motion,
    duration: duration,
    ease: ease,
    delay: delay,
    repeat: repeat,
    repeatDelay: repeatDelay,
    yoyo: yoyo,
    overwrite: overwrite,
    hook: hook,
    shortest: false,
    period: 6.283185307179586,
    sample: sample,
    snap: snap,
    clamp: clamp,
    onStart: onStart,
    onUpdate: onUpdate,
    onRepeat: onRepeat,
    onComplete: onComplete,
    onCancel: onCancel,
  );

  MotionHandle spring({
    double? x,
    double? y,
    double? rotation,
    double? scale,
    double? pivotX,
    double? pivotY,
    double? alpha,
    Spring spring = Spring.snappy,
    double initialVelocity = 0.0,
    double delay = 0.0,
    Overwrite overwrite = Overwrite.auto,
    Object? hook,
    bool shortest = false,
    double period = 6.283185307179586,
    bool inheritVelocity = true,
    MotionSample? sample,
    MotionSnap? snap,
    MotionClamp? clamp,
    void Function()? onStart,
    void Function()? onUpdate,
    void Function()? onSettled,
    void Function()? onComplete,
    void Function(MotionCancelReason reason)? onCancel,
  }) {
    final motion = _motionForStart();
    final state = _ImageSampleState(instance);
    return motion.engine.springProperties(
      _properties(
        _ImageMotionMode.to,
        state,
        (
          x: x,
          y: y,
          rotation: rotation,
          scale: scale,
          pivotX: pivotX,
          pivotY: pivotY,
          alpha: alpha,
        ),
        shortest: shortest,
        period: period,
      ),
      owner: instance,
      hook: hook,
      spring: spring,
      initialVelocity: initialVelocity,
      delay: delay,
      overwrite: overwrite,
      inheritVelocity: inheritVelocity,
      sample: sample,
      snap: snap,
      clamp: clamp,
      onStart: onStart,
      onUpdate: _flushThen(state, onUpdate),
      onSettled: onSettled,
      onComplete: onComplete,
      onCancel: onCancel,
    );
  }

  MotionHandle damp({
    double? x,
    double? y,
    double? rotation,
    double? scale,
    double? pivotX,
    double? pivotY,
    double? alpha,
    Damp damp = const Damp(),
    double delay = 0.0,
    Overwrite overwrite = Overwrite.auto,
    Object? hook,
    bool shortest = false,
    double period = 6.283185307179586,
    MotionSample? sample,
    MotionSnap? snap,
    MotionClamp? clamp,
    void Function()? onStart,
    void Function()? onUpdate,
    void Function()? onSettled,
    void Function()? onComplete,
    void Function(MotionCancelReason reason)? onCancel,
  }) {
    final motion = _motionForStart();
    final state = _ImageSampleState(instance);
    return motion.engine.dampProperties(
      _properties(
        _ImageMotionMode.to,
        state,
        (
          x: x,
          y: y,
          rotation: rotation,
          scale: scale,
          pivotX: pivotX,
          pivotY: pivotY,
          alpha: alpha,
        ),
        shortest: shortest,
        period: period,
      ),
      owner: instance,
      hook: hook,
      damp: damp,
      delay: delay,
      overwrite: overwrite,
      sample: sample,
      snap: snap,
      clamp: clamp,
      onStart: onStart,
      onUpdate: _flushThen(state, onUpdate),
      onSettled: onSettled,
      onComplete: onComplete,
      onCancel: onCancel,
    );
  }

  MotionHandle inertia({
    double? velocityX,
    double? velocityY,
    double? velocityRotation,
    MotionBounds? xBounds,
    MotionBounds? yBounds,
    MotionBounds? rotationBounds,
    double friction = 5.0,
    double tolerance = 0.01,
    double delay = 0.0,
    Overwrite overwrite = Overwrite.auto,
    Object? hook,
    void Function()? onStart,
    void Function()? onUpdate,
    void Function()? onSettled,
    void Function()? onComplete,
    void Function(MotionCancelReason reason)? onCancel,
  }) {
    final motion = _motionForStart();
    final state = _ImageSampleState(instance);
    return motion.engine.inertiaProperties(
      <DoubleInertiaProperty>[
        if (velocityX != null)
          DoubleInertiaProperty(
            property: GImageInstanceMotionProperties.x,
            read: () => instance.x,
            write: state.setX,
            velocity: velocityX,
            inertia: _axisInertia(xBounds, friction, tolerance),
          ),
        if (velocityY != null)
          DoubleInertiaProperty(
            property: GImageInstanceMotionProperties.y,
            read: () => instance.y,
            write: state.setY,
            velocity: velocityY,
            inertia: _axisInertia(yBounds, friction, tolerance),
          ),
        if (velocityRotation != null)
          DoubleInertiaProperty(
            property: GImageInstanceMotionProperties.rotation,
            read: () => instance.rotation,
            write: state.setRotation,
            velocity: velocityRotation,
            inertia: _axisInertia(rotationBounds, friction, tolerance),
          ),
      ],
      owner: instance,
      hook: hook,
      delay: delay,
      overwrite: overwrite,
      onStart: onStart,
      onUpdate: _flushThen(state, onUpdate),
      onSettled: onSettled,
      onComplete: onComplete,
      onCancel: onCancel,
    );
  }

  /// Animates the instance modulation color.
  ///
  /// `drawRawAtlas` accepts packed 32-bit colors, so the final per-sample value
  /// is converted to sRGB before assignment. Interpolation itself still follows
  /// [ColorLerpMode], including P3-aware RGB interpolation before this boundary.
  MotionHandle toColor(
    ui.Color color, {
    double duration = .3,
    EaseFunction ease = Ease.quadOut,
    double delay = 0.0,
    Overwrite overwrite = Overwrite.auto,
    Object? hook,
    ColorLerpMode mode = ColorLerpMode.rgb,
    bool shortestHue = true,
    void Function()? onComplete,
    void Function(MotionCancelReason reason)? onCancel,
  }) => _motionForStart().toColor(
    () => instance.color,
    _writePackedColor,
    color,
    duration: duration,
    ease: ease,
    delay: delay,
    overwrite: overwrite,
    owner: instance,
    hook: hook,
    property: GImageInstanceMotionProperties.color,
    mode: mode,
    shortestHue: shortestHue,
    onComplete: onComplete,
    onCancel: onCancel,
  );

  MotionHandle springColor(
    ui.Color color, {
    Spring spring = Spring.snappy,
    double delay = 0.0,
    Overwrite overwrite = Overwrite.auto,
    Object? hook,
    ColorLerpMode mode = ColorLerpMode.rgb,
    bool shortestHue = true,
    void Function()? onSettled,
    void Function()? onComplete,
    void Function(MotionCancelReason reason)? onCancel,
  }) => _motionForStart().springColor(
    () => instance.color,
    _writePackedColor,
    color,
    spring: spring,
    delay: delay,
    overwrite: overwrite,
    owner: instance,
    hook: hook,
    property: GImageInstanceMotionProperties.color,
    mode: mode,
    shortestHue: shortestHue,
    onSettled: onSettled,
    onComplete: onComplete,
    onCancel: onCancel,
  );

  MotionHandle dampColor(
    ui.Color color, {
    Damp damp = const Damp(),
    double delay = 0.0,
    Overwrite overwrite = Overwrite.auto,
    Object? hook,
    ColorLerpMode mode = ColorLerpMode.rgb,
    bool shortestHue = true,
    void Function()? onSettled,
    void Function()? onComplete,
    void Function(MotionCancelReason reason)? onCancel,
  }) => _motionForStart().dampColor(
    () => instance.color,
    _writePackedColor,
    color,
    damp: damp,
    delay: delay,
    overwrite: overwrite,
    owner: instance,
    hook: hook,
    property: GImageInstanceMotionProperties.color,
    mode: mode,
    shortestHue: shortestHue,
    onSettled: onSettled,
    onComplete: onComplete,
    onCancel: onCancel,
  );

  MotionHandle? operator [](Object hook) => _motionForControl()?.find(owner: instance, hook: hook);

  void cancel({Object? hook, bool complete = false}) => _motionForControl()?.cancel(
    owner: instance,
    hook: hook,
    complete: complete,
  );

  void pause([Object? hook]) => _motionForControl()?.pause(owner: instance, hook: hook);

  void resume([Object? hook]) => _motionForControl()?.resume(owner: instance, hook: hook);

  MotionHandle _duration(
    _ImageMotionMode mode,
    _ImageValues values, {
    required MotionSpec? motion,
    required double? duration,
    required EaseFunction? ease,
    required double? delay,
    required int? repeat,
    required double? repeatDelay,
    required bool? yoyo,
    required Overwrite? overwrite,
    required Object? hook,
    required bool shortest,
    required double period,
    required MotionSample? sample,
    required MotionSnap? snap,
    required MotionClamp? clamp,
    required void Function()? onStart,
    required void Function()? onUpdate,
    required void Function(int iteration)? onRepeat,
    required void Function()? onComplete,
    required void Function(MotionCancelReason reason)? onCancel,
  }) {
    final stageMotion = _motionForStart();
    final state = _ImageSampleState(instance);
    return stageMotion.engine.toConfiguredProperties(
      _properties(
        mode,
        state,
        values,
        shortest: shortest,
        period: period,
      ),
      owner: instance,
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
      onUpdate: _flushThen(state, onUpdate),
      onRepeat: onRepeat,
      onComplete: onComplete,
      onCancel: onCancel,
    );
  }

  void _writePackedColor(ui.Color value) {
    instance.color = value.colorSpace == ui.ColorSpace.sRGB
        ? value
        : value.withValues(colorSpace: ui.ColorSpace.sRGB);
  }

  GraphXMotion _motionForStart() {
    final batch = instance.batch;
    if (batch == null) {
      throw StateError('GImageInstance is no longer attached to a batch.');
    }
    if (!batch.isAttached) {
      throw StateError('Attach the image batch to a stage before starting motion.');
    }
    final motion = batch.stage.motion;
    final previous = _boundMotion;
    if (previous != null && !identical(previous, motion)) {
      previous.cancel(owner: instance);
    }
    return _boundMotion = motion;
  }

  GraphXMotion? _motionForControl() {
    final batch = instance.batch;
    if (batch != null && batch.isAttached) {
      final motion = batch.stage.motion;
      final previous = _boundMotion;
      if (previous != null && !identical(previous, motion)) {
        previous.cancel(owner: instance);
      }
      return _boundMotion = motion;
    }
    return _boundMotion;
  }
}

extension GImageInstanceMotionExtension on GImageInstance {
  GImageInstanceMotion get motion => _motionByImageInstance[this] ??= GImageInstanceMotion._(this);
}

List<DoubleMotionProperty> _properties(
  _ImageMotionMode mode,
  _ImageSampleState state,
  _ImageValues values, {
  required bool shortest,
  required double period,
}) {
  final instance = state.instance;
  final result = <DoubleMotionProperty>[];

  void add(
    MotionPropertyKey property,
    double Function() read,
    void Function(double value) write,
    double? value, {
    required String name,
    bool circular = false,
    double? min,
    double? max,
  }) {
    if (value == null) return;
    if (!value.isFinite) {
      throw ArgumentError.value(value, name, 'must be finite');
    }
    final current = read();
    final (double start, double end) = switch (mode) {
      _ImageMotionMode.to => (current, value),
      _ImageMotionMode.from => (value, current),
      _ImageMotionMode.by => (current, current + value),
    };
    if (!start.isFinite || !end.isFinite) {
      throw ArgumentError.value(value, name, 'produces a non-finite motion value');
    }
    if (min != null && (start < min || end < min)) {
      throw ArgumentError.value(value, name, 'must stay >= $min');
    }
    if (max != null && (start > max || end > max)) {
      throw ArgumentError.value(value, name, 'must stay <= $max');
    }
    result.add(
      DoubleMotionProperty(
        property: property,
        read: read,
        write: write,
        from: mode == _ImageMotionMode.from ? start : null,
        to: end,
        shortest: circular && mode != _ImageMotionMode.by && shortest,
        period: period,
      ),
    );
  }

  add(GImageInstanceMotionProperties.x, () => instance.x, state.setX, values.x, name: 'x');
  add(GImageInstanceMotionProperties.y, () => instance.y, state.setY, values.y, name: 'y');
  add(
    GImageInstanceMotionProperties.rotation,
    () => instance.rotation,
    state.setRotation,
    values.rotation,
    name: 'rotation',
    circular: true,
  );
  add(
    GImageInstanceMotionProperties.scale,
    () => instance.scale,
    state.setScale,
    values.scale,
    name: 'scale',
    min: 0.0,
  );
  add(
    GImageInstanceMotionProperties.pivotX,
    () => instance.pivotX,
    state.setPivotX,
    values.pivotX,
    name: 'pivotX',
  );
  add(
    GImageInstanceMotionProperties.pivotY,
    () => instance.pivotY,
    state.setPivotY,
    values.pivotY,
    name: 'pivotY',
  );
  add(
    GImageInstanceMotionProperties.alpha,
    () => instance.alpha,
    state.setAlpha,
    values.alpha,
    name: 'alpha',
    min: 0.0,
    max: 1.0,
  );
  return result;
}

final class _ImageSampleState {
  _ImageSampleState(this.instance)
    : x = instance.x,
      y = instance.y,
      rotation = instance.rotation,
      scale = instance.scale,
      pivotX = instance.pivotX,
      pivotY = instance.pivotY,
      alpha = instance.alpha;

  static const _x = 1 << 0;
  static const _y = 1 << 1;
  static const _rotation = 1 << 2;
  static const _scale = 1 << 3;
  static const _pivotX = 1 << 4;
  static const _pivotY = 1 << 5;
  static const _alpha = 1 << 6;
  static const _transform = _x | _y | _rotation | _scale;
  static const _pivot = _pivotX | _pivotY;

  final GImageInstance instance;
  double x;
  double y;
  double rotation;
  double scale;
  double pivotX;
  double pivotY;
  double alpha;
  int _dirty = 0;

  void setX(double value) {
    x = value;
    _dirty |= _x;
  }

  void setY(double value) {
    y = value;
    _dirty |= _y;
  }

  void setRotation(double value) {
    rotation = value;
    _dirty |= _rotation;
  }

  void setScale(double value) {
    scale = value;
    _dirty |= _scale;
  }

  void setPivotX(double value) {
    pivotX = value;
    _dirty |= _pivotX;
  }

  void setPivotY(double value) {
    pivotY = value;
    _dirty |= _pivotY;
  }

  void setAlpha(double value) {
    alpha = value;
    _dirty |= _alpha;
  }

  void flush() {
    final dirty = _dirty;
    _dirty = 0;
    if (dirty == 0 || !instance.isAttached) return;

    if ((dirty & _transform) != 0) {
      instance.setTransform(
        x: (dirty & _x) != 0 ? x : instance.x,
        y: (dirty & _y) != 0 ? y : instance.y,
        rotation: (dirty & _rotation) != 0 ? rotation : instance.rotation,
        scale: (dirty & _scale) != 0 ? _nonNegative(scale) : instance.scale,
      );
    }
    if ((dirty & _pivot) != 0) {
      instance.setPivot(
        (dirty & _pivotX) != 0 ? pivotX : instance.pivotX,
        (dirty & _pivotY) != 0 ? pivotY : instance.pivotY,
      );
    }
    if ((dirty & _alpha) != 0) {
      instance.alpha = alpha.clamp(0.0, 1.0).toDouble();
    }
  }
}

void Function() _flushThen(_ImageSampleState state, void Function()? callback) => () {
  state.flush();
  callback?.call();
};

Inertia _axisInertia(MotionBounds? bounds, double friction, double tolerance) => bounds == null
    ? Inertia(friction: friction, tolerance: tolerance)
    : bounds.inertia(friction: friction, tolerance: tolerance);

double _nonNegative(double value) => value < 0.0 ? 0.0 : value;

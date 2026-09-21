part of '../../motion.dart';

/// Interpolates one value of type [T] between [from] and [to].
typedef MotionInterpolator<T> = T Function(T from, T to, double t);

// Dart generic classes are covariant by default. MotionProperty is a true
// read/write channel and therefore must be invariant: treating a
// MotionProperty<double> as MotionProperty<num> can pass an int into a double
// writer. This follows Dart's documented invariance-emulation pattern until
// declaration-site `inout` variance is available in stable Dart.
typedef _MotionInvariant<T> = T Function(T);
typedef MotionProperty<T> = _MotionProperty<T, _MotionInvariant<T>>;

int _nextMotionPropertyId = 0;

/// Passive destination used by [MotionEnginePropertyGroupExtension.toMany].
///
/// A target is created through [MotionProperty.target]. Creation never starts
/// motion; it only captures one type-checked destination for later orchestration.
sealed class MotionTarget {
  const MotionTarget._();

  Object get _owner;
  DoubleMotionProperty _compile();
}

final class _TypedMotionTarget<T> extends MotionTarget {
  const _TypedMotionTarget(this.property, this.value, this.interpolate) : super._();

  final MotionProperty<T> property;
  final T value;
  final MotionInterpolator<T>? interpolate;

  @override
  Object get _owner => property.motionOwner;

  @override
  DoubleMotionProperty _compile() {
    final lerp = interpolate ?? property.interpolate;
    late T start;
    var captured = false;
    return DoubleMotionProperty(
      read: () => 0.0,
      write: (t) {
        if (!captured) {
          start = property.read();
          captured = true;
        }
        property.set(lerp(start, value, t));
      },
      from: 0.0,
      to: 1.0,
      property: property.motionKey,
    );
  }
}

/// Reusable readable/writable animation channel.
///
/// A property describes identity and access only. It owns no tween state and
/// may be reused across any number of motions. When [owner] is omitted the
/// property object itself becomes the overwrite owner, giving a declared free
/// property stable identity without requiring an external owner object.
final class _MotionProperty<T, Invariance extends _MotionInvariant<T>> {
  _MotionProperty({
    required this.read,
    required this.write,
    MotionInterpolator<T>? interpolate,
    this.owner,
    MotionPropertyKey? property,
    this.invalidate,
  }) : interpolate = interpolate ?? _defaultInterpolator<T>(),
       property = property ?? MotionPropertyKey('MotionProperty.value#${_nextMotionPropertyId++}');

  final T Function() read;
  final void Function(T value) write;
  final MotionInterpolator<T> interpolate;
  final Object? owner;
  final MotionPropertyKey property;
  final void Function()? invalidate;

  Object get motionOwner => owner ?? this;

  MotionPropertyKey get motionKey => property;

  void set(T value) {
    write(value);
    invalidate?.call();
  }

  /// Describes a destination for a later grouped motion.
  ///
  /// This method is intentionally passive: only `stage.motion.toMany(...)`
  /// (or another orchestrator) starts the motion.
  MotionTarget target(
    T value, {
    MotionInterpolator<T>? interpolate,
  }) => _TypedMotionTarget<T>(this, value, interpolate);
}

MotionInterpolator<T> _defaultInterpolator<T>() {
  if (T == double) {
    return ((T from, T to, double t) {
      final a = from as double;
      final b = to as double;
      return (a + (b - a) * t) as T;
    });
  }
  throw ArgumentError(
    'MotionProperty<$T> requires an interpolate callback. '
    'Only double has a generic-core default.',
  );
}

/// Generic value-channel duration motion.
///
/// [MotionProperty] is intentionally invariant because it is both readable and
/// writable. When a target literal would otherwise widen the type (for example
/// `100` for a `MotionProperty<double>`), pass the generic explicitly:
/// `motion.to<double>(property, 100)`.
extension MotionEnginePropertyExtension on MotionEngine {
  MotionHandle to<T>(
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
    Object? hook,
    void Function()? onStart,
    void Function()? onUpdate,
    void Function(int iteration)? onRepeat,
    void Function()? onComplete,
    void Function(MotionCancelReason reason)? onCancel,
  }) {
    final lerp = interpolate ?? property.interpolate;
    late T start;
    var captured = false;
    return toConfiguredDouble(
      () => 0.0,
      (t) {
        if (!captured) {
          start = property.read();
          captured = true;
        }
        property.set(lerp(start, target, t));
      },
      1.0,
      from: 0.0,
      motion: motion,
      duration: duration,
      ease: ease,
      delay: delay,
      repeat: repeat,
      repeatDelay: repeatDelay,
      yoyo: yoyo,
      overwrite: overwrite,
      owner: property.motionOwner,
      hook: hook,
      property: property.motionKey,
      onStart: onStart,
      onUpdate: onUpdate,
      onRepeat: onRepeat,
      onComplete: onComplete,
      onCancel: onCancel,
    );
  }

  MotionHandle from<T>(
    MotionProperty<T> property,
    T source, {
    MotionSpec? motion,
    MotionInterpolator<T>? interpolate,
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
    final lerp = interpolate ?? property.interpolate;
    late T target;
    var captured = false;
    return toConfiguredDouble(
      () => 0.0,
      (t) {
        if (!captured) {
          target = property.read();
          captured = true;
        }
        property.set(lerp(source, target, t));
      },
      1.0,
      from: 0.0,
      motion: motion,
      duration: duration,
      ease: ease,
      delay: delay,
      repeat: repeat,
      repeatDelay: repeatDelay,
      yoyo: yoyo,
      overwrite: overwrite,
      owner: property.motionOwner,
      hook: hook,
      property: property.motionKey,
      onStart: onStart,
      onUpdate: onUpdate,
      onRepeat: onRepeat,
      onComplete: onComplete,
      onCancel: onCancel,
    );
  }
}

/// Heterogeneous grouped generic properties.
///
/// Targets in one group must share the same owner. This keeps overwrite,
/// lifecycle, lookup, and cancellation semantics identical to existing grouped
/// GraphX facades without introducing a multi-owner runtime. For fields on one
/// state/controller object, declare each property with `owner: this`.
extension MotionEnginePropertyGroupExtension on MotionEngine {
  MotionHandle toMany(
    Iterable<MotionTarget> targets, {
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
    final descriptors = targets.toList(growable: false);
    if (descriptors.isEmpty) {
      onComplete?.call();
      return MotionHandle._completed();
    }

    final owner = descriptors.first._owner;
    final properties = <DoubleMotionProperty>[];
    for (final target in descriptors) {
      if (!identical(target._owner, owner)) {
        throw ArgumentError(
          'Grouped MotionProperty targets must share one owner. '
          'Declare related properties with the same `owner:`.',
        );
      }
      properties.add(target._compile());
    }

    return toConfiguredProperties(
      properties,
      owner: owner,
      hook: hook,
      motion: motion,
      duration: duration,
      ease: ease,
      delay: delay,
      repeat: repeat,
      repeatDelay: repeatDelay,
      yoyo: yoyo,
      overwrite: overwrite,
      onStart: onStart,
      onUpdate: onUpdate,
      onRepeat: onRepeat,
      onComplete: onComplete,
      onCancel: onCancel,
    );
  }
}

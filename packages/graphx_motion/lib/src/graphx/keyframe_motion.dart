import 'package:graphx/graphx.dart';
import 'package:graphx_motion/motion.dart';

import 'node_motion.dart';

/// Ergonomic retained keyframe authoring for [GNode] properties.
extension GNodeMotionKeyframesExtension on GNodeMotion {
  MotionClip keyframes(
    void Function(GNodeKeyframes frames) build, {
    required double duration,
    EaseFunction? ease,
    bool shortest = false,
    double period = 6.283185307179586,
  }) {
    if (!duration.isFinite || duration <= 0.0) {
      throw ArgumentError.value(duration, 'duration', 'Must be finite and > 0.');
    }
    if (!period.isFinite || period <= 0.0) {
      throw ArgumentError.value(period, 'period', 'Must be finite and > 0.');
    }
    final frames = GNodeKeyframes._(
      node,
      duration,
      ease,
      shortest,
      period,
    );
    build(frames);
    return frames._clip();
  }
}

/// Node keyframe authoring builder.
///
/// Omitted properties are simply not keyed at that position. A property's first
/// key after 0 animates from its value at clip start; after its final key it
/// holds the last authored value.
final class GNodeKeyframes {
  GNodeKeyframes._(
    this.node,
    this.duration,
    this.ease,
    this.shortest,
    this.period,
  );

  final GNode node;
  final double duration;
  final EaseFunction? ease;
  final bool shortest;
  final double period;

  MotionKeyframes<double>? _x;
  MotionKeyframes<double>? _y;
  MotionKeyframes<double>? _scaleX;
  MotionKeyframes<double>? _scaleY;
  MotionKeyframes<double>? _rotation;
  MotionKeyframes<double>? _skewX;
  MotionKeyframes<double>? _skewY;
  MotionKeyframes<double>? _pivotX;
  MotionKeyframes<double>? _pivotY;
  MotionKeyframes<double>? _alpha;

  GNodeKeyframes at(
    double position, {
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
    EaseFunction? ease,
  }) {
    if (scale != null && (scaleX != null || scaleY != null)) {
      throw ArgumentError('Use scale or scaleX/scaleY, not both.');
    }
    _finite('x', x);
    _finite('y', y);
    _finite('scale', scale);
    _finite('scaleX', scaleX);
    _finite('scaleY', scaleY);
    _finite('rotation', rotation);
    _finite('skewX', skewX);
    _finite('skewY', skewY);
    _finite('pivotX', pivotX);
    _finite('pivotY', pivotY);
    if (alpha != null && (!alpha.isFinite || alpha < 0.0 || alpha > 1.0)) {
      throw ArgumentError.value(alpha, 'alpha', 'Must be finite and within 0..1.');
    }

    if (x != null) {
      (_x ??= _linear(
        GNodeMotionProperties.x,
        () => node.x,
        (v) => node.x = v,
      )).at(position, x, ease: ease);
    }
    if (y != null) {
      (_y ??= _linear(
        GNodeMotionProperties.y,
        () => node.y,
        (v) => node.y = v,
      )).at(position, y, ease: ease);
    }
    if (scale != null) {
      (_scaleX ??= _linear(
        GNodeMotionProperties.scaleX,
        () => node.scaleX,
        (v) => node.scaleX = v,
      )).at(position, scale, ease: ease);
      (_scaleY ??= _linear(
        GNodeMotionProperties.scaleY,
        () => node.scaleY,
        (v) => node.scaleY = v,
      )).at(position, scale, ease: ease);
    } else {
      if (scaleX != null) {
        (_scaleX ??= _linear(
          GNodeMotionProperties.scaleX,
          () => node.scaleX,
          (v) => node.scaleX = v,
        )).at(position, scaleX, ease: ease);
      }
      if (scaleY != null) {
        (_scaleY ??= _linear(
          GNodeMotionProperties.scaleY,
          () => node.scaleY,
          (v) => node.scaleY = v,
        )).at(position, scaleY, ease: ease);
      }
    }
    if (rotation != null) {
      (_rotation ??= _circular(
        GNodeMotionProperties.rotation,
        () => node.rotation,
        (v) => node.rotation = v,
      )).at(position, rotation, ease: ease);
    }
    if (skewX != null) {
      (_skewX ??= _linear(
        GNodeMotionProperties.skewX,
        () => node.skewX,
        (v) => node.skewX = v,
      )).at(position, skewX, ease: ease);
    }
    if (skewY != null) {
      (_skewY ??= _linear(
        GNodeMotionProperties.skewY,
        () => node.skewY,
        (v) => node.skewY = v,
      )).at(position, skewY, ease: ease);
    }
    if (pivotX != null) {
      (_pivotX ??= _linear(
        GNodeMotionProperties.pivotX,
        () => node.pivotX,
        (v) => node.pivotX = v,
      )).at(position, pivotX, ease: ease);
    }
    if (pivotY != null) {
      (_pivotY ??= _linear(
        GNodeMotionProperties.pivotY,
        () => node.pivotY,
        (v) => node.pivotY = v,
      )).at(position, pivotY, ease: ease);
    }
    if (alpha != null) {
      (_alpha ??= _linear(
        GNodeMotionProperties.alpha,
        () => node.alpha,
        (v) => node.alpha = v,
      )).at(position, alpha, ease: ease);
    }
    return this;
  }

  MotionKeyframes<double> _linear(
    MotionPropertyKey key,
    double Function() read,
    void Function(double) write,
  ) => MotionProperty<double>(
    owner: node,
    property: key,
    read: read,
    write: write,
  ).keyframes(duration: duration, ease: ease);

  MotionKeyframes<double> _circular(
    MotionPropertyKey key,
    double Function() read,
    void Function(double) write,
  ) => MotionProperty<double>(
    owner: node,
    property: key,
    read: read,
    write: write,
    interpolate: shortest
        ? (from, to, t) {
            var delta = (to - from) % period;
            if (delta > period * .5) delta -= period;
            if (delta < -period * .5) delta += period;
            return from + delta * t;
          }
        : null,
  ).keyframes(duration: duration, ease: ease);

  MotionClip _clip() => MotionClip.parallel([
    if (_x != null) _x!,
    if (_y != null) _y!,
    if (_scaleX != null) _scaleX!,
    if (_scaleY != null) _scaleY!,
    if (_rotation != null) _rotation!,
    if (_skewX != null) _skewX!,
    if (_skewY != null) _skewY!,
    if (_pivotX != null) _pivotX!,
    if (_pivotY != null) _pivotY!,
    if (_alpha != null) _alpha!,
  ]);
}

void _finite(String name, double? value) {
  if (value != null && !value.isFinite) {
    throw ArgumentError.value(value, name, 'Must be finite.');
  }
}

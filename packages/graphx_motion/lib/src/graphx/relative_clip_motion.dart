import 'package:graphx_motion/motion.dart';

import 'node_motion.dart';

/// Passive retained counterpart to [GNodeMotion.by].
///
/// Relative values are resolved from the node at the clip's actual local start.
extension GNodeMotionRelativeClipExtension on GNodeMotion {
  MotionClip clipBy({
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
  }) {
    if (scale != null && (scaleX != null || scaleY != null)) {
      throw ArgumentError('Use scale or scaleX/scaleY, not both.');
    }

    final properties = <DoubleMotionProperty>[];

    void add(
      MotionPropertyKey key,
      double Function() read,
      void Function(double) write,
      double delta,
      String name,
    ) {
      if (!delta.isFinite) {
        throw ArgumentError.value(delta, name, 'Must be finite.');
      }
      double? start;
      properties.add(
        DoubleMotionProperty(
          property: key,
          read: () => 0.0,
          write: (t) {
            start ??= read();
            write(start! + delta * t);
          },
          from: 0.0,
          to: 1.0,
        ),
      );
    }

    if (x != null) add(GNodeMotionProperties.x, () => node.x, (v) => node.x = v, x, 'x');
    if (y != null) add(GNodeMotionProperties.y, () => node.y, (v) => node.y = v, y, 'y');
    if (scale != null) {
      add(
        GNodeMotionProperties.scaleX,
        () => node.scaleX,
        (v) => node.scaleX = v,
        scale,
        'scale',
      );
      add(
        GNodeMotionProperties.scaleY,
        () => node.scaleY,
        (v) => node.scaleY = v,
        scale,
        'scale',
      );
    } else {
      if (scaleX != null) {
        add(
          GNodeMotionProperties.scaleX,
          () => node.scaleX,
          (v) => node.scaleX = v,
          scaleX,
          'scaleX',
        );
      }
      if (scaleY != null) {
        add(
          GNodeMotionProperties.scaleY,
          () => node.scaleY,
          (v) => node.scaleY = v,
          scaleY,
          'scaleY',
        );
      }
    }
    if (rotation != null) {
      add(
        GNodeMotionProperties.rotation,
        () => node.rotation,
        (v) => node.rotation = v,
        rotation,
        'rotation',
      );
    }
    if (skewX != null) {
      add(
        GNodeMotionProperties.skewX,
        () => node.skewX,
        (v) => node.skewX = v,
        skewX,
        'skewX',
      );
    }
    if (skewY != null) {
      add(
        GNodeMotionProperties.skewY,
        () => node.skewY,
        (v) => node.skewY = v,
        skewY,
        'skewY',
      );
    }
    if (pivotX != null) {
      add(
        GNodeMotionProperties.pivotX,
        () => node.pivotX,
        (v) => node.pivotX = v,
        pivotX,
        'pivotX',
      );
    }
    if (pivotY != null) {
      add(
        GNodeMotionProperties.pivotY,
        () => node.pivotY,
        (v) => node.pivotY = v,
        pivotY,
        'pivotY',
      );
    }
    if (alpha != null) {
      add(
        GNodeMotionProperties.alpha,
        () => node.alpha,
        (v) => node.alpha = v,
        alpha,
        'alpha',
      );
    }

    return MotionClip.properties(
      properties,
      owner: node,
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
}

import 'package:graphx/graphx.dart';
import 'package:graphx_motion/motion.dart';

import 'node_motion.dart';
import 'stage_motion.dart';

extension GraphXMotionTimelineExtension on GraphXMotion {
  MotionTimeline timeline({
    MotionSpec? defaults,
    void Function()? onStart,
    void Function()? onComplete,
    void Function()? onCancel,
  }) => engine.timeline(
    defaults: defaults,
    onStart: onStart,
    onComplete: onComplete,
    onCancel: onCancel,
  );
}

/// GraphX-specific Timeline facade. The generic core remains host-agnostic.
extension GraphXTimelineMotionExtension on MotionTimeline {
  GTimelineNodeMotion node(GNode node) => GTimelineNodeMotion._(this, node);
}

final class GTimelineNodeMotion {
  GTimelineNodeMotion._(this.timeline, this.node);

  final MotionTimeline timeline;
  final GNode node;

  MotionTimeline to({
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
    Object? at,
    MotionSpec? motion,
    double? duration,
    EaseFunction? ease,
    double? delay,
    int? repeat,
    double? repeatDelay,
    bool? yoyo,
    Overwrite? overwrite,
    bool shortest = false,
    double period = 6.283185307179586,
  }) {
    if (scale != null && (scaleX != null || scaleY != null)) {
      throw ArgumentError('Use scale or scaleX/scaleY, not both.');
    }

    final properties = <DoubleMotionProperty>[];
    void add(
      MotionPropertyKey key,
      double Function() read,
      void Function(double) write,
      double target, {
      bool circular = false,
    }) {
      properties.add(
        DoubleMotionProperty(
          property: key,
          read: read,
          write: write,
          to: target,
          shortest: circular && shortest,
          period: period,
        ),
      );
    }

    if (x != null) add(GNodeMotionProperties.x, () => node.x, (v) => node.x = v, x);
    if (y != null) add(GNodeMotionProperties.y, () => node.y, (v) => node.y = v, y);
    if (scale != null) {
      add(GNodeMotionProperties.scaleX, () => node.scaleX, (v) => node.scaleX = v, scale);
      add(GNodeMotionProperties.scaleY, () => node.scaleY, (v) => node.scaleY = v, scale);
    } else {
      if (scaleX != null) {
        add(GNodeMotionProperties.scaleX, () => node.scaleX, (v) => node.scaleX = v, scaleX);
      }
      if (scaleY != null) {
        add(GNodeMotionProperties.scaleY, () => node.scaleY, (v) => node.scaleY = v, scaleY);
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
    if (skewX != null)
      add(GNodeMotionProperties.skewX, () => node.skewX, (v) => node.skewX = v, skewX);
    if (skewY != null)
      add(GNodeMotionProperties.skewY, () => node.skewY, (v) => node.skewY = v, skewY);
    if (pivotX != null)
      add(GNodeMotionProperties.pivotX, () => node.pivotX, (v) => node.pivotX = v, pivotX);
    if (pivotY != null)
      add(GNodeMotionProperties.pivotY, () => node.pivotY, (v) => node.pivotY = v, pivotY);
    if (alpha != null)
      add(GNodeMotionProperties.alpha, () => node.alpha, (v) => node.alpha = v, alpha);

    timeline.toProperties(
      properties,
      owner: node,
      at: at,
      motion: motion,
      duration: duration,
      ease: ease,
      delay: delay,
      repeat: repeat,
      repeatDelay: repeatDelay,
      yoyo: yoyo,
      overwrite: overwrite,
    );
    return timeline;
  }
}

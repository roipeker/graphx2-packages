part of '../../motion.dart';

/// Origin used to distribute stagger offsets across an ordered collection.
enum StaggerFrom {
  /// First item starts at the base timeline position.
  start,

  /// Last item starts at the base timeline position.
  end,

  /// The middle item(s) start first and offsets grow toward both edges.
  center,
}

/// Timeline placement sugar for repeated passive clips.
///
/// Stagger owns no runtime state. It expands an ordered collection into normal
/// [MotionTimeline.add] calls at deterministic offsets, so nesting, overwrite,
/// seek/reverse, pooling, and playhead semantics remain Timeline semantics.
extension MotionTimelineStaggerExtension on MotionTimeline {
  MotionTimeline stagger<T>(
    Iterable<T> items, {
    required double each,
    required MotionClip Function(T item, int index) clip,
    StaggerFrom from = StaggerFrom.start,
    Object? at,
  }) {
    _checkMutable();
    if (!each.isFinite || each < 0.0) {
      throw ArgumentError.value(each, 'each', 'Must be finite and >= 0.');
    }

    final values = items.toList(growable: false);
    if (values.isEmpty) return this;

    final base = _resolveAt(at, fallback: _cursor);
    final center = (values.length - 1) * 0.5;
    final centerBias = values.length.isEven ? 0.5 : 0.0;

    for (var i = 0; i < values.length; ++i) {
      final order = switch (from) {
        StaggerFrom.start => i.toDouble(),
        StaggerFrom.end => (values.length - 1 - i).toDouble(),
        StaggerFrom.center => (i - center).abs() - centerBias,
      };
      add(clip(values[i], i), at: base + order * each);
    }
    return this;
  }
}

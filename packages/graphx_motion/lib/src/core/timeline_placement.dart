part of '../../motion.dart';

/// Relative composition helpers for [MotionTimeline].
///
/// These remain thin setup-time sugar over [MotionTimeline.add]. They do not
/// introduce another scheduling model or any per-frame work.
extension MotionTimelinePlacementExtension on MotionTimeline {
  /// Places [clip] relative to the start of the previously inserted clip.
  ///
  /// If the timeline has no previous clip, the reference start is zero.
  /// [offset] may be negative as long as the resolved start stays >= 0.
  MotionTimeline withPrevious(MotionClip clip, {double offset = 0.0}) {
    _checkMutable();
    final previousStart = _entries.isEmpty ? 0.0 : _entries.last.start;
    return add(clip, at: _relativeStart(previousStart, offset));
  }

  /// Places [clip] relative to the end of the previously inserted clip.
  ///
  /// If the timeline has no previous clip, the reference end is zero.
  /// [offset] may be negative as long as the resolved start stays >= 0.
  MotionTimeline afterPrevious(MotionClip clip, {double offset = 0.0}) {
    _checkMutable();
    final previous = _entries.isEmpty ? null : _entries.last;
    final previousEnd = previous == null ? 0.0 : previous.start + previous.clip.span;
    return add(clip, at: _relativeStart(previousEnd, offset));
  }

  double _relativeStart(double anchor, double offset) {
    if (!offset.isFinite) {
      throw ArgumentError.value(offset, 'offset', 'Must be finite.');
    }
    final start = anchor + offset;
    if (start < 0.0) {
      throw ArgumentError.value(
        offset,
        'offset',
        'Resolved timeline start must be >= 0.',
      );
    }
    return start;
  }
}

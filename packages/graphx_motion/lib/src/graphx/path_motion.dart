import 'package:graphx_motion/motion.dart';
import 'package:graphx_paths/graphx_paths.dart';

final Expando<MotionProperty<double>> _progressByFollower = Expando<MotionProperty<double>>(
  'graphx.motion.pathFollower.progress',
);
const MotionPropertyKey _pathFollowerProgressKey = MotionPropertyKey(
  'GPathFollower.progress',
);

/// Motion integration kept on the Motion side of the dependency boundary.
extension GPathFollowerMotionExtension on GPathFollower {
  /// Stable reusable Motion channel for [GPathFollower.progress].
  MotionProperty<double> get motionProgress {
    final existing = _progressByFollower[this];
    if (existing != null) return existing;
    final property = MotionProperty<double>(
      read: () => progress,
      write: (value) => progress = value,
      owner: this,
      property: _pathFollowerProgressKey,
    );
    _progressByFollower[this] = property;
    return property;
  }
}

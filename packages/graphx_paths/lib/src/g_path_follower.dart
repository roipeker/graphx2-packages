// Copyright (c) 2026 GraphX by roipeker.

part of '../graphx_paths.dart';

/// Small behavior object that applies path progress to one [GNode].
///
/// [GPath] owns geometry only. This object owns target behavior and can be
/// driven directly, by Motion, or by another clock without coupling the path to
/// animation infrastructure.
final class GPathFollower {
  GPathFollower(
    this.path, {
    required this.target,
    double progress = 0.0,
    bool orientToPath = false,
    double normalOffset = 0.0,
    double rotationOffset = 0.0,
  }) : _progress = _checkedFinite(progress, 'progress').clamp(0.0, 1.0).toDouble(),
       _orientToPath = orientToPath,
       _normalOffset = _checkedFinite(normalOffset, 'normalOffset'),
       _rotationOffset = _checkedFinite(rotationOffset, 'rotationOffset') {
    apply();
  }

  final GPath path;
  final GNode target;
  final GPoint _point = GPoint();
  final GPoint _tangent = GPoint();

  double _progress;
  bool _orientToPath;
  double _normalOffset;
  double _rotationOffset;

  double get progress => _progress;
  set progress(double value) {
    final next = _checkedFinite(value, 'progress').clamp(0.0, 1.0).toDouble();
    if (next == _progress) return;
    _progress = next;
    apply();
  }

  bool get orientToPath => _orientToPath;
  set orientToPath(bool value) {
    if (value == _orientToPath) return;
    _orientToPath = value;
    apply();
  }

  double get normalOffset => _normalOffset;
  set normalOffset(double value) {
    final next = _checkedFinite(value, 'normalOffset');
    if (next == _normalOffset) return;
    _normalOffset = next;
    apply();
  }

  double get rotationOffset => _rotationOffset;
  set rotationOffset(double value) {
    final next = _checkedFinite(value, 'rotationOffset');
    if (next == _rotationOffset) return;
    _rotationOffset = next;
    if (_orientToPath) apply();
  }

  /// Re-applies the current progress, useful after mutating [path].
  void apply() {
    path.sampleAt(_progress, _point, _tangent);
    var x = _point.x;
    var y = _point.y;
    if (_normalOffset != 0.0) {
      x -= _tangent.y * _normalOffset;
      y += _tangent.x * _normalOffset;
    }
    target.setPosition(x, y);
    if (_orientToPath && (_tangent.x != 0.0 || _tangent.y != 0.0)) {
      target.rotation = math.atan2(_tangent.y, _tangent.x) + _rotationOffset;
    }
  }
}

double _checkedFinite(double value, String name) {
  if (!value.isFinite) throw ArgumentError.value(value, name, 'Must be finite.');
  return value;
}

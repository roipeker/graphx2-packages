// Copyright (c) 2026 GraphX by roipeker.

part of '../graphx_paths.dart';

/// Allocation-free combined position/tangent sampling for hot consumers.
extension GPathCombinedSampling on GPath {
  /// Writes position and unit tangent at normalized arc-length [progress].
  ///
  /// This is equivalent to calling [pointAt] and [tangentAt] at the same
  /// progress, but resolves the retained arc-length lookup only once. [point]
  /// and [tangent] are caller-owned outputs and must be distinct objects.
  /// Progress is clamped to `[0, 1]` using the same contour/seam semantics as
  /// the individual queries.
  void sampleAt(double progress, GPoint point, GPoint tangent) {
    assert(!identical(point, tangent), 'point and tangent outputs must be distinct');
    _sampleAtProgress(progress, point, tangent);
  }

  /// Writes position and unit tangent at absolute arc-length [distance].
  ///
  /// This is equivalent to calling [pointAtDistance] and [tangentAtDistance]
  /// for the same distance while performing one retained lookup. [point] and
  /// [tangent] are caller-owned outputs and must be distinct objects. Distance
  /// is clamped to the path length.
  void sampleAtDistance(double distance, GPoint point, GPoint tangent) {
    assert(!identical(point, tangent), 'point and tangent outputs must be distinct');
    _checkFinite(distance, 'distance');
    final prepared = _ensurePrepared();
    if (prepared.totalLength <= _pathEpsilon) {
      _writeFallbackPoint(prepared, point);
      tangent.setZero();
      return;
    }
    final d = distance.clamp(0.0, prepared.totalLength).toDouble();
    _sampleGlobalDistance(prepared, d, _cursor);
    _evalPoint(prepared, _cursor.segment, _cursor.t, point);
    _writeTangent(prepared, _cursor.segment, _cursor.t, tangent);
  }

  /// Writes position and tangent at [distance] within one contour.
  ///
  /// This is the combined hot-path equivalent of [pointAtContourDistance] plus
  /// [tangentAtContourDistance] and performs one contour-distance lookup.
  void sampleAtContourDistance(
    int contour,
    double distance,
    GPoint point,
    GPoint tangent,
  ) {
    assert(!identical(point, tangent), 'point and tangent outputs must be distinct');
    _checkFinite(distance, 'distance');
    final prepared = _ensurePrepared();
    _checkContourIndex(contour, prepared.contourCount);
    final length = prepared.contourLengths[contour];
    if (length <= _pathEpsilon) {
      _writeContourFallbackPoint(prepared, contour, point);
      tangent.setZero();
      return;
    }
    final local = distance.clamp(0.0, length).toDouble();
    final global = prepared.contourStartDistances[contour] + local;
    _sampleContourDistance(prepared, contour, global, _cursor);
    _evalPoint(prepared, _cursor.segment, _cursor.t, point);
    _writeTangent(prepared, _cursor.segment, _cursor.t, tangent);
  }
}

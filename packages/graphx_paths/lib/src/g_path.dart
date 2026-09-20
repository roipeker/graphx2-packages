// Copyright (c) 2026 GraphX by roipeker.

part of '../graphx_paths.dart';

const int _verbMove = 0;
const int _verbLine = 1;
const int _verbQuadratic = 2;
const int _verbCubic = 3;
const int _verbClose = 4;

const int _segmentLine = 0;
const int _segmentQuadratic = 1;
const int _segmentCubic = 2;

const double _pathEpsilon = 1e-12;
const int _maxSubdivisionDepth = 18;

/// Retained 2D geometric path with cached arc-length sampling data.
///
/// [pointAt], [tangentAt], and [normalAt] use normalized arc-length progress,
/// not raw Bezier parameter space. The first query after geometry mutation
/// prepares retained lookup tables; repeated queries reuse that work.
///
/// Convenience queries allocate a [GPoint] only when [out] is omitted. Pass a
/// reusable output point in animation and simulation hot paths.
final class GPath {
  GPath({this.tolerance = 0.25}) {
    if (!tolerance.isFinite || tolerance <= 0.0) {
      throw ArgumentError.value(tolerance, 'tolerance', 'Must be finite and > 0.');
    }
  }

  /// Creates a path that passes through every supplied waypoint in order.
  ///
  /// Three or more points use a centripetal Catmull-Rom authoring spline that is
  /// converted immediately to the same retained cubic Bezier representation as
  /// [cubicTo]. Two points form a straight line; one point forms a move-only
  /// contour; an empty list produces an empty path. [closed] joins the final
  /// waypoint back to the first with a continuous spline seam when possible.
  factory GPath.spline(
    List<GPoint> points, {
    bool closed = false,
    double tolerance = 0.25,
  }) => _buildSplinePath(points, closed: closed, tolerance: tolerance);

  /// Fits sampled/noisy points with a compact sequence of cubic Bezier curves.
  ///
  /// [tolerance] is the maximum accepted Euclidean error from each retained
  /// input sample to a point on its fitted cubic. Endpoints are preserved.
  /// Consecutive and numerically near-duplicate samples are ignored. When
  /// [closed] is true, the samples are treated as a cyclic contour and the seam
  /// uses a shared cyclic tangent rather than unrelated open-path endpoint
  /// tangents. The result is ordinary retained [GPath] geometry; no fitting
  /// state remains after construction.
  ///
  /// [pathTolerance] controls this path's later retained arc-length preparation
  /// and is independent from the fitting tolerance.
  factory GPath.fit(
    List<GPoint> points, {
    bool closed = false,
    double tolerance = 0.75,
    double pathTolerance = 0.25,
  }) => _fitSampledPath(
    points,
    closed: closed,
    fitTolerance: tolerance,
    pathTolerance: pathTolerance,
  );

  /// Reduces sampled points using tolerance-based Ramer-Douglas-Peucker.
  ///
  /// Endpoints are preserved and consecutive duplicate points are removed.
  /// This operates on sampled points, not on existing Bezier path geometry.
  static List<GPoint> simplifyPoints(
    List<GPoint> points, {
    double tolerance = 1.0,
  }) => _simplifySampledPoints(points, tolerance: tolerance);

  /// Local adaptive-subdivision threshold used while preparing curve lookup data.
  ///
  /// A curve leaf is accepted when `controlPolygonLength - chordLength` is at
  /// most this value. This is a local criterion, not a global Hausdorff-error
  /// guarantee. Smaller values retain denser lookup data.
  final double tolerance;

  final List<int> _verbs = <int>[];
  final List<double> _values = <double>[];

  _PreparedPath? _prepared;
  int _geometryVersion = 0;

  bool _hasCurrent = false;
  bool _contourOpen = false;
  double _currentX = 0.0;
  double _currentY = 0.0;
  double _contourStartX = 0.0;
  double _contourStartY = 0.0;

  final _SampleCursor _cursor = _SampleCursor();
  final GPoint _scratchA = GPoint();
  final GPoint _scratchB = GPoint();
  final GPoint _scratchC = GPoint();

  int get geometryVersion => _geometryVersion;
  bool get isEmpty => _verbs.isEmpty;
  int get contourCount => _ensurePrepared().contourCount;
  int get segmentCount => _ensurePrepared().segmentCount;
  double get length => _ensurePrepared().totalLength;

  GBounds get bounds {
    final result = GBounds.empty();
    boundsInto(result);
    return result;
  }

  void boundsInto(GBounds out) => out.copyFrom(_ensurePrepared().bounds);

  GPath moveTo(double x, double y) {
    _checkPoint(x, y);
    _verbs.add(_verbMove);
    _values.add(x);
    _values.add(y);
    _currentX = _contourStartX = x;
    _currentY = _contourStartY = y;
    _hasCurrent = true;
    _contourOpen = true;
    _invalidate();
    return this;
  }

  GPath lineTo(double x, double y) {
    _checkPoint(x, y);
    _ensureOpenContour();
    _verbs.add(_verbLine);
    _values.add(x);
    _values.add(y);
    _currentX = x;
    _currentY = y;
    _invalidate();
    return this;
  }

  GPath quadraticTo(double controlX, double controlY, double x, double y) {
    _checkPoint(controlX, controlY);
    _checkPoint(x, y);
    _ensureOpenContour();
    _verbs.add(_verbQuadratic);
    _values.add(controlX);
    _values.add(controlY);
    _values.add(x);
    _values.add(y);
    _currentX = x;
    _currentY = y;
    _invalidate();
    return this;
  }

  GPath cubicTo(
    double controlX1,
    double controlY1,
    double controlX2,
    double controlY2,
    double x,
    double y,
  ) {
    _checkPoint(controlX1, controlY1);
    _checkPoint(controlX2, controlY2);
    _checkPoint(x, y);
    _ensureOpenContour();
    _verbs.add(_verbCubic);
    _values.add(controlX1);
    _values.add(controlY1);
    _values.add(controlX2);
    _values.add(controlY2);
    _values.add(x);
    _values.add(y);
    _currentX = x;
    _currentY = y;
    _invalidate();
    return this;
  }

  /// Closes the current contour. Calling this without an open contour is a no-op.
  GPath close() {
    if (!_contourOpen) return this;
    _verbs.add(_verbClose);
    _currentX = _contourStartX;
    _currentY = _contourStartY;
    _contourOpen = false;
    _hasCurrent = true;
    _invalidate();
    return this;
  }

  GPath clear() {
    if (_verbs.isEmpty) return this;
    _verbs.clear();
    _values.clear();
    _hasCurrent = false;
    _contourOpen = false;
    _currentX = _currentY = 0.0;
    _contourStartX = _contourStartY = 0.0;
    _invalidate();
    return this;
  }

  double contourLength(int contour) {
    final prepared = _ensurePrepared();
    _checkContourIndex(contour, prepared.contourCount);
    return prepared.contourLengths[contour];
  }

  /// Position at normalized arc-length [progress] across all contours.
  ///
  /// Progress is clamped. Move gaps contribute no length. At an exact boundary
  /// between contours, the following contour owns the boundary. If the final
  /// contour is closed, progress 1 resolves to its seam/start.
  GPoint pointAt(double progress, [GPoint? out]) {
    _checkFinite(progress, 'progress');
    final prepared = _ensurePrepared();
    final result = out ?? GPoint();
    if (prepared.totalLength <= _pathEpsilon) {
      _writeFallbackPoint(prepared, result);
      return result;
    }
    final p = progress.clamp(0.0, 1.0).toDouble();
    _sampleGlobalDistance(prepared, p * prepared.totalLength, _cursor);
    _evalPoint(prepared, _cursor.segment, _cursor.t, result);
    return result;
  }

  GPoint pointAtDistance(double distance, [GPoint? out]) {
    _checkFinite(distance, 'distance');
    final prepared = _ensurePrepared();
    final result = out ?? GPoint();
    if (prepared.totalLength <= _pathEpsilon) {
      _writeFallbackPoint(prepared, result);
      return result;
    }
    final d = distance.clamp(0.0, prepared.totalLength).toDouble();
    _sampleGlobalDistance(prepared, d, _cursor);
    _evalPoint(prepared, _cursor.segment, _cursor.t, result);
    return result;
  }

  GPoint tangentAt(double progress, [GPoint? out]) {
    _checkFinite(progress, 'progress');
    final prepared = _ensurePrepared();
    final result = out ?? GPoint();
    if (prepared.totalLength <= _pathEpsilon) {
      result.setZero();
      return result;
    }
    final p = progress.clamp(0.0, 1.0).toDouble();
    _sampleGlobalDistance(prepared, p * prepared.totalLength, _cursor);
    _writeTangent(prepared, _cursor.segment, _cursor.t, result);
    return result;
  }

  GPoint tangentAtDistance(double distance, [GPoint? out]) {
    _checkFinite(distance, 'distance');
    final prepared = _ensurePrepared();
    final result = out ?? GPoint();
    if (prepared.totalLength <= _pathEpsilon) {
      result.setZero();
      return result;
    }
    final d = distance.clamp(0.0, prepared.totalLength).toDouble();
    _sampleGlobalDistance(prepared, d, _cursor);
    _writeTangent(prepared, _cursor.segment, _cursor.t, result);
    return result;
  }

  GPoint normalAt(double progress, [GPoint? out]) {
    final result = tangentAt(progress, out);
    final x = result.x;
    result.x = -result.y;
    result.y = x;
    return result;
  }

  GPoint normalAtDistance(double distance, [GPoint? out]) {
    final result = tangentAtDistance(distance, out);
    final x = result.x;
    result.x = -result.y;
    result.y = x;
    return result;
  }

  GPoint pointAtContourDistance(int contour, double distance, [GPoint? out]) {
    _checkFinite(distance, 'distance');
    final prepared = _ensurePrepared();
    _checkContourIndex(contour, prepared.contourCount);
    final result = out ?? GPoint();
    final contourLength = prepared.contourLengths[contour];
    if (contourLength <= _pathEpsilon) {
      _writeContourFallbackPoint(prepared, contour, result);
      return result;
    }
    final local = distance.clamp(0.0, contourLength).toDouble();
    final global = prepared.contourStartDistances[contour] + local;
    _sampleContourDistance(prepared, contour, global, _cursor);
    _evalPoint(prepared, _cursor.segment, _cursor.t, result);
    return result;
  }

  GPoint tangentAtContourDistance(int contour, double distance, [GPoint? out]) {
    _checkFinite(distance, 'distance');
    final prepared = _ensurePrepared();
    _checkContourIndex(contour, prepared.contourCount);
    final result = out ?? GPoint();
    final contourLength = prepared.contourLengths[contour];
    if (contourLength <= _pathEpsilon) {
      result.setZero();
      return result;
    }
    final local = distance.clamp(0.0, contourLength).toDouble();
    final global = prepared.contourStartDistances[contour] + local;
    _sampleContourDistance(prepared, contour, global, _cursor);
    _writeTangent(prepared, _cursor.segment, _cursor.t, result);
    return result;
  }

  /// Closest point on the retained adaptive polyline, refined on the winning
  /// source segment with bounded Newton iterations.
  GPoint closestPoint(double x, double y, [GPoint? out]) {
    _checkPoint(x, y);
    final prepared = _ensurePrepared();
    final result = out ?? GPoint();
    if (prepared.segmentCount == 0 || prepared.totalLength <= _pathEpsilon) {
      _writeFallbackPoint(prepared, result);
      return result;
    }

    var bestDistanceSquared = double.infinity;
    var bestSegment = -1;
    var bestT = 0.0;
    var bestLo = 0.0;
    var bestHi = 1.0;

    for (var segment = 0; segment < prepared.segmentCount; ++segment) {
      final first = prepared.lutOffsets[segment];
      final last = prepared.lutOffsets[segment + 1] - 1;
      for (var sample = first; sample < last; ++sample) {
        final a = sample * 4;
        final b = (sample + 1) * 4;
        final ax = prepared.samples[a + 2];
        final ay = prepared.samples[a + 3];
        final bx = prepared.samples[b + 2];
        final by = prepared.samples[b + 3];
        final dx = bx - ax;
        final dy = by - ay;
        final edgeLengthSquared = dx * dx + dy * dy;
        var u = 0.0;
        if (edgeLengthSquared > _pathEpsilon) {
          u = ((x - ax) * dx + (y - ay) * dy) / edgeLengthSquared;
          u = u.clamp(0.0, 1.0).toDouble();
        }
        final px = ax + dx * u;
        final py = ay + dy * u;
        final qx = px - x;
        final qy = py - y;
        final distanceSquared = qx * qx + qy * qy;
        if (distanceSquared < bestDistanceSquared) {
          bestDistanceSquared = distanceSquared;
          bestSegment = segment;
          bestLo = prepared.samples[a];
          bestHi = prepared.samples[b];
          bestT = bestLo + (bestHi - bestLo) * u;
        }
      }
    }

    if (bestSegment < 0) {
      _writeFallbackPoint(prepared, result);
      return result;
    }

    var t = bestT;
    for (var i = 0; i < 5; ++i) {
      _evalPoint(prepared, bestSegment, t, _scratchA);
      _evalDerivative(prepared, bestSegment, t, _scratchB);
      _evalSecondDerivative(prepared, bestSegment, t, _scratchC);
      final qx = _scratchA.x - x;
      final qy = _scratchA.y - y;
      final numerator = qx * _scratchB.x + qy * _scratchB.y;
      final denominator =
          _scratchB.x * _scratchB.x +
          _scratchB.y * _scratchB.y +
          qx * _scratchC.x +
          qy * _scratchC.y;
      if (denominator.abs() <= _pathEpsilon || !denominator.isFinite) break;
      final next = (t - numerator / denominator).clamp(bestLo, bestHi).toDouble();
      if ((next - t).abs() <= 1e-10) {
        t = next;
        break;
      }
      t = next;
    }
    _evalPoint(prepared, bestSegment, t, result);
    return result;
  }

  void _sampleAtProgress(double progress, GPoint point, GPoint tangent) {
    _checkFinite(progress, 'progress');
    final prepared = _ensurePrepared();
    if (prepared.totalLength <= _pathEpsilon) {
      _writeFallbackPoint(prepared, point);
      tangent.setZero();
      return;
    }
    final p = progress.clamp(0.0, 1.0).toDouble();
    _sampleGlobalDistance(prepared, p * prepared.totalLength, _cursor);
    _evalPoint(prepared, _cursor.segment, _cursor.t, point);
    _writeTangent(prepared, _cursor.segment, _cursor.t, tangent);
  }

  void _ensureOpenContour() {
    if (_contourOpen) return;
    final x = _hasCurrent ? _currentX : 0.0;
    final y = _hasCurrent ? _currentY : 0.0;
    _verbs.add(_verbMove);
    _values.add(x);
    _values.add(y);
    _contourStartX = _currentX = x;
    _contourStartY = _currentY = y;
    _hasCurrent = true;
    _contourOpen = true;
  }

  void _invalidate() {
    _geometryVersion++;
    _prepared = null;
  }

  _PreparedPath _ensurePrepared() => _prepared ??= _prepare();

  _PreparedPath _prepare() {
    final segments = <_BuildSegment>[];
    final contours = <_BuildContour>[];
    final bounds = GBounds.empty();
    var valueIndex = 0;
    var currentX = 0.0;
    var currentY = 0.0;
    var startX = 0.0;
    var startY = 0.0;
    var contour = -1;

    void addSegment(_BuildSegment segment) {
      segments.add(segment);
      final item = contours[segment.contour];
      item.lastSegment = segments.length - 1;
      if (item.firstSegment < 0) item.firstSegment = item.lastSegment;
    }

    for (final verb in _verbs) {
      switch (verb) {
        case _verbMove:
          currentX = _values[valueIndex++];
          currentY = _values[valueIndex++];
          startX = currentX;
          startY = currentY;
          contour++;
          contours.add(_BuildContour(currentX, currentY));
          bounds.includePoint(currentX, currentY);
          break;
        case _verbLine:
          final x = _values[valueIndex++];
          final y = _values[valueIndex++];
          addSegment(_BuildSegment.line(contour, currentX, currentY, x, y));
          bounds.includePoint(currentX, currentY);
          bounds.includePoint(x, y);
          currentX = x;
          currentY = y;
          break;
        case _verbQuadratic:
          final cx = _values[valueIndex++];
          final cy = _values[valueIndex++];
          final x = _values[valueIndex++];
          final y = _values[valueIndex++];
          addSegment(_BuildSegment.quadratic(contour, currentX, currentY, cx, cy, x, y));
          _includeQuadraticBounds(bounds, currentX, currentY, cx, cy, x, y);
          currentX = x;
          currentY = y;
          break;
        case _verbCubic:
          final c1x = _values[valueIndex++];
          final c1y = _values[valueIndex++];
          final c2x = _values[valueIndex++];
          final c2y = _values[valueIndex++];
          final x = _values[valueIndex++];
          final y = _values[valueIndex++];
          addSegment(
            _BuildSegment.cubic(
              contour,
              currentX,
              currentY,
              c1x,
              c1y,
              c2x,
              c2y,
              x,
              y,
            ),
          );
          _includeCubicBounds(bounds, currentX, currentY, c1x, c1y, c2x, c2y, x, y);
          currentX = x;
          currentY = y;
          break;
        case _verbClose:
          if (contour < 0) break;
          addSegment(_BuildSegment.line(contour, currentX, currentY, startX, startY));
          contours[contour].closed = true;
          bounds.includePoint(currentX, currentY);
          bounds.includePoint(startX, startY);
          currentX = startX;
          currentY = startY;
          break;
      }
    }

    final segmentCount = segments.length;
    final coords = Float64List(segmentCount * 8);
    final kinds = Int32List(segmentCount);
    final segmentContours = Int32List(segmentCount);
    final distances = Float64List(segmentCount + 1);
    final lutOffsets = Int32List(segmentCount + 1);
    final sampleValues = <double>[];
    var totalLength = 0.0;

    for (var i = 0; i < segmentCount; ++i) {
      final segment = segments[i];
      kinds[i] = segment.kind;
      segmentContours[i] = segment.contour;
      final base = i * 8;
      for (var j = 0; j < 8; ++j) {
        coords[base + j] = segment.coords[j];
      }
      distances[i] = totalLength;
      lutOffsets[i] = sampleValues.length ~/ 4;
      final segmentLength = _appendSegmentSamples(segment, tolerance, sampleValues);
      totalLength += segmentLength;
      distances[i + 1] = totalLength;
      lutOffsets[i + 1] = sampleValues.length ~/ 4;
      contours[segment.contour].length += segmentLength;
    }

    final contourCount = contours.length;
    final contourLengths = Float64List(contourCount);
    final contourStartDistances = Float64List(contourCount);
    final contourEndDistances = Float64List(contourCount);
    final contourFirstSegments = Int32List(contourCount);
    final contourLastSegments = Int32List(contourCount);
    final contourClosed = Uint8List(contourCount);
    final contourStarts = Float64List(contourCount * 2);
    var contourDistance = 0.0;
    for (var i = 0; i < contourCount; ++i) {
      final item = contours[i];
      contourLengths[i] = item.length;
      contourStartDistances[i] = contourDistance;
      contourDistance += item.length;
      contourEndDistances[i] = contourDistance;
      contourFirstSegments[i] = item.firstSegment;
      contourLastSegments[i] = item.lastSegment;
      contourClosed[i] = item.closed ? 1 : 0;
      contourStarts[i * 2] = item.startX;
      contourStarts[i * 2 + 1] = item.startY;
    }

    return _PreparedPath(
      kinds: kinds,
      segmentContours: segmentContours,
      coords: coords,
      segmentDistances: distances,
      lutOffsets: lutOffsets,
      samples: Float64List.fromList(sampleValues),
      contourLengths: contourLengths,
      contourStartDistances: contourStartDistances,
      contourEndDistances: contourEndDistances,
      contourFirstSegments: contourFirstSegments,
      contourLastSegments: contourLastSegments,
      contourClosed: contourClosed,
      contourStarts: contourStarts,
      bounds: bounds,
      totalLength: totalLength,
    );
  }

  void _sampleGlobalDistance(_PreparedPath prepared, double distance, _SampleCursor out) {
    if (distance >= prepared.totalLength && prepared.contourCount > 0) {
      final lastContour = prepared.contourCount - 1;
      if (prepared.contourClosed[lastContour] != 0 &&
          prepared.contourLengths[lastContour] > _pathEpsilon) {
        _sampleContourDistance(
          prepared,
          lastContour,
          prepared.contourStartDistances[lastContour],
          out,
        );
        return;
      }
    }
    var low = 0;
    var high = prepared.segmentCount - 1;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (distance < prepared.segmentDistances[mid + 1]) {
        high = mid;
      } else {
        low = mid + 1;
      }
    }
    _resolveSegmentDistance(prepared, low, distance, out);
  }

  void _sampleContourDistance(
    _PreparedPath prepared,
    int contour,
    double globalDistance,
    _SampleCursor out,
  ) {
    final first = prepared.contourFirstSegments[contour];
    final last = prepared.contourLastSegments[contour];
    if (first < 0 || last < first) {
      out.segment = -1;
      out.t = 0.0;
      return;
    }
    var distance = globalDistance;
    if (distance >= prepared.contourEndDistances[contour] && prepared.contourClosed[contour] != 0) {
      distance = prepared.contourStartDistances[contour];
    }
    var low = first;
    var high = last;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (distance < prepared.segmentDistances[mid + 1]) {
        high = mid;
      } else {
        low = mid + 1;
      }
    }
    _resolveSegmentDistance(prepared, low, distance, out);
  }

  void _resolveSegmentDistance(
    _PreparedPath prepared,
    int segment,
    double globalDistance,
    _SampleCursor out,
  ) {
    final segmentStart = prepared.segmentDistances[segment];
    final segmentLength = prepared.segmentDistances[segment + 1] - segmentStart;
    if (segmentLength <= _pathEpsilon) {
      out.segment = segment;
      out.t = 0.0;
      return;
    }
    final localDistance = (globalDistance - segmentStart).clamp(0.0, segmentLength).toDouble();
    if (localDistance <= 0.0) {
      out.segment = segment;
      out.t = 0.0;
      return;
    }
    if (localDistance >= segmentLength) {
      out.segment = segment;
      out.t = 1.0;
      return;
    }

    final first = prepared.lutOffsets[segment];
    final last = prepared.lutOffsets[segment + 1] - 1;
    var low = first + 1;
    var high = last;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (localDistance <= prepared.samples[mid * 4 + 1]) {
        high = mid;
      } else {
        low = mid + 1;
      }
    }
    final upper = low;
    final lower = upper - 1;
    final lowerBase = lower * 4;
    final upperBase = upper * 4;
    final d0 = prepared.samples[lowerBase + 1];
    final d1 = prepared.samples[upperBase + 1];
    final t0 = prepared.samples[lowerBase];
    final t1 = prepared.samples[upperBase];
    final ratio = d1 - d0 <= _pathEpsilon ? 0.0 : (localDistance - d0) / (d1 - d0);
    out.segment = segment;
    out.t = t0 + (t1 - t0) * ratio;
  }

  void _writeTangent(_PreparedPath prepared, int segment, double t, GPoint out) {
    if (segment < 0) {
      out.setZero();
      return;
    }
    _evalDerivative(prepared, segment, t, out);
    var lengthSquared = out.x * out.x + out.y * out.y;
    if (lengthSquared <= _pathEpsilon) {
      final dt = math.max(1e-6, tolerance * 1e-5);
      final t0 = math.max(0.0, t - dt);
      final t1 = math.min(1.0, t + dt);
      _evalPoint(prepared, segment, t0, _scratchA);
      _evalPoint(prepared, segment, t1, _scratchB);
      out.x = _scratchB.x - _scratchA.x;
      out.y = _scratchB.y - _scratchA.y;
      lengthSquared = out.x * out.x + out.y * out.y;
    }
    if (lengthSquared <= _pathEpsilon) {
      _fallbackSegmentDirection(prepared, segment, out);
      lengthSquared = out.x * out.x + out.y * out.y;
    }
    if (lengthSquared <= _pathEpsilon) {
      out.setZero();
      return;
    }
    final inv = 1.0 / math.sqrt(lengthSquared);
    out.x *= inv;
    out.y *= inv;
  }

  void _fallbackSegmentDirection(_PreparedPath prepared, int segment, GPoint out) {
    final contour = prepared.segmentContours[segment];
    final first = prepared.contourFirstSegments[contour];
    final last = prepared.contourLastSegments[contour];
    for (var offset = 0; offset <= last - first; ++offset) {
      final forward = segment + offset;
      if (forward <= last && _segmentChord(prepared, forward, out)) return;
      if (offset == 0) continue;
      final backward = segment - offset;
      if (backward >= first && _segmentChord(prepared, backward, out)) return;
    }
    out.setZero();
  }

  bool _segmentChord(_PreparedPath prepared, int segment, GPoint out) {
    final base = segment * 8;
    final dx = prepared.coords[base + 6] - prepared.coords[base];
    final dy = prepared.coords[base + 7] - prepared.coords[base + 1];
    if (dx * dx + dy * dy <= _pathEpsilon) return false;
    out.x = dx;
    out.y = dy;
    return true;
  }

  void _evalPoint(_PreparedPath prepared, int segment, double t, GPoint out) {
    final base = segment * 8;
    final x0 = prepared.coords[base];
    final y0 = prepared.coords[base + 1];
    final x1 = prepared.coords[base + 6];
    final y1 = prepared.coords[base + 7];
    switch (prepared.kinds[segment]) {
      case _segmentLine:
        out.x = x0 + (x1 - x0) * t;
        out.y = y0 + (y1 - y0) * t;
        break;
      case _segmentQuadratic:
        final cx = prepared.coords[base + 2];
        final cy = prepared.coords[base + 3];
        final u = 1.0 - t;
        out.x = u * u * x0 + 2.0 * u * t * cx + t * t * x1;
        out.y = u * u * y0 + 2.0 * u * t * cy + t * t * y1;
        break;
      case _segmentCubic:
        final c1x = prepared.coords[base + 2];
        final c1y = prepared.coords[base + 3];
        final c2x = prepared.coords[base + 4];
        final c2y = prepared.coords[base + 5];
        final u = 1.0 - t;
        final uu = u * u;
        final tt = t * t;
        out.x = uu * u * x0 + 3.0 * uu * t * c1x + 3.0 * u * tt * c2x + tt * t * x1;
        out.y = uu * u * y0 + 3.0 * uu * t * c1y + 3.0 * u * tt * c2y + tt * t * y1;
        break;
    }
  }

  void _evalDerivative(_PreparedPath prepared, int segment, double t, GPoint out) {
    final base = segment * 8;
    final x0 = prepared.coords[base];
    final y0 = prepared.coords[base + 1];
    final x1 = prepared.coords[base + 6];
    final y1 = prepared.coords[base + 7];
    switch (prepared.kinds[segment]) {
      case _segmentLine:
        out.x = x1 - x0;
        out.y = y1 - y0;
        break;
      case _segmentQuadratic:
        final cx = prepared.coords[base + 2];
        final cy = prepared.coords[base + 3];
        final u = 1.0 - t;
        out.x = 2.0 * (u * (cx - x0) + t * (x1 - cx));
        out.y = 2.0 * (u * (cy - y0) + t * (y1 - cy));
        break;
      case _segmentCubic:
        final c1x = prepared.coords[base + 2];
        final c1y = prepared.coords[base + 3];
        final c2x = prepared.coords[base + 4];
        final c2y = prepared.coords[base + 5];
        final u = 1.0 - t;
        out.x = 3.0 * u * u * (c1x - x0) + 6.0 * u * t * (c2x - c1x) + 3.0 * t * t * (x1 - c2x);
        out.y = 3.0 * u * u * (c1y - y0) + 6.0 * u * t * (c2y - c1y) + 3.0 * t * t * (y1 - c2y);
        break;
    }
  }

  void _evalSecondDerivative(_PreparedPath prepared, int segment, double t, GPoint out) {
    final base = segment * 8;
    final x0 = prepared.coords[base];
    final y0 = prepared.coords[base + 1];
    final x1 = prepared.coords[base + 6];
    final y1 = prepared.coords[base + 7];
    switch (prepared.kinds[segment]) {
      case _segmentLine:
        out.setZero();
        break;
      case _segmentQuadratic:
        final cx = prepared.coords[base + 2];
        final cy = prepared.coords[base + 3];
        out.x = 2.0 * (x1 - 2.0 * cx + x0);
        out.y = 2.0 * (y1 - 2.0 * cy + y0);
        break;
      case _segmentCubic:
        final c1x = prepared.coords[base + 2];
        final c1y = prepared.coords[base + 3];
        final c2x = prepared.coords[base + 4];
        final c2y = prepared.coords[base + 5];
        final u = 1.0 - t;
        out.x = 6.0 * u * (c2x - 2.0 * c1x + x0) + 6.0 * t * (x1 - 2.0 * c2x + c1x);
        out.y = 6.0 * u * (c2y - 2.0 * c1y + y0) + 6.0 * t * (y1 - 2.0 * c2y + c1y);
        break;
    }
  }

  void _writeFallbackPoint(_PreparedPath prepared, GPoint out) {
    if (prepared.contourCount == 0) {
      out.setZero();
      return;
    }
    out.set(prepared.contourStarts[0], prepared.contourStarts[1]);
  }

  void _writeContourFallbackPoint(_PreparedPath prepared, int contour, GPoint out) {
    final base = contour * 2;
    out.set(prepared.contourStarts[base], prepared.contourStarts[base + 1]);
  }
}

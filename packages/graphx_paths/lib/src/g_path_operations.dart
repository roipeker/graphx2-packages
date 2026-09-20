// Copyright (c) 2026 GraphX by roipeker.

part of '../graphx_paths.dart';

/// Read-only polyline snapshot produced from a [GPath]'s retained adaptive
/// subdivision data.
///
/// The snapshot owns compact packed coordinates. It remains valid if the source
/// path later mutates. Closed contours do not repeat their seam point; use
/// [isContourClosed] to determine whether the last point connects to the first.
final class GPathFlattened {
  GPathFlattened._(
    this._points,
    this._contourOffsets,
    this._contourClosed, {
    required this.sourceGeometryVersion,
    required this.tolerance,
  });

  final Float64List _points;
  final Int32List _contourOffsets;
  final Uint8List _contourClosed;

  /// Geometry version of the source path when this snapshot was created.
  final int sourceGeometryVersion;

  /// Adaptive-subdivision tolerance used by the source path.
  final double tolerance;

  int get pointCount => _points.length >> 1;
  int get contourCount => _contourClosed.length;

  double xAt(int index) {
    _checkPointIndex(index);
    return _points[index << 1];
  }

  double yAt(int index) {
    _checkPointIndex(index);
    return _points[(index << 1) + 1];
  }

  GPoint pointAtIndex(int index, [GPoint? out]) {
    _checkPointIndex(index);
    final result = out ?? GPoint();
    final base = index << 1;
    result.x = _points[base];
    result.y = _points[base + 1];
    return result;
  }

  int contourStartIndex(int contour) {
    _checkContour(contour);
    return _contourOffsets[contour];
  }

  int contourEndIndex(int contour) {
    _checkContour(contour);
    return _contourOffsets[contour + 1];
  }

  int contourPointCount(int contour) => contourEndIndex(contour) - contourStartIndex(contour);

  bool isContourClosed(int contour) {
    _checkContour(contour);
    return _contourClosed[contour] != 0;
  }

  void _checkPointIndex(int index) {
    if (index < 0 || index >= pointCount) {
      throw RangeError.index(index, this, 'index', null, pointCount);
    }
  }

  void _checkContour(int contour) {
    if (contour < 0 || contour >= contourCount) {
      throw RangeError.index(contour, this, 'contour', null, contourCount);
    }
  }
}

/// Exact geometry operations layered on the retained [GPath] representation.
extension GPathGeometryOperations on GPath {
  /// Extracts normalized arc-length progress `[start, end]` into a new path.
  ///
  /// Progress is clamped to `[0, 1]` and [start] must not exceed [end]. The
  /// distance-to-parameter mapping follows this path's retained arc-length
  /// tolerance; once source parameters are resolved, line/quadratic/cubic
  /// pieces are split analytically without flattening.
  ///
  /// Move gaps remain move gaps. A fully selected closed contour stays closed;
  /// a partially selected closed contour becomes an open path section.
  GPath subpath(double start, double end) {
    _checkFinite(start, 'start');
    _checkFinite(end, 'end');
    if (start > end) {
      throw ArgumentError.value(start, 'start', 'Must be <= end.');
    }
    final prepared = _ensurePrepared();
    final s = start.clamp(0.0, 1.0).toDouble();
    final e = end.clamp(0.0, 1.0).toDouble();
    return _subpathByDistancePrepared(
      this,
      prepared,
      s * prepared.totalLength,
      e * prepared.totalLength,
    );
  }

  /// Extracts the arc-length distance range `[startDistance, endDistance]`.
  ///
  /// Distances are clamped to the path length and [startDistance] must not
  /// exceed [endDistance]. See [subpath] for contour and numerical semantics.
  GPath subpathByDistance(double startDistance, double endDistance) {
    _checkFinite(startDistance, 'startDistance');
    _checkFinite(endDistance, 'endDistance');
    if (startDistance > endDistance) {
      throw ArgumentError.value(
        startDistance,
        'startDistance',
        'Must be <= endDistance.',
      );
    }
    final prepared = _ensurePrepared();
    final s = startDistance.clamp(0.0, prepared.totalLength).toDouble();
    final e = endDistance.clamp(0.0, prepared.totalLength).toDouble();
    return _subpathByDistancePrepared(this, prepared, s, e);
  }

  /// Splits this path at normalized arc-length [progress].
  ///
  /// The source path is unchanged. `before` is equivalent to
  /// `subpath(0, progress)` and `after` to `subpath(progress, 1)`.
  ({GPath before, GPath after}) splitAt(double progress) {
    _checkFinite(progress, 'progress');
    final p = progress.clamp(0.0, 1.0).toDouble();
    return (before: subpath(0.0, p), after: subpath(p, 1.0));
  }

  /// Reverses traversal direction in place and returns this path.
  ///
  /// Contour order and segment direction are both reversed. Open contours start
  /// at their former end. Closed contours remain closed; their seam moves to the
  /// authored endpoint immediately preceding the original `close()` edge so the
  /// closing edge remains represented by `close()` rather than an extra segment.
  GPath reverse() {
    final prepared = _ensurePrepared();
    final reversed = GPath(tolerance: tolerance);

    for (var contour = prepared.contourCount - 1; contour >= 0; --contour) {
      final first = prepared.contourFirstSegments[contour];
      final last = prepared.contourLastSegments[contour];
      final closed = prepared.contourClosed[contour] != 0;

      if (first < 0 || last < first) {
        final base = contour << 1;
        reversed.moveTo(
          prepared.contourStarts[base],
          prepared.contourStarts[base + 1],
        );
        if (closed) reversed.close();
        continue;
      }

      if (closed) {
        // The final prepared segment is the line materialized by close(). Start
        // at its source point and reverse only authored segments; close() then
        // recreates the reversed closing edge exactly.
        final closeBase = last * 8;
        reversed.moveTo(
          prepared.coords[closeBase],
          prepared.coords[closeBase + 1],
        );
        for (var segment = last - 1; segment >= first; --segment) {
          _appendReversedSegment(prepared, segment, reversed);
        }
        reversed.close();
      } else {
        final endBase = last * 8;
        reversed.moveTo(
          prepared.coords[endBase + 6],
          prepared.coords[endBase + 7],
        );
        for (var segment = last; segment >= first; --segment) {
          _appendReversedSegment(prepared, segment, reversed);
        }
      }
    }

    _replaceGeometry(this, reversed);
    return this;
  }

  /// Creates a compact, read-only polyline snapshot using the path's already
  /// retained adaptive subdivision data.
  ///
  /// This does not re-subdivide curves. The returned snapshot owns its packed
  /// coordinates and therefore remains valid after later path mutation.
  GPathFlattened flatten() => _flattenPath(this, _ensurePrepared());
}

GPath _subpathByDistancePrepared(
  GPath source,
  _PreparedPath prepared,
  double startDistance,
  double endDistance,
) {
  final out = GPath(tolerance: source.tolerance);

  if (prepared.contourCount == 0) {
    if ((endDistance - startDistance).abs() <= _pathEpsilon) {
      out.moveTo(0.0, 0.0);
    }
    return out;
  }

  if (prepared.totalLength <= _pathEpsilon || (endDistance - startDistance).abs() <= _pathEpsilon) {
    source.pointAtDistance(startDistance, source._scratchA);
    out.moveTo(source._scratchA.x, source._scratchA.y);
    return out;
  }

  for (var contour = 0; contour < prepared.contourCount; ++contour) {
    final contourStart = prepared.contourStartDistances[contour];
    final contourEnd = prepared.contourEndDistances[contour];
    final contourLength = prepared.contourLengths[contour];

    if (contourLength <= _pathEpsilon) {
      if (startDistance <= contourStart && endDistance >= contourEnd) {
        final base = contour << 1;
        out.moveTo(
          prepared.contourStarts[base],
          prepared.contourStarts[base + 1],
        );
        if (prepared.contourClosed[contour] != 0) out.close();
      }
      continue;
    }

    if (endDistance <= contourStart || startDistance >= contourEnd) continue;

    final localStart = math.max(startDistance, contourStart);
    final localEnd = math.min(endDistance, contourEnd);
    if (localEnd - localStart <= _pathEpsilon) continue;

    final fullySelected =
        localStart <= contourStart + _pathEpsilon && localEnd >= contourEnd - _pathEpsilon;
    if (fullySelected) {
      _appendWholeContour(source, prepared, contour, out);
      continue;
    }

    _appendContourRange(
      source,
      prepared,
      contour,
      localStart,
      localEnd,
      out,
    );
  }

  if (out.isEmpty) {
    source.pointAtDistance(startDistance, source._scratchA);
    out.moveTo(source._scratchA.x, source._scratchA.y);
  }
  return out;
}

void _appendWholeContour(
  GPath source,
  _PreparedPath prepared,
  int contour,
  GPath out,
) {
  final first = prepared.contourFirstSegments[contour];
  final last = prepared.contourLastSegments[contour];
  final base = contour << 1;
  out.moveTo(prepared.contourStarts[base], prepared.contourStarts[base + 1]);

  if (first < 0 || last < first) {
    if (prepared.contourClosed[contour] != 0) out.close();
    return;
  }

  final closed = prepared.contourClosed[contour] != 0;
  final authoredLast = closed ? last - 1 : last;
  for (var segment = first; segment <= authoredLast; ++segment) {
    _appendFullSegment(prepared, segment, out);
  }
  if (closed) out.close();
}

void _appendContourRange(
  GPath source,
  _PreparedPath prepared,
  int contour,
  double startDistance,
  double endDistance,
  GPath out,
) {
  final first = prepared.contourFirstSegments[contour];
  final last = prepared.contourLastSegments[contour];
  if (first < 0 || last < first) return;

  var started = false;
  final startCursor = _SampleCursor();
  final endCursor = _SampleCursor();

  for (var segment = first; segment <= last; ++segment) {
    final segmentStart = prepared.segmentDistances[segment];
    final segmentEnd = prepared.segmentDistances[segment + 1];
    if (segmentEnd - segmentStart <= _pathEpsilon) continue;
    if (endDistance <= segmentStart || startDistance >= segmentEnd) continue;

    final pieceStart = math.max(startDistance, segmentStart);
    final pieceEnd = math.min(endDistance, segmentEnd);
    if (pieceEnd - pieceStart <= _pathEpsilon) continue;

    source._resolveSegmentDistance(
      prepared,
      segment,
      pieceStart,
      startCursor,
    );
    source._resolveSegmentDistance(
      prepared,
      segment,
      pieceEnd,
      endCursor,
    );

    final t0 = startCursor.t.clamp(0.0, 1.0).toDouble();
    final t1 = endCursor.t.clamp(0.0, 1.0).toDouble();
    if (t1 - t0 <= _pathEpsilon) continue;

    if (!started) {
      source._evalPoint(prepared, segment, t0, source._scratchA);
      out.moveTo(source._scratchA.x, source._scratchA.y);
      started = true;
    }
    _appendSegmentRange(source, prepared, segment, t0, t1, out);
  }
}

void _appendSegmentRange(
  GPath source,
  _PreparedPath prepared,
  int segment,
  double t0,
  double t1,
  GPath out,
) {
  if (t0 <= _pathEpsilon && t1 >= 1.0 - _pathEpsilon) {
    _appendFullSegment(prepared, segment, out);
    return;
  }

  final dt = t1 - t0;
  source._evalPoint(prepared, segment, t0, source._scratchA);
  final x0 = source._scratchA.x;
  final y0 = source._scratchA.y;
  source._evalPoint(prepared, segment, t1, source._scratchA);
  final x1 = source._scratchA.x;
  final y1 = source._scratchA.y;

  switch (prepared.kinds[segment]) {
    case _segmentLine:
      out.lineTo(x1, y1);
      break;
    case _segmentQuadratic:
      source._evalDerivative(prepared, segment, t0, source._scratchB);
      final scale = dt * 0.5;
      out.quadraticTo(
        x0 + source._scratchB.x * scale,
        y0 + source._scratchB.y * scale,
        x1,
        y1,
      );
      break;
    case _segmentCubic:
      source._evalDerivative(prepared, segment, t0, source._scratchB);
      final d0x = source._scratchB.x;
      final d0y = source._scratchB.y;
      source._evalDerivative(prepared, segment, t1, source._scratchC);
      final scale = dt / 3.0;
      out.cubicTo(
        x0 + d0x * scale,
        y0 + d0y * scale,
        x1 - source._scratchC.x * scale,
        y1 - source._scratchC.y * scale,
        x1,
        y1,
      );
      break;
  }
}

void _appendFullSegment(_PreparedPath prepared, int segment, GPath out) {
  final base = segment * 8;
  switch (prepared.kinds[segment]) {
    case _segmentLine:
      out.lineTo(prepared.coords[base + 6], prepared.coords[base + 7]);
      break;
    case _segmentQuadratic:
      out.quadraticTo(
        prepared.coords[base + 2],
        prepared.coords[base + 3],
        prepared.coords[base + 6],
        prepared.coords[base + 7],
      );
      break;
    case _segmentCubic:
      out.cubicTo(
        prepared.coords[base + 2],
        prepared.coords[base + 3],
        prepared.coords[base + 4],
        prepared.coords[base + 5],
        prepared.coords[base + 6],
        prepared.coords[base + 7],
      );
      break;
  }
}

void _appendReversedSegment(
  _PreparedPath prepared,
  int segment,
  GPath out,
) {
  final base = segment * 8;
  final x0 = prepared.coords[base];
  final y0 = prepared.coords[base + 1];
  switch (prepared.kinds[segment]) {
    case _segmentLine:
      out.lineTo(x0, y0);
      break;
    case _segmentQuadratic:
      out.quadraticTo(
        prepared.coords[base + 2],
        prepared.coords[base + 3],
        x0,
        y0,
      );
      break;
    case _segmentCubic:
      out.cubicTo(
        prepared.coords[base + 4],
        prepared.coords[base + 5],
        prepared.coords[base + 2],
        prepared.coords[base + 3],
        x0,
        y0,
      );
      break;
  }
}

void _replaceGeometry(GPath target, GPath source) {
  target._verbs.clear();
  target._verbs.addAll(source._verbs);
  target._values.clear();
  target._values.addAll(source._values);
  target._hasCurrent = source._hasCurrent;
  target._contourOpen = source._contourOpen;
  target._currentX = source._currentX;
  target._currentY = source._currentY;
  target._contourStartX = source._contourStartX;
  target._contourStartY = source._contourStartY;
  target._invalidate();
}

GPathFlattened _flattenPath(GPath source, _PreparedPath prepared) {
  final points = <double>[];
  final offsets = Int32List(prepared.contourCount + 1);
  final closed = Uint8List(prepared.contourCount);

  for (var contour = 0; contour < prepared.contourCount; ++contour) {
    offsets[contour] = points.length >> 1;
    closed[contour] = prepared.contourClosed[contour];
    final first = prepared.contourFirstSegments[contour];
    final last = prepared.contourLastSegments[contour];

    if (first < 0 || last < first) {
      final base = contour << 1;
      points.add(prepared.contourStarts[base]);
      points.add(prepared.contourStarts[base + 1]);
      offsets[contour + 1] = points.length >> 1;
      continue;
    }

    for (var segment = first; segment <= last; ++segment) {
      final sampleFirst = prepared.lutOffsets[segment];
      final sampleLast = prepared.lutOffsets[segment + 1];
      final begin = segment == first ? sampleFirst : sampleFirst + 1;
      for (var sample = begin; sample < sampleLast; ++sample) {
        final base = sample * 4;
        points.add(prepared.samples[base + 2]);
        points.add(prepared.samples[base + 3]);
      }
    }

    if (closed[contour] != 0) {
      final start = offsets[contour] << 1;
      if (points.length - start >= 4) {
        final last = points.length - 2;
        if (points[start] == points[last] && points[start + 1] == points[last + 1]) {
          points.removeRange(last, points.length);
        }
      }
    }
    offsets[contour + 1] = points.length >> 1;
  }

  return GPathFlattened._(
    Float64List.fromList(points),
    offsets,
    closed,
    sourceGeometryVersion: source.geometryVersion,
    tolerance: source.tolerance,
  );
}

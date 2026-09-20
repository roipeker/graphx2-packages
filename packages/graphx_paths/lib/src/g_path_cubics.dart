// Copyright (c) 2026 GraphX by roipeker.

part of '../graphx_paths.dart';

const int _cubicStride = 8;
const double _cubicDirectionEpsilon = 1e-12;

/// Packed canonical cubic representation of a retained [GPath].
///
/// Every geometric segment is represented by eight doubles:
/// `p0, c1, c2, p3`. Lines and quadratics are converted exactly; cubics are
/// copied. Contour offsets and closed state are retained separately.
///
/// This is derived geometry intended for tooling, serialization and topology
/// preparation. It does not replace [GPath] as the authored or sampled runtime
/// representation.
final class GPathCubics {
  GPathCubics._(this._coords, this._contourOffsets, this._contourClosed);

  final Float64List _coords;
  final Int32List _contourOffsets;
  final Uint8List _contourClosed;

  int get segmentCount => _coords.length ~/ _cubicStride;
  int get contourCount => _contourClosed.length;
  int get coordinateCount => _coords.length;

  int contourStartSegment(int contour) {
    _checkContour(contour);
    return _contourOffsets[contour];
  }

  int contourEndSegment(int contour) {
    _checkContour(contour);
    return _contourOffsets[contour + 1];
  }

  int contourSegmentCount(int contour) => contourEndSegment(contour) - contourStartSegment(contour);

  int contourCoordinateCount(int contour) => contourSegmentCount(contour) * _cubicStride;

  bool isContourClosed(int contour) {
    _checkContour(contour);
    return _contourClosed[contour] != 0;
  }

  double coordinateAt(int index) {
    if (index < 0 || index >= _coords.length) {
      throw RangeError.index(index, this, 'index', null, _coords.length);
    }
    return _coords[index];
  }

  /// Copies all packed cubic data into [out] without exposing mutable storage.
  void copyCoordinatesInto(Float64List out, [int offset = 0]) {
    _checkOutput(out, offset, _coords.length);
    out.setRange(offset, offset + _coords.length, _coords);
  }

  /// Copies one canonical cubic into [out].
  void copySegmentCoordinatesInto(
    int segment,
    Float64List out, [
    int offset = 0,
  ]) {
    _checkSegment(segment);
    _checkOutput(out, offset, _cubicStride);
    final source = segment * _cubicStride;
    out.setRange(offset, offset + _cubicStride, _coords, source);
  }

  /// Copies one contour's packed cubic range into [out].
  void copyContourCoordinatesInto(
    int contour,
    Float64List out, [
    int offset = 0,
  ]) {
    final start = contourStartSegment(contour) * _cubicStride;
    final count = contourCoordinateCount(contour);
    _checkOutput(out, offset, count);
    out.setRange(offset, offset + count, _coords, start);
  }

  /// Evaluates one canonical cubic at raw Bézier parameter [t].
  ///
  /// Unlike [GPath.pointAt], [t] is local cubic parameter space, not arc-length
  /// progress. This operation performs no retained path lookup or allocation
  /// when [out] is supplied.
  GPoint pointAtSegment(int segment, double t, [GPoint? out]) {
    _checkSegmentParameter(segment, t);
    final result = out ?? GPoint();
    final base = segment * _cubicStride;
    final mt = 1.0 - t;
    final mt2 = mt * mt;
    final t2 = t * t;
    final a = mt2 * mt;
    final b = 3.0 * mt2 * t;
    final c = 3.0 * mt * t2;
    final d = t2 * t;
    result.x =
        _coords[base] * a + _coords[base + 2] * b + _coords[base + 4] * c + _coords[base + 6] * d;
    result.y =
        _coords[base + 1] * a +
        _coords[base + 3] * b +
        _coords[base + 5] * c +
        _coords[base + 7] * d;
    return result;
  }

  /// Evaluates the raw first derivative of one canonical cubic at [t].
  GPoint derivativeAtSegment(int segment, double t, [GPoint? out]) {
    _checkSegmentParameter(segment, t);
    final result = out ?? GPoint();
    final base = segment * _cubicStride;
    final mt = 1.0 - t;
    final a = 3.0 * mt * mt;
    final b = 6.0 * mt * t;
    final c = 3.0 * t * t;
    result.x =
        (_coords[base + 2] - _coords[base]) * a +
        (_coords[base + 4] - _coords[base + 2]) * b +
        (_coords[base + 6] - _coords[base + 4]) * c;
    result.y =
        (_coords[base + 3] - _coords[base + 1]) * a +
        (_coords[base + 5] - _coords[base + 3]) * b +
        (_coords[base + 7] - _coords[base + 5]) * c;
    return result;
  }

  /// Evaluates a normalized tangent for one canonical cubic at [t].
  ///
  /// Singular derivatives fall back deterministically to the segment chord and
  /// then to non-zero control-polygon edges. Fully degenerate cubics return zero.
  GPoint tangentAtSegment(int segment, double t, [GPoint? out]) {
    final result = derivativeAtSegment(segment, t, out);
    if (_normalizeDirection(result)) return result;

    final base = segment * _cubicStride;
    result.x = _coords[base + 6] - _coords[base];
    result.y = _coords[base + 7] - _coords[base + 1];
    if (_normalizeDirection(result)) return result;

    for (var edge = 0; edge < 3; ++edge) {
      final a = base + edge * 2;
      final b = a + 2;
      result.x = _coords[b] - _coords[a];
      result.y = _coords[b + 1] - _coords[a + 1];
      if (_normalizeDirection(result)) return result;
    }
    result.setZero();
    return result;
  }

  /// Returns a new canonical snapshot with [segment] split exactly at [t].
  ///
  /// De Casteljau subdivision preserves the original cubic geometry exactly.
  /// Contour ordering, closure and seam metadata are unchanged; only the
  /// containing contour gains one segment.
  GPathCubics subdivide(int segment, double t) {
    _checkSegment(segment);
    if (!t.isFinite || t <= 0.0 || t >= 1.0) {
      throw ArgumentError.value(
        t,
        't',
        'Must be finite and strictly between 0 and 1.',
      );
    }

    final out = Float64List(_coords.length + _cubicStride);
    final source = segment * _cubicStride;
    if (source > 0) out.setRange(0, source, _coords);
    _splitCubicInto(_coords, source, t, out, source);
    final tail = source + _cubicStride;
    if (tail < _coords.length) {
      out.setRange(source + _cubicStride * 2, out.length, _coords, tail);
    }

    final offsets = Int32List.fromList(_contourOffsets);
    for (var contour = 1; contour < offsets.length; ++contour) {
      if (offsets[contour] > segment) offsets[contour] += 1;
    }
    return GPathCubics._(
      out,
      offsets,
      Uint8List.fromList(_contourClosed),
    );
  }

  /// Subdivides every source segment into the requested number of equal-`t`
  /// pieces, allocating the resulting packed snapshot once.
  ///
  /// [piecesPerSegment] must contain one value per current segment and every
  /// value must be at least one. A value of one copies the segment unchanged.
  /// This changes topology without changing the represented geometry.
  GPathCubics subdivideByCounts(Int32List piecesPerSegment) {
    if (piecesPerSegment.length != segmentCount) {
      throw ArgumentError.value(
        piecesPerSegment.length,
        'piecesPerSegment',
        'Expected one piece count for each of $segmentCount segments.',
      );
    }
    if (segmentCount == 0) return this;

    var outputSegments = 0;
    var changed = false;
    for (var segment = 0; segment < segmentCount; ++segment) {
      final pieces = piecesPerSegment[segment];
      if (pieces < 1) {
        throw RangeError.value(
          pieces,
          'piecesPerSegment[$segment]',
          'Must be at least 1.',
        );
      }
      outputSegments += pieces;
      if (pieces != 1) changed = true;
    }
    if (!changed) return this;

    final offsets = Int32List(contourCount + 1);
    var outputOffset = 0;
    for (var contour = 0; contour < contourCount; ++contour) {
      offsets[contour] = outputOffset;
      final start = _contourOffsets[contour];
      final end = _contourOffsets[contour + 1];
      for (var segment = start; segment < end; ++segment) {
        outputOffset += piecesPerSegment[segment];
      }
    }
    offsets[contourCount] = outputOffset;

    final out = Float64List(outputSegments * _cubicStride);
    var targetSegment = 0;
    for (var segment = 0; segment < segmentCount; ++segment) {
      final pieces = piecesPerSegment[segment];
      final source = segment * _cubicStride;
      final target = targetSegment * _cubicStride;
      if (pieces == 1) {
        out.setRange(target, target + _cubicStride, _coords, source);
      } else {
        _splitCubicEvenlyInto(_coords, source, pieces, out, target);
      }
      targetSegment += pieces;
    }

    return GPathCubics._(
      out,
      offsets,
      Uint8List.fromList(_contourClosed),
    );
  }

  /// Exactly subdivides one contour until it contains [targetSegmentCount]
  /// canonical cubic segments.
  ///
  /// Existing segments are distributed deterministically across the target
  /// count and split into equal local-parameter pieces. Geometry, contour order,
  /// closure and seam are preserved. This operation only subdivides; it never
  /// merges segments.
  GPathCubics subdivideContourToCount(int contour, int targetSegmentCount) {
    final sourceCount = contourSegmentCount(contour);
    if (targetSegmentCount < sourceCount) {
      throw RangeError.value(
        targetSegmentCount,
        'targetSegmentCount',
        'Must be at least the current contour segment count ($sourceCount).',
      );
    }
    if (sourceCount == 0) {
      if (targetSegmentCount != 0) {
        throw StateError('Cannot subdivide an empty contour into geometry.');
      }
      return this;
    }
    if (targetSegmentCount == sourceCount) return this;

    final counts = Int32List(segmentCount);
    counts.fillRange(0, counts.length, 1);
    final start = _contourOffsets[contour];
    for (var local = 0; local < sourceCount; ++local) {
      final begin = local * targetSegmentCount ~/ sourceCount;
      final end = (local + 1) * targetSegmentCount ~/ sourceCount;
      counts[start + local] = end - begin;
    }
    return subdivideByCounts(counts);
  }

  /// Removes one canonical segment from the packed topology.
  ///
  /// No neighboring geometry is reconnected or refit. This is intentionally a
  /// low-level topology operation for tooling/preparation layers that already
  /// own continuity policy.
  GPathCubics removeSegment(int segment) {
    _checkSegment(segment);
    final source = segment * _cubicStride;
    final out = Float64List(_coords.length - _cubicStride);
    if (source > 0) out.setRange(0, source, _coords);
    final tail = source + _cubicStride;
    if (tail < _coords.length) {
      out.setRange(source, out.length, _coords, tail);
    }

    final offsets = Int32List.fromList(_contourOffsets);
    for (var contour = 1; contour < offsets.length; ++contour) {
      if (offsets[contour] > segment) offsets[contour] -= 1;
    }
    return GPathCubics._(
      out,
      offsets,
      Uint8List.fromList(_contourClosed),
    );
  }

  /// Reverses traversal of one contour without changing its geometry.
  ///
  /// Cubic control handles swap direction exactly. Other contours and contour
  /// ordering are untouched. Closed contours keep their existing canonical seam
  /// when their final segment ends at that seam, as normal [GPath.toCubics]
  /// snapshots do.
  GPathCubics reverseContour(int contour) {
    final start = contourStartSegment(contour);
    final end = contourEndSegment(contour);
    if (end - start <= 1 && start == end) return this;

    final out = Float64List.fromList(_coords);
    final count = end - start;
    for (var local = 0; local < count; ++local) {
      final source = (end - 1 - local) * _cubicStride;
      final target = (start + local) * _cubicStride;
      _writeCubic(
        out,
        target,
        _coords[source + 6],
        _coords[source + 7],
        _coords[source + 4],
        _coords[source + 5],
        _coords[source + 2],
        _coords[source + 3],
        _coords[source],
        _coords[source + 1],
      );
    }
    return GPathCubics._(
      out,
      Int32List.fromList(_contourOffsets),
      Uint8List.fromList(_contourClosed),
    );
  }

  /// Rotates the authored seam of one closed contour by whole cubic segments.
  ///
  /// Geometry and traversal direction are unchanged. [segmentOffset] may be
  /// positive or negative and is normalized by the contour's segment count.
  /// Choosing which seam is desirable remains consumer policy.
  GPathCubics rotateClosedContourSeam(int contour, int segmentOffset) {
    if (!isContourClosed(contour)) {
      throw StateError('Seam rotation requires a closed contour.');
    }
    final start = _contourOffsets[contour];
    final end = _contourOffsets[contour + 1];
    final count = end - start;
    if (count == 0) {
      throw StateError('Cannot rotate the seam of an empty contour.');
    }
    final shift = ((segmentOffset % count) + count) % count;
    if (shift == 0) return this;

    final out = Float64List.fromList(_coords);
    for (var local = 0; local < count; ++local) {
      final sourceSegment = start + (local + shift) % count;
      final targetSegment = start + local;
      final source = sourceSegment * _cubicStride;
      final target = targetSegment * _cubicStride;
      out.setRange(target, target + _cubicStride, _coords, source);
    }
    return GPathCubics._(
      out,
      Int32List.fromList(_contourOffsets),
      Uint8List.fromList(_contourClosed),
    );
  }

  void _checkSegmentParameter(int segment, double t) {
    _checkSegment(segment);
    if (!t.isFinite || t < 0.0 || t > 1.0) {
      throw ArgumentError.value(t, 't', 'Must be finite and between 0 and 1.');
    }
  }

  void _checkSegment(int segment) {
    if (segment < 0 || segment >= segmentCount) {
      throw RangeError.index(segment, this, 'segment', null, segmentCount);
    }
  }

  void _checkContour(int contour) {
    if (contour < 0 || contour >= contourCount) {
      throw RangeError.index(contour, this, 'contour', null, contourCount);
    }
  }

  static void _checkOutput(Float64List out, int offset, int count) {
    if (offset < 0 || offset > out.length || count > out.length - offset) {
      throw RangeError.value(offset, 'offset', 'Output buffer is too small.');
    }
  }
}

extension GPathCubicGeometry on GPath {
  /// Converts this path exactly to packed cubic Bézier segments.
  ///
  /// Lines and quadratics use their exact degree-elevation formulas. Closed
  /// contours include their geometric closing edge as a cubic segment while
  /// retaining a separate closed flag and contour boundary metadata.
  GPathCubics toCubics() {
    final prepared = _ensurePrepared();
    final coords = Float64List(prepared.segmentCount * _cubicStride);

    for (var segment = 0; segment < prepared.segmentCount; ++segment) {
      final source = segment * _cubicStride;
      final target = source;
      final p0x = prepared.coords[source];
      final p0y = prepared.coords[source + 1];
      final p3x = prepared.coords[source + 6];
      final p3y = prepared.coords[source + 7];
      coords[target] = p0x;
      coords[target + 1] = p0y;
      coords[target + 6] = p3x;
      coords[target + 7] = p3y;

      switch (prepared.kinds[segment]) {
        case _segmentLine:
          coords[target + 2] = p0x + (p3x - p0x) / 3.0;
          coords[target + 3] = p0y + (p3y - p0y) / 3.0;
          coords[target + 4] = p0x + (p3x - p0x) * (2.0 / 3.0);
          coords[target + 5] = p0y + (p3y - p0y) * (2.0 / 3.0);
          break;
        case _segmentQuadratic:
          final qx = prepared.coords[source + 2];
          final qy = prepared.coords[source + 3];
          coords[target + 2] = p0x + (qx - p0x) * (2.0 / 3.0);
          coords[target + 3] = p0y + (qy - p0y) * (2.0 / 3.0);
          coords[target + 4] = p3x + (qx - p3x) * (2.0 / 3.0);
          coords[target + 5] = p3y + (qy - p3y) * (2.0 / 3.0);
          break;
        case _segmentCubic:
          coords[target + 2] = prepared.coords[source + 2];
          coords[target + 3] = prepared.coords[source + 3];
          coords[target + 4] = prepared.coords[source + 4];
          coords[target + 5] = prepared.coords[source + 5];
          break;
      }
    }

    final offsets = Int32List(prepared.contourCount + 1);
    var nextSegment = 0;
    for (var contour = 0; contour < prepared.contourCount; ++contour) {
      offsets[contour] = nextSegment;
      final last = prepared.contourLastSegments[contour];
      if (last >= nextSegment) nextSegment = last + 1;
    }
    offsets[prepared.contourCount] = prepared.segmentCount;

    return GPathCubics._(
      coords,
      offsets,
      Uint8List.fromList(prepared.contourClosed),
    );
  }
}

bool _normalizeDirection(GPoint point) {
  final lengthSquared = point.x * point.x + point.y * point.y;
  if (!lengthSquared.isFinite || lengthSquared <= _cubicDirectionEpsilon * _cubicDirectionEpsilon) {
    return false;
  }
  final inverse = 1.0 / math.sqrt(lengthSquared);
  point.x *= inverse;
  point.y *= inverse;
  return true;
}

void _splitCubicInto(
  Float64List source,
  int sourceBase,
  double t,
  Float64List output,
  int outputBase,
) {
  final p0x = source[sourceBase];
  final p0y = source[sourceBase + 1];
  final p1x = source[sourceBase + 2];
  final p1y = source[sourceBase + 3];
  final p2x = source[sourceBase + 4];
  final p2y = source[sourceBase + 5];
  final p3x = source[sourceBase + 6];
  final p3y = source[sourceBase + 7];

  final a0x = _lerpScalar(p0x, p1x, t);
  final a0y = _lerpScalar(p0y, p1y, t);
  final a1x = _lerpScalar(p1x, p2x, t);
  final a1y = _lerpScalar(p1y, p2y, t);
  final a2x = _lerpScalar(p2x, p3x, t);
  final a2y = _lerpScalar(p2y, p3y, t);
  final b0x = _lerpScalar(a0x, a1x, t);
  final b0y = _lerpScalar(a0y, a1y, t);
  final b1x = _lerpScalar(a1x, a2x, t);
  final b1y = _lerpScalar(a1y, a2y, t);
  final mx = _lerpScalar(b0x, b1x, t);
  final my = _lerpScalar(b0y, b1y, t);

  _writeCubic(
    output,
    outputBase,
    p0x,
    p0y,
    a0x,
    a0y,
    b0x,
    b0y,
    mx,
    my,
  );
  _writeCubic(
    output,
    outputBase + _cubicStride,
    mx,
    my,
    b1x,
    b1y,
    a2x,
    a2y,
    p3x,
    p3y,
  );
}

void _splitCubicEvenlyInto(
  Float64List source,
  int sourceBase,
  int pieces,
  Float64List output,
  int outputBase,
) {
  var p0x = source[sourceBase];
  var p0y = source[sourceBase + 1];
  var p1x = source[sourceBase + 2];
  var p1y = source[sourceBase + 3];
  var p2x = source[sourceBase + 4];
  var p2y = source[sourceBase + 5];
  final p3x = source[sourceBase + 6];
  final p3y = source[sourceBase + 7];

  for (var piece = 0; piece < pieces - 1; ++piece) {
    final t = 1.0 / (pieces - piece);
    final a0x = _lerpScalar(p0x, p1x, t);
    final a0y = _lerpScalar(p0y, p1y, t);
    final a1x = _lerpScalar(p1x, p2x, t);
    final a1y = _lerpScalar(p1y, p2y, t);
    final a2x = _lerpScalar(p2x, p3x, t);
    final a2y = _lerpScalar(p2y, p3y, t);
    final b0x = _lerpScalar(a0x, a1x, t);
    final b0y = _lerpScalar(a0y, a1y, t);
    final b1x = _lerpScalar(a1x, a2x, t);
    final b1y = _lerpScalar(a1y, a2y, t);
    final mx = _lerpScalar(b0x, b1x, t);
    final my = _lerpScalar(b0y, b1y, t);

    _writeCubic(
      output,
      outputBase + piece * _cubicStride,
      p0x,
      p0y,
      a0x,
      a0y,
      b0x,
      b0y,
      mx,
      my,
    );
    p0x = mx;
    p0y = my;
    p1x = b1x;
    p1y = b1y;
    p2x = a2x;
    p2y = a2y;
  }

  _writeCubic(
    output,
    outputBase + (pieces - 1) * _cubicStride,
    p0x,
    p0y,
    p1x,
    p1y,
    p2x,
    p2y,
    p3x,
    p3y,
  );
}

void _writeCubic(
  Float64List output,
  int base,
  double p0x,
  double p0y,
  double p1x,
  double p1y,
  double p2x,
  double p2y,
  double p3x,
  double p3y,
) {
  output[base] = p0x;
  output[base + 1] = p0y;
  output[base + 2] = p1x;
  output[base + 3] = p1y;
  output[base + 4] = p2x;
  output[base + 5] = p2y;
  output[base + 6] = p3x;
  output[base + 7] = p3y;
}

double _lerpScalar(double a, double b, double t) => a + (b - a) * t;

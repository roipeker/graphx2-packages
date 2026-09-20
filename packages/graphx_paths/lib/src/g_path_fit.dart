// Copyright (c) 2026 GraphX by roipeker.

part of '../graphx_paths.dart';

/// Established sampled-point authoring algorithms used by [GPath.fit] and
/// [GPath.simplifyPoints].
///
/// Cubic fitting follows Philip J. Schneider's Graphics Gems algorithm:
/// chord-length parameterization, least-squares handle generation, guarded
/// Newton reparameterization, then splitting at the largest error.
///
/// Closed fitting uses a cyclic seam tangent rather than treating the seam as
/// two unrelated open-path endpoints. Pathological candidate cubics are
/// rejected and subdivided instead of clamping their control handles.
GPath _fitSampledPath(
  List<GPoint> input, {
  required bool closed,
  required double fitTolerance,
  required double pathTolerance,
}) {
  if (!fitTolerance.isFinite || fitTolerance <= 0.0) {
    throw ArgumentError.value(
      fitTolerance,
      'tolerance',
      'Must be finite and > 0.',
    );
  }
  if (!pathTolerance.isFinite || pathTolerance <= 0.0) {
    throw ArgumentError.value(
      pathTolerance,
      'pathTolerance',
      'Must be finite and > 0.',
    );
  }

  final points = _packUniquePoints(
    input,
    nearDistance: fitTolerance * 1e-6,
    closed: closed,
  );
  final retainedCount = points.length >> 1;
  final out = GPath(tolerance: pathTolerance);
  if (retainedCount == 0) return out;

  out.moveTo(points[0], points[1]);
  if (retainedCount == 1) return out;
  if (retainedCount == 2) {
    out.lineTo(points[2], points[3]);
    if (closed) out.close();
    return out;
  }

  late final Float64List fitPoints;
  late final int count;
  late final (double, double) left;
  late final (double, double) right;

  if (closed) {
    fitPoints = Float64List(points.length + 2);
    fitPoints.setRange(0, points.length, points);
    fitPoints[points.length] = points[0];
    fitPoints[points.length + 1] = points[1];
    count = retainedCount + 1;
    left = _fitClosedSeamTangent(points, retainedCount);
    right = (-left.$1, -left.$2);
  } else {
    fitPoints = points;
    count = retainedCount;
    left = _fitEndpointTangent(fitPoints, 0, 1);
    right = _fitEndpointTangent(fitPoints, count - 1, count - 2);
  }

  final u = Float64List(count);
  final tasks = <_FitTask>[
    _FitTask(0, count - 1, left.$1, left.$2, right.$1, right.$2),
  ];
  final errorSquared = fitTolerance * fitTolerance;

  while (tasks.isNotEmpty) {
    final task = tasks.removeLast();
    final first = task.first;
    final last = task.last;
    final n = last - first + 1;

    if (n == 2) {
      _appendTwoPointFit(out, fitPoints, first, last, task);
      continue;
    }

    _chordParameterize(fitPoints, first, last, u);
    var curve = _generateFitCubic(fitPoints, first, last, u, task);
    var sane = _fitCurveSane(
      fitPoints,
      first,
      last,
      curve,
      fitTolerance,
    );
    var error = sane
        ? _fitMaxError(fitPoints, first, last, u, curve)
        : (
            errorSquared: double.infinity,
            split: _fitStableSplit(fitPoints, first, last),
          );

    if (sane && error.errorSquared <= errorSquared) {
      _appendFitCurve(out, curve);
      continue;
    }

    if (sane && error.errorSquared <= errorSquared * 4.0) {
      for (var iteration = 0; iteration < 4; ++iteration) {
        if (!_reparameterizeFit(fitPoints, first, last, u, curve)) break;
        curve = _generateFitCubic(fitPoints, first, last, u, task);
        sane = _fitCurveSane(
          fitPoints,
          first,
          last,
          curve,
          fitTolerance,
        );
        if (!sane) {
          error = (
            errorSquared: double.infinity,
            split: _fitStableSplit(fitPoints, first, last),
          );
          break;
        }
        error = _fitMaxError(fitPoints, first, last, u, curve);
        if (error.errorSquared <= errorSquared) break;
      }
      if (sane && error.errorSquared <= errorSquared) {
        _appendFitCurve(out, curve);
        continue;
      }
    }

    var split = error.split;
    if (split <= first || split >= last) {
      split = _fitStableSplit(fitPoints, first, last);
    }
    if (split <= first) split = first + 1;
    if (split >= last) split = last - 1;

    final center = _fitCenterTangent(fitPoints, split, first, last);

    // Stack is LIFO. Push right first so left is emitted first and the output
    // remains in source order without collecting per-segment objects.
    tasks.add(
      _FitTask(split, last, -center.$1, -center.$2, task.t2x, task.t2y),
    );
    tasks.add(
      _FitTask(first, split, task.t1x, task.t1y, center.$1, center.$2),
    );
  }

  if (closed) out.close();
  return out;
}

void _appendTwoPointFit(
  GPath out,
  Float64List points,
  int first,
  int last,
  _FitTask task,
) {
  final p0 = first << 1;
  final p3 = last << 1;
  final dx = points[p3] - points[p0];
  final dy = points[p3 + 1] - points[p0 + 1];
  final segmentLength = math.sqrt(dx * dx + dy * dy);
  if (segmentLength <= _pathEpsilon) {
    out.lineTo(points[p3], points[p3 + 1]);
    return;
  }

  final forward = _normalizeFitVector(dx, dy);
  final left = task.t1x == 0.0 && task.t1y == 0.0 ? forward : (task.t1x, task.t1y);
  final right = task.t2x == 0.0 && task.t2y == 0.0
      ? (-forward.$1, -forward.$2)
      : (task.t2x, task.t2y);
  final dist = segmentLength / 3.0;

  out.cubicTo(
    points[p0] + left.$1 * dist,
    points[p0 + 1] + left.$2 * dist,
    points[p3] + right.$1 * dist,
    points[p3 + 1] + right.$2 * dist,
    points[p3],
    points[p3 + 1],
  );
}

List<GPoint> _simplifySampledPoints(
  List<GPoint> input, {
  required double tolerance,
}) {
  if (!tolerance.isFinite || tolerance < 0.0) {
    throw ArgumentError.value(
      tolerance,
      'tolerance',
      'Must be finite and >= 0.',
    );
  }
  if (input.isEmpty) return <GPoint>[];

  final points = _packUniquePoints(input);
  final count = points.length >> 1;
  if (count <= 2) {
    return List<GPoint>.generate(
      count,
      (i) => GPoint(points[i << 1], points[(i << 1) + 1]),
      growable: false,
    );
  }

  final keep = Uint8List(count);
  keep[0] = 1;
  keep[count - 1] = 1;
  final stack = <int>[0, count - 1];
  final toleranceSquared = tolerance * tolerance;

  while (stack.isNotEmpty) {
    final last = stack.removeLast();
    final first = stack.removeLast();
    final ax = points[first << 1];
    final ay = points[(first << 1) + 1];
    final bx = points[last << 1];
    final by = points[(last << 1) + 1];

    var split = -1;
    var maxDistanceSquared = toleranceSquared;
    for (var i = first + 1; i < last; ++i) {
      final base = i << 1;
      final distanceSquared = _pointSegmentDistanceSquared(
        points[base],
        points[base + 1],
        ax,
        ay,
        bx,
        by,
      );
      if (distanceSquared > maxDistanceSquared) {
        maxDistanceSquared = distanceSquared;
        split = i;
      }
    }

    if (split >= 0) {
      keep[split] = 1;
      stack.add(first);
      stack.add(split);
      stack.add(split);
      stack.add(last);
    }
  }

  final out = <GPoint>[];
  for (var i = 0; i < count; ++i) {
    if (keep[i] == 0) continue;
    final base = i << 1;
    out.add(GPoint(points[base], points[base + 1]));
  }
  return out;
}

Float64List _packUniquePoints(
  List<GPoint> input, {
  double nearDistance = 0.0,
  bool closed = false,
}) {
  if (input.isEmpty) return Float64List(0);

  final values = <double>[];
  final nearSquared = nearDistance * nearDistance;
  var hasLast = false;
  var lastX = 0.0;
  var lastY = 0.0;

  for (var i = 0; i < input.length; ++i) {
    final point = input[i];
    final x = point.x;
    final y = point.y;
    _checkPoint(x, y);
    if (hasLast) {
      final dx = x - lastX;
      final dy = y - lastY;
      if (dx * dx + dy * dy <= nearSquared) continue;
    }
    values.add(x);
    values.add(y);
    lastX = x;
    lastY = y;
    hasLast = true;
  }

  if (closed && values.length >= 4) {
    final last = values.length - 2;
    final dx = values[last] - values[0];
    final dy = values[last + 1] - values[1];
    if (dx * dx + dy * dy <= nearSquared) {
      values.removeRange(last, values.length);
    }
  }

  return Float64List.fromList(values);
}

(double, double) _fitClosedSeamTangent(Float64List points, int count) {
  final previous = (count - 1) << 1;
  final next = 2;
  var tangent = _normalizeFitVector(
    points[next] - points[previous],
    points[next + 1] - points[previous + 1],
  );
  if (tangent.$1 != 0.0 || tangent.$2 != 0.0) return tangent;

  tangent = _normalizeFitVector(
    points[next] - points[0],
    points[next + 1] - points[1],
  );
  if (tangent.$1 != 0.0 || tangent.$2 != 0.0) return tangent;

  return _normalizeFitVector(
    points[0] - points[previous],
    points[1] - points[previous + 1],
  );
}

(double, double) _fitEndpointTangent(
  Float64List points,
  int from,
  int toward,
) {
  final a = from << 1;
  final b = toward << 1;
  return _normalizeFitVector(
    points[b] - points[a],
    points[b + 1] - points[a + 1],
  );
}

(double, double) _fitCenterTangent(
  Float64List points,
  int center,
  int first,
  int last,
) {
  final c = center << 1;
  var px = 0.0;
  var py = 0.0;
  if (center > first) {
    final p = (center - 1) << 1;
    px += points[p] - points[c];
    py += points[p + 1] - points[c + 1];
  }
  if (center < last) {
    final n = (center + 1) << 1;
    px += points[c] - points[n];
    py += points[c + 1] - points[n + 1];
  }
  final normalized = _normalizeFitVector(px, py);
  if (normalized.$1 != 0.0 || normalized.$2 != 0.0) return normalized;
  if (center > first) return _fitEndpointTangent(points, center, center - 1);
  return _fitEndpointTangent(points, center, center + 1);
}

(double, double) _normalizeFitVector(double x, double y) {
  final lengthSquared = x * x + y * y;
  if (lengthSquared <= _pathEpsilon || !lengthSquared.isFinite) {
    return (0.0, 0.0);
  }
  final inv = 1.0 / math.sqrt(lengthSquared);
  return (x * inv, y * inv);
}

void _chordParameterize(
  Float64List points,
  int first,
  int last,
  Float64List u,
) {
  final count = last - first + 1;
  u[0] = 0.0;
  var total = 0.0;
  for (var i = 1; i < count; ++i) {
    final a = (first + i - 1) << 1;
    final b = (first + i) << 1;
    final dx = points[b] - points[a];
    final dy = points[b + 1] - points[a + 1];
    total += math.sqrt(dx * dx + dy * dy);
    u[i] = total;
  }
  if (total <= _pathEpsilon) {
    final denominator = math.max(1, count - 1);
    for (var i = 1; i < count; ++i) u[i] = i / denominator;
    return;
  }
  final inv = 1.0 / total;
  for (var i = 1; i < count; ++i) u[i] *= inv;
}

_FitCurve _generateFitCubic(
  Float64List points,
  int first,
  int last,
  Float64List u,
  _FitTask task,
) {
  final p0 = first << 1;
  final p3 = last << 1;
  final p0x = points[p0];
  final p0y = points[p0 + 1];
  final p3x = points[p3];
  final p3y = points[p3 + 1];

  var c00 = 0.0;
  var c01 = 0.0;
  var c11 = 0.0;
  var x0 = 0.0;
  var x1 = 0.0;
  final count = last - first + 1;

  for (var i = 0; i < count; ++i) {
    final t = u[i];
    final mt = 1.0 - t;
    final b0 = mt * mt * mt;
    final b1 = 3.0 * t * mt * mt;
    final b2 = 3.0 * t * t * mt;
    final b3 = t * t * t;
    final a1x = task.t1x * b1;
    final a1y = task.t1y * b1;
    final a2x = task.t2x * b2;
    final a2y = task.t2y * b2;
    c00 += a1x * a1x + a1y * a1y;
    c01 += a1x * a2x + a1y * a2y;
    c11 += a2x * a2x + a2y * a2y;

    final point = (first + i) << 1;
    final qx = points[point] - (p0x * (b0 + b1) + p3x * (b2 + b3));
    final qy = points[point + 1] - (p0y * (b0 + b1) + p3y * (b2 + b3));
    x0 += a1x * qx + a1y * qy;
    x1 += a2x * qx + a2y * qy;
  }

  final determinant = c00 * c11 - c01 * c01;
  var alpha1 = 0.0;
  var alpha2 = 0.0;
  if (determinant.isFinite && determinant.abs() > _pathEpsilon) {
    alpha1 = (x0 * c11 - x1 * c01) / determinant;
    alpha2 = (c00 * x1 - c01 * x0) / determinant;
  }

  final dx = p3x - p0x;
  final dy = p3y - p0y;
  final segmentLength = math.sqrt(dx * dx + dy * dy);
  final epsilon = math.max(_pathEpsilon, segmentLength * 1e-6);
  if (!alpha1.isFinite || !alpha2.isFinite || alpha1 < epsilon || alpha2 < epsilon) {
    alpha1 = alpha2 = segmentLength / 3.0;
  }

  return _FitCurve(
    p0x,
    p0y,
    p0x + task.t1x * alpha1,
    p0y + task.t1y * alpha1,
    p3x + task.t2x * alpha2,
    p3y + task.t2y * alpha2,
    p3x,
    p3y,
  );
}

bool _fitCurveSane(
  Float64List points,
  int first,
  int last,
  _FitCurve curve,
  double fitTolerance,
) {
  if (!curve.p0x.isFinite ||
      !curve.p0y.isFinite ||
      !curve.c1x.isFinite ||
      !curve.c1y.isFinite ||
      !curve.c2x.isFinite ||
      !curve.c2y.isFinite ||
      !curve.p3x.isFinite ||
      !curve.p3y.isFinite) {
    return false;
  }

  var minX = double.infinity;
  var minY = double.infinity;
  var maxX = double.negativeInfinity;
  var maxY = double.negativeInfinity;
  var maxEdge = 0.0;

  for (var i = first; i <= last; ++i) {
    final base = i << 1;
    final x = points[base];
    final y = points[base + 1];
    minX = math.min(minX, x);
    minY = math.min(minY, y);
    maxX = math.max(maxX, x);
    maxY = math.max(maxY, y);
    if (i > first) {
      final previous = (i - 1) << 1;
      final dx = x - points[previous];
      final dy = y - points[previous + 1];
      maxEdge = math.max(maxEdge, math.sqrt(dx * dx + dy * dy));
    }
  }

  final width = maxX - minX;
  final height = maxY - minY;
  final diagonal = math.sqrt(width * width + height * height);
  final localScale = math.max(
    fitTolerance * 8.0,
    math.max(diagonal * 1.5, maxEdge * 4.0),
  );

  final h1x = curve.c1x - curve.p0x;
  final h1y = curve.c1y - curve.p0y;
  final h2x = curve.c2x - curve.p3x;
  final h2y = curve.c2y - curve.p3y;
  final h1 = math.sqrt(h1x * h1x + h1y * h1y);
  final h2 = math.sqrt(h2x * h2x + h2y * h2y);
  return h1 <= localScale && h2 <= localScale;
}

({double errorSquared, int split}) _fitMaxError(
  Float64List points,
  int first,
  int last,
  Float64List u,
  _FitCurve curve,
) {
  var maxError = -1.0;
  var split = (first + last) >> 1;
  final count = last - first + 1;
  for (var i = 1; i < count - 1; ++i) {
    final point = (first + i) << 1;
    final sample = _evaluateFitCurve(curve, u[i]);
    final dx = sample.$1 - points[point];
    final dy = sample.$2 - points[point + 1];
    final error = dx * dx + dy * dy;
    if (!error.isFinite) {
      return (
        errorSquared: double.infinity,
        split: _fitStableSplit(points, first, last),
      );
    }
    if (error > maxError) {
      maxError = error;
      split = first + i;
    }
  }
  return (errorSquared: math.max(0.0, maxError), split: split);
}

int _fitStableSplit(Float64List points, int first, int last) {
  if (last - first <= 2) return first + 1;

  var total = 0.0;
  for (var i = first + 1; i <= last; ++i) {
    final a = (i - 1) << 1;
    final b = i << 1;
    final dx = points[b] - points[a];
    final dy = points[b + 1] - points[a + 1];
    total += math.sqrt(dx * dx + dy * dy);
  }
  if (total <= _pathEpsilon || !total.isFinite) {
    return (first + last) >> 1;
  }

  final target = total * 0.5;
  var traversed = 0.0;
  for (var i = first + 1; i < last; ++i) {
    final a = (i - 1) << 1;
    final b = i << 1;
    final dx = points[b] - points[a];
    final dy = points[b + 1] - points[a + 1];
    traversed += math.sqrt(dx * dx + dy * dy);
    if (traversed >= target) return i;
  }
  return (first + last) >> 1;
}

bool _reparameterizeFit(
  Float64List points,
  int first,
  int last,
  Float64List u,
  _FitCurve curve,
) {
  final count = last - first + 1;
  if (count <= 2) return false;

  const minGap = 1e-9;
  var previous = 0.0;
  for (var i = 1; i < count - 1; ++i) {
    final point = (first + i) << 1;
    final next = _fitNewtonParameter(
      curve,
      points[point],
      points[point + 1],
      u[i],
    );
    final upper = 1.0 - (count - 1 - i) * minGap;
    if (!next.isFinite || next <= previous + minGap || next >= upper) {
      return false;
    }
    u[i] = next;
    previous = next;
  }
  u[0] = 0.0;
  u[count - 1] = 1.0;
  return true;
}

double _fitNewtonParameter(_FitCurve c, double px, double py, double t) {
  final q = _evaluateFitCurve(c, t);
  final mt = 1.0 - t;
  final dx =
      3.0 * mt * mt * (c.c1x - c.p0x) +
      6.0 * mt * t * (c.c2x - c.c1x) +
      3.0 * t * t * (c.p3x - c.c2x);
  final dy =
      3.0 * mt * mt * (c.c1y - c.p0y) +
      6.0 * mt * t * (c.c2y - c.c1y) +
      3.0 * t * t * (c.p3y - c.c2y);
  final ddx = 6.0 * mt * (c.c2x - 2.0 * c.c1x + c.p0x) + 6.0 * t * (c.p3x - 2.0 * c.c2x + c.c1x);
  final ddy = 6.0 * mt * (c.c2y - 2.0 * c.c1y + c.p0y) + 6.0 * t * (c.p3y - 2.0 * c.c2y + c.c1y);
  final qx = q.$1 - px;
  final qy = q.$2 - py;
  final numerator = qx * dx + qy * dy;
  final denominator = dx * dx + dy * dy + qx * ddx + qy * ddy;

  if (!numerator.isFinite || !denominator.isFinite) return t;
  final scale = dx * dx + dy * dy + (qx * ddx).abs() + (qy * ddy).abs();
  if (denominator.abs() <= math.max(_pathEpsilon, scale * 1e-12)) return t;

  final next = t - numerator / denominator;
  return next.isFinite ? next : t;
}

(double, double) _evaluateFitCurve(_FitCurve c, double t) {
  final mt = 1.0 - t;
  final mt2 = mt * mt;
  final t2 = t * t;
  return (
    mt2 * mt * c.p0x + 3.0 * mt2 * t * c.c1x + 3.0 * mt * t2 * c.c2x + t2 * t * c.p3x,
    mt2 * mt * c.p0y + 3.0 * mt2 * t * c.c1y + 3.0 * mt * t2 * c.c2y + t2 * t * c.p3y,
  );
}

void _appendFitCurve(GPath path, _FitCurve curve) {
  path.cubicTo(
    curve.c1x,
    curve.c1y,
    curve.c2x,
    curve.c2y,
    curve.p3x,
    curve.p3y,
  );
}

double _pointSegmentDistanceSquared(
  double px,
  double py,
  double ax,
  double ay,
  double bx,
  double by,
) {
  final dx = bx - ax;
  final dy = by - ay;
  final lengthSquared = dx * dx + dy * dy;
  if (lengthSquared <= _pathEpsilon) {
    final qx = px - ax;
    final qy = py - ay;
    return qx * qx + qy * qy;
  }
  final t = (((px - ax) * dx + (py - ay) * dy) / lengthSquared).clamp(0.0, 1.0).toDouble();
  final qx = px - (ax + dx * t);
  final qy = py - (ay + dy * t);
  return qx * qx + qy * qy;
}

final class _FitTask {
  const _FitTask(
    this.first,
    this.last,
    this.t1x,
    this.t1y,
    this.t2x,
    this.t2y,
  );

  final int first;
  final int last;
  final double t1x;
  final double t1y;
  final double t2x;
  final double t2y;
}

final class _FitCurve {
  const _FitCurve(
    this.p0x,
    this.p0y,
    this.c1x,
    this.c1y,
    this.c2x,
    this.c2y,
    this.p3x,
    this.p3y,
  );

  final double p0x;
  final double p0y;
  final double c1x;
  final double c1y;
  final double c2x;
  final double c2y;
  final double p3x;
  final double p3y;
}

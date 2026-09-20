// Copyright (c) 2026 GraphX by roipeker.

part of '../graphx_paths.dart';

final class _PreparedPath {
  _PreparedPath({
    required this.kinds,
    required this.segmentContours,
    required this.coords,
    required this.segmentDistances,
    required this.lutOffsets,
    required this.samples,
    required this.contourLengths,
    required this.contourStartDistances,
    required this.contourEndDistances,
    required this.contourFirstSegments,
    required this.contourLastSegments,
    required this.contourClosed,
    required this.contourStarts,
    required this.bounds,
    required this.totalLength,
  });

  final Int32List kinds;
  final Int32List segmentContours;
  final Float64List coords;
  final Float64List segmentDistances;
  final Int32List lutOffsets;
  final Float64List samples;
  final Float64List contourLengths;
  final Float64List contourStartDistances;
  final Float64List contourEndDistances;
  final Int32List contourFirstSegments;
  final Int32List contourLastSegments;
  final Uint8List contourClosed;
  final Float64List contourStarts;
  final GBounds bounds;
  final double totalLength;

  int get segmentCount => kinds.length;
  int get contourCount => contourLengths.length;
}

final class _SampleCursor {
  int segment = -1;
  double t = 0.0;
}

final class _BuildContour {
  _BuildContour(this.startX, this.startY);

  final double startX;
  final double startY;
  int firstSegment = -1;
  int lastSegment = -1;
  bool closed = false;
  double length = 0.0;
}

final class _BuildSegment {
  _BuildSegment._(this.kind, this.contour, this.coords);

  factory _BuildSegment.line(int contour, double x0, double y0, double x1, double y1) =>
      _BuildSegment._(_segmentLine, contour, <double>[x0, y0, 0, 0, 0, 0, x1, y1]);

  factory _BuildSegment.quadratic(
    int contour,
    double x0,
    double y0,
    double cx,
    double cy,
    double x1,
    double y1,
  ) => _BuildSegment._(
    _segmentQuadratic,
    contour,
    <double>[x0, y0, cx, cy, 0, 0, x1, y1],
  );

  factory _BuildSegment.cubic(
    int contour,
    double x0,
    double y0,
    double c1x,
    double c1y,
    double c2x,
    double c2y,
    double x1,
    double y1,
  ) => _BuildSegment._(
    _segmentCubic,
    contour,
    <double>[x0, y0, c1x, c1y, c2x, c2y, x1, y1],
  );

  final int kind;
  final int contour;
  final List<double> coords;
}

double _appendSegmentSamples(_BuildSegment segment, double tolerance, List<double> target) {
  final c = segment.coords;
  target.add(0);
  target.add(0);
  target.add(c[0]);
  target.add(c[1]);
  if (segment.kind == _segmentLine) {
    final length = _distance(c[0], c[1], c[6], c[7]);
    target.add(1);
    target.add(length);
    target.add(c[6]);
    target.add(c[7]);
    return length;
  }
  if (segment.kind == _segmentQuadratic) {
    return _flattenQuadratic(
      c[0],
      c[1],
      c[2],
      c[3],
      c[6],
      c[7],
      0,
      1,
      tolerance,
      0,
      target,
      0,
    );
  }
  return _flattenCubic(
    c[0],
    c[1],
    c[2],
    c[3],
    c[4],
    c[5],
    c[6],
    c[7],
    0,
    1,
    tolerance,
    0,
    target,
    0,
  );
}

double _flattenQuadratic(
  double x0,
  double y0,
  double cx,
  double cy,
  double x1,
  double y1,
  double t0,
  double t1,
  double tolerance,
  int depth,
  List<double> target,
  double cumulative,
) {
  final chord = _distance(x0, y0, x1, y1);
  final polygon = _distance(x0, y0, cx, cy) + _distance(cx, cy, x1, y1);
  if (depth >= _maxSubdivisionDepth || polygon - chord <= tolerance) {
    final next = cumulative + chord;
    target.add(t1);
    target.add(next);
    target.add(x1);
    target.add(y1);
    return next;
  }
  final x01 = (x0 + cx) * .5;
  final y01 = (y0 + cy) * .5;
  final x12 = (cx + x1) * .5;
  final y12 = (cy + y1) * .5;
  final xm = (x01 + x12) * .5;
  final ym = (y01 + y12) * .5;
  final tm = (t0 + t1) * .5;
  final middle = _flattenQuadratic(
    x0,
    y0,
    x01,
    y01,
    xm,
    ym,
    t0,
    tm,
    tolerance,
    depth + 1,
    target,
    cumulative,
  );
  return _flattenQuadratic(
    xm,
    ym,
    x12,
    y12,
    x1,
    y1,
    tm,
    t1,
    tolerance,
    depth + 1,
    target,
    middle,
  );
}

double _flattenCubic(
  double x0,
  double y0,
  double c1x,
  double c1y,
  double c2x,
  double c2y,
  double x1,
  double y1,
  double t0,
  double t1,
  double tolerance,
  int depth,
  List<double> target,
  double cumulative,
) {
  final chord = _distance(x0, y0, x1, y1);
  final polygon =
      _distance(x0, y0, c1x, c1y) + _distance(c1x, c1y, c2x, c2y) + _distance(c2x, c2y, x1, y1);
  if (depth >= _maxSubdivisionDepth || polygon - chord <= tolerance) {
    final next = cumulative + chord;
    target.add(t1);
    target.add(next);
    target.add(x1);
    target.add(y1);
    return next;
  }
  final x01 = (x0 + c1x) * .5;
  final y01 = (y0 + c1y) * .5;
  final x12 = (c1x + c2x) * .5;
  final y12 = (c1y + c2y) * .5;
  final x23 = (c2x + x1) * .5;
  final y23 = (c2y + y1) * .5;
  final xa = (x01 + x12) * .5;
  final ya = (y01 + y12) * .5;
  final xb = (x12 + x23) * .5;
  final yb = (y12 + y23) * .5;
  final xm = (xa + xb) * .5;
  final ym = (ya + yb) * .5;
  final tm = (t0 + t1) * .5;
  final middle = _flattenCubic(
    x0,
    y0,
    x01,
    y01,
    xa,
    ya,
    xm,
    ym,
    t0,
    tm,
    tolerance,
    depth + 1,
    target,
    cumulative,
  );
  return _flattenCubic(
    xm,
    ym,
    xb,
    yb,
    x23,
    y23,
    x1,
    y1,
    tm,
    t1,
    tolerance,
    depth + 1,
    target,
    middle,
  );
}

void _includeQuadraticBounds(
  GBounds bounds,
  double x0,
  double y0,
  double cx,
  double cy,
  double x1,
  double y1,
) {
  bounds.includePoint(x0, y0);
  bounds.includePoint(x1, y1);
  final dx = x0 - 2 * cx + x1;
  if (dx.abs() > _pathEpsilon) {
    final t = (x0 - cx) / dx;
    if (t > 0 && t < 1) _includeQuadraticAt(bounds, x0, y0, cx, cy, x1, y1, t);
  }
  final dy = y0 - 2 * cy + y1;
  if (dy.abs() > _pathEpsilon) {
    final t = (y0 - cy) / dy;
    if (t > 0 && t < 1) _includeQuadraticAt(bounds, x0, y0, cx, cy, x1, y1, t);
  }
}

void _includeQuadraticAt(
  GBounds bounds,
  double x0,
  double y0,
  double cx,
  double cy,
  double x1,
  double y1,
  double t,
) {
  final u = 1 - t;
  bounds.includePoint(
    u * u * x0 + 2 * u * t * cx + t * t * x1,
    u * u * y0 + 2 * u * t * cy + t * t * y1,
  );
}

void _includeCubicBounds(
  GBounds bounds,
  double x0,
  double y0,
  double c1x,
  double c1y,
  double c2x,
  double c2y,
  double x1,
  double y1,
) {
  bounds.includePoint(x0, y0);
  bounds.includePoint(x1, y1);
  final roots = <double>[];
  _appendCubicDerivativeRoots(x0, c1x, c2x, x1, roots);
  _appendCubicDerivativeRoots(y0, c1y, c2y, y1, roots);
  for (final t in roots) {
    if (t <= 0 || t >= 1) continue;
    final u = 1 - t;
    final uu = u * u;
    final tt = t * t;
    bounds.includePoint(
      uu * u * x0 + 3 * uu * t * c1x + 3 * u * tt * c2x + tt * t * x1,
      uu * u * y0 + 3 * uu * t * c1y + 3 * u * tt * c2y + tt * t * y1,
    );
  }
}

void _appendCubicDerivativeRoots(
  double p0,
  double p1,
  double p2,
  double p3,
  List<double> target,
) {
  final a = -p0 + 3 * p1 - 3 * p2 + p3;
  final b = 2 * (p0 - 2 * p1 + p2);
  final c = p1 - p0;
  if (a.abs() <= _pathEpsilon) {
    if (b.abs() > _pathEpsilon) target.add(-c / b);
    return;
  }
  final discriminant = b * b - 4 * a * c;
  if (discriminant < 0) return;
  final root = math.sqrt(math.max(0, discriminant));
  final denominator = 2 * a;
  target.add((-b + root) / denominator);
  target.add((-b - root) / denominator);
}

double _distance(double x0, double y0, double x1, double y1) {
  final dx = x1 - x0;
  final dy = y1 - y0;
  return math.sqrt(dx * dx + dy * dy);
}

void _checkPoint(double x, double y) {
  if (!x.isFinite || !y.isFinite) {
    throw ArgumentError.value(<double>[x, y], 'point', 'Coordinates must be finite.');
  }
}

void _checkFinite(double value, String name) {
  if (!value.isFinite) throw ArgumentError.value(value, name, 'Must be finite.');
}

void _checkContourIndex(int contour, int count) {
  if (contour < 0 || contour >= count) {
    throw RangeError.range(contour, 0, math.max(0, count - 1), 'contour');
  }
}

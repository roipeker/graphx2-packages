// Copyright (c) 2026 GraphX by roipeker.

part of '../graphx_paths.dart';

const double _splineCoincidentDistanceSquared = 1e-12;

GPath _buildSplinePath(
  List<GPoint> points, {
  required bool closed,
  required double tolerance,
}) {
  final path = GPath(tolerance: tolerance);
  final count = points.length;
  if (count == 0) return path;

  for (final point in points) {
    _checkPoint(point.x, point.y);
  }

  final first = points.first;
  path.moveTo(first.x, first.y);
  if (count == 1) {
    if (closed) path.close();
    return path;
  }

  if (count == 2) {
    final second = points[1];
    path.lineTo(second.x, second.y);
    if (closed) path.close();
    return path;
  }

  final segmentCount = closed ? count : count - 1;
  for (var i = 0; i < segmentCount; ++i) {
    final p1 = points[i];
    final p2 = points[(i + 1) % count];

    final p0x = closed || i > 0 ? points[(i - 1 + count) % count].x : 2.0 * p1.x - p2.x;
    final p0y = closed || i > 0 ? points[(i - 1 + count) % count].y : 2.0 * p1.y - p2.y;
    final p3x = closed || i + 2 < count ? points[(i + 2) % count].x : 2.0 * p2.x - p1.x;
    final p3y = closed || i + 2 < count ? points[(i + 2) % count].y : 2.0 * p2.y - p1.y;

    _appendCentripetalSplineSegment(
      path,
      p0x,
      p0y,
      p1.x,
      p1.y,
      p2.x,
      p2.y,
      p3x,
      p3y,
    );
  }

  if (closed) path.close();
  return path;
}

void _appendCentripetalSplineSegment(
  GPath path,
  double p0x,
  double p0y,
  double p1x,
  double p1y,
  double p2x,
  double p2y,
  double p3x,
  double p3y,
) {
  final d01Squared = _distanceSquared(p0x, p0y, p1x, p1y);
  final d12Squared = _distanceSquared(p1x, p1y, p2x, p2y);
  final d23Squared = _distanceSquared(p2x, p2y, p3x, p3y);

  if (d12Squared <= _splineCoincidentDistanceSquared ||
      !d12Squared.isFinite ||
      d01Squared <= _splineCoincidentDistanceSquared ||
      d23Squared <= _splineCoincidentDistanceSquared ||
      !d01Squared.isFinite ||
      !d23Squared.isFinite) {
    path.lineTo(p2x, p2y);
    return;
  }

  // Centripetal Catmull-Rom uses alpha = 0.5, so each knot increment is
  // |Pi+1 - Pi|^0.5. `_distanceSquared` stores |d|^2, hence the fourth root.
  final dt01 = math.sqrt(math.sqrt(d01Squared));
  final dt12 = math.sqrt(math.sqrt(d12Squared));
  final dt23 = math.sqrt(math.sqrt(d23Squared));
  final dt02 = dt01 + dt12;
  final dt13 = dt12 + dt23;

  if (!dt01.isFinite ||
      !dt12.isFinite ||
      !dt23.isFinite ||
      dt01 <= 0.0 ||
      dt12 <= 0.0 ||
      dt23 <= 0.0 ||
      !dt02.isFinite ||
      !dt13.isFinite) {
    path.lineTo(p2x, p2y);
    return;
  }

  // Tangents are expressed in the local [0, 1] parameter of P1 -> P2.
  final m1x = dt12 * ((p1x - p0x) / dt01 - (p2x - p0x) / dt02 + (p2x - p1x) / dt12);
  final m1y = dt12 * ((p1y - p0y) / dt01 - (p2y - p0y) / dt02 + (p2y - p1y) / dt12);
  final m2x = dt12 * ((p2x - p1x) / dt12 - (p3x - p1x) / dt13 + (p3x - p2x) / dt23);
  final m2y = dt12 * ((p2y - p1y) / dt12 - (p3y - p1y) / dt13 + (p3y - p2y) / dt23);

  final c1x = p1x + m1x / 3.0;
  final c1y = p1y + m1y / 3.0;
  final c2x = p2x - m2x / 3.0;
  final c2y = p2y - m2y / 3.0;

  if (!c1x.isFinite || !c1y.isFinite || !c2x.isFinite || !c2y.isFinite) {
    path.lineTo(p2x, p2y);
    return;
  }

  path.cubicTo(c1x, c1y, c2x, c2y, p2x, p2y);
}

double _distanceSquared(double ax, double ay, double bx, double by) {
  final dx = bx - ax;
  final dy = by - ay;
  return dx * dx + dy * dy;
}

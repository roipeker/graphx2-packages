// Copyright (c) 2026 GraphX by roipeker.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:graphx/graphx.dart';
import 'package:graphx_paths/graphx_paths.dart';

void main() {
  group('GPath.fit', () {
    test('preserves empty, single and two-point endpoints', () {
      expect(GPath.fit(const <GPoint>[]).isEmpty, isTrue);

      final single = GPath.fit(<GPoint>[GPoint(4, 7)]);
      expect(single.contourCount, 1);
      expect(single.length, 0);
      expect(single.pointAt(0).x, 4);
      expect(single.pointAt(0).y, 7);

      final two = GPath.fit(<GPoint>[GPoint(2, 3), GPoint(12, -4)]);
      expect(two.pointAt(0).x, 2);
      expect(two.pointAt(1).x, 12);
      expect(two.segmentCount, 1);
    });

    test('ignores repeated points and stays finite', () {
      final path = GPath.fit(<GPoint>[
        GPoint(0, 0),
        GPoint(0, 0),
        GPoint(10, 10),
        GPoint(10, 10),
        GPoint(20, 0),
      ], tolerance: .5);
      final p = GPoint();
      final t = GPoint();
      for (var i = 0; i <= 20; i++) {
        path.sampleAt(i / 20, p, t);
        expect(p.x.isFinite && p.y.isFinite, isTrue);
        expect(t.x.isFinite && t.y.isFinite, isTrue);
      }
    });

    test('straight dense samples collapse to a compact curve', () {
      final points = List<GPoint>.generate(
        101,
        (i) => GPoint(i.toDouble(), i * .5),
      );
      final path = GPath.fit(points, tolerance: .01);
      expect(path.segmentCount, lessThanOrEqualTo(2));
      expect(path.pointAt(0).x, closeTo(0, 1e-9));
      expect(path.pointAt(1).x, closeTo(100, 1e-9));
    });

    test('sharp corner is preserved within fit tolerance', () {
      const tolerance = .4;
      final points = <GPoint>[
        GPoint(0, 0),
        GPoint(20, 0),
        GPoint(40, 0),
        GPoint(40, 20),
        GPoint(40, 40),
      ];
      final path = GPath.fit(points, tolerance: tolerance, pathTolerance: .03);
      final closest = GPoint();
      for (final source in points) {
        path.closestPoint(source.x, source.y, closest);
        final dx = closest.x - source.x;
        final dy = closest.y - source.y;
        expect(math.sqrt(dx * dx + dy * dy), lessThanOrEqualTo(tolerance + .04));
      }
      expect(path.segmentCount, greaterThan(1));
    });

    test('sample-to-curve geometric error stays within tolerance', () {
      const tolerance = 1.25;
      final points = List<GPoint>.generate(180, (i) {
        final x = i * 2.0;
        final y = math.sin(i * .075) * 38 + math.sin(i * .31) * 1.2;
        return GPoint(x, y);
      });
      final path = GPath.fit(
        points,
        tolerance: tolerance,
        pathTolerance: .05,
      );
      final closest = GPoint();
      var maxError = 0.0;
      for (final source in points) {
        path.closestPoint(source.x, source.y, closest);
        final dx = closest.x - source.x;
        final dy = closest.y - source.y;
        maxError = math.max(maxError, math.sqrt(dx * dx + dy * dy));
      }
      expect(maxError, lessThanOrEqualTo(tolerance + .08));
    });

    test('extreme coordinate scales remain finite', () {
      final path = GPath.fit(<GPoint>[
        GPoint(1e9, -1e9),
        GPoint(1e9 + 1000, -1e9 + 300),
        GPoint(1e9 + 2500, -1e9 - 200),
        GPoint(1e9 + 4000, -1e9 + 800),
      ], tolerance: 2);
      final p = path.pointAt(.5);
      expect(p.x.isFinite && p.y.isFinite, isTrue);
    });
  });

  group('GPath.fit closed robustness', () {
    test('camera-like contour cannot emit a giant seam spike', () {
      final points = <GPoint>[
        GPoint(8, 34),
        GPoint(18, 24),
        GPoint(42, 24),
        GPoint(42, 10),
        GPoint(76, 10),
        GPoint(76, 24),
        GPoint(112, 24),
        GPoint(122, 34),
        GPoint(122, 88),
        GPoint(116, 98),
        GPoint(108, 100),
        GPoint(92, 96),
        GPoint(78, 100),
        GPoint(18, 100),
        GPoint(8, 90),
      ];
      _expectStableClosedFit(points, tolerance: 1.3);
    });

    test('rounded rectangle with protrusion stays local', () {
      final points = <GPoint>[
        GPoint(12, 0),
        GPoint(88, 0),
        GPoint(96, 4),
        GPoint(100, 12),
        GPoint(100, 30),
        GPoint(116, 34),
        GPoint(100, 40),
        GPoint(100, 88),
        GPoint(96, 96),
        GPoint(88, 100),
        GPoint(12, 100),
        GPoint(4, 96),
        GPoint(0, 88),
        GPoint(0, 12),
        GPoint(4, 4),
      ];
      _expectStableClosedFit(points, tolerance: 1.0);
    });

    test('circle and noisy loop remain stable and deterministic', () {
      final circle = List<GPoint>.generate(64, (i) {
        final a = i * math.pi * 2 / 64;
        return GPoint(math.cos(a) * 80, math.sin(a) * 80);
      }, growable: false);
      _expectStableClosedFit(circle, tolerance: .8);

      final noisy = List<GPoint>.generate(96, (i) {
        final a = i * math.pi * 2 / 96;
        final r = 70 + math.sin(i * 2.17) * 1.4 + math.cos(i * .71) * .8;
        return GPoint(math.cos(a) * r, math.sin(a) * r);
      }, growable: false);
      _expectStableClosedFit(noisy, tolerance: 1.5);
    });

    test('collinear runs, abrupt turns and uneven spacing stay finite', () {
      final points = <GPoint>[
        GPoint(0, 0),
        GPoint(0.0000001, 0),
        GPoint(20, 0),
        GPoint(60, 0),
        GPoint(140, 0),
        GPoint(140, 4),
        GPoint(140, 45),
        GPoint(140, 100),
        GPoint(80, 100),
        GPoint(20, 100),
        GPoint(0, 100),
        GPoint(0, 30),
      ];
      _expectStableClosedFit(points, tolerance: .75);
    });

    test('duplicate, near-duplicate and tiny closed contours are deterministic', () {
      final points = <GPoint>[
        GPoint(0, 0),
        GPoint(0, 0),
        GPoint(1e-8, 0),
        GPoint(2, 0),
        GPoint(2, 2),
        GPoint(0, 2),
        GPoint(0, 1e-8),
        GPoint(0, 0),
      ];
      _expectStableClosedFit(points, tolerance: .1);

      final tiny = GPath.fit(
        <GPoint>[GPoint(3, 4), GPoint(3, 4), GPoint(3 + 1e-10, 4)],
        closed: true,
        tolerance: .25,
      );
      expect(tiny.pointAt(0).x.isFinite, isTrue);
      expect(tiny.pointAt(0).y.isFinite, isTrue);
    });

    test('high-curvature authored seam uses cyclic continuity', () {
      final points = <GPoint>[
        GPoint(0, 0), // Intentionally place the seam at the sharpest turn.
        GPoint(48, 4),
        GPoint(82, 30),
        GPoint(72, 76),
        GPoint(22, 88),
        GPoint(-18, 52),
      ];
      final path = _expectStableClosedFit(points, tolerance: 1.0);
      final a = path.tangentAt(0);
      final b = path.tangentAt(1);
      final dot = a.x * b.x + a.y * b.y;
      expect(dot, greaterThan(.98));
    });
  });

  group('GPath.simplifyPoints', () {
    test('removes duplicate and collinear sampled points', () {
      final simplified = GPath.simplifyPoints(<GPoint>[
        GPoint(0, 0),
        GPoint(0, 0),
        GPoint(5, 0),
        GPoint(10, 0),
        GPoint(10, 0),
      ], tolerance: .01);
      expect(simplified, hasLength(2));
      expect(simplified.first.x, 0);
      expect(simplified.last.x, 10);
    });

    test('preserves a sharp corner outside tolerance', () {
      final simplified = GPath.simplifyPoints(<GPoint>[
        GPoint(0, 0),
        GPoint(10, 0),
        GPoint(10, 20),
        GPoint(20, 20),
      ], tolerance: 1);
      expect(simplified.length, greaterThanOrEqualTo(3));
    });

    test('handles ten thousand dense samples deterministically', () {
      final points = List<GPoint>.generate(10000, (i) {
        return GPoint(i * .2, math.sin(i * .01) * 30);
      }, growable: false);
      final simplified = GPath.simplifyPoints(points, tolerance: .8);
      expect(simplified.length, lessThan(points.length));
      expect(simplified.first.x, points.first.x);
      expect(simplified.last.x, points.last.x);
    });
  });

  group('GPathCubics', () {
    test('line and quadratic degree elevation are exact', () {
      final path = GPath().moveTo(0, 0).lineTo(9, 0).quadraticTo(12, 6, 18, 0);
      final cubics = path.toCubics();
      expect(cubics.segmentCount, 2);
      expect(cubics.coordinateAt(2), closeTo(3, 1e-12));
      expect(cubics.coordinateAt(4), closeTo(6, 1e-12));
      final q = 8;
      expect(cubics.coordinateAt(q + 2), closeTo(11, 1e-12));
      expect(cubics.coordinateAt(q + 3), closeTo(4, 1e-12));
      expect(cubics.coordinateAt(q + 4), closeTo(14, 1e-12));
      expect(cubics.coordinateAt(q + 5), closeTo(4, 1e-12));
    });

    test('preserves contour boundaries, empties and closed state', () {
      final path = GPath()
          .moveTo(0, 0)
          .lineTo(10, 0)
          .close()
          .moveTo(15, 5)
          .moveTo(20, 0)
          .cubicTo(25, 5, 30, -5, 40, 0);
      final cubics = path.toCubics();
      expect(cubics.contourCount, 3);
      expect(cubics.isContourClosed(0), isTrue);
      expect(cubics.isContourClosed(1), isFalse);
      expect(cubics.isContourClosed(2), isFalse);
      expect(cubics.contourSegmentCount(0), 2);
      expect(cubics.contourSegmentCount(1), 0);
      expect(cubics.contourSegmentCount(2), 1);
      expect(cubics.contourStartSegment(1), cubics.contourEndSegment(1));
    });

    test('exact subdivision preserves endpoints and join', () {
      final path = GPath().moveTo(0, 0).cubicTo(10, 20, 30, -10, 40, 0);
      final split = path.toCubics().subdivide(0, .35);
      expect(split.segmentCount, 2);
      expect(split.coordinateAt(6), closeTo(split.coordinateAt(8), 1e-12));
      expect(split.coordinateAt(7), closeTo(split.coordinateAt(9), 1e-12));
      expect(split.coordinateAt(0), 0);
      expect(split.coordinateAt(15), 0);
      expect(split.coordinateAt(14), 40);

      final copy = Float64List(split.coordinateCount);
      split.copyCoordinatesInto(copy);
      expect(copy[8], split.coordinateAt(8));
    });
  });

  test('combined contour sampling matches separate queries', () {
    final path = GPath().moveTo(0, 0).cubicTo(20, 30, 50, -10, 80, 0);
    final p = GPoint();
    final t = GPoint();
    final ep = GPoint();
    final et = GPoint();
    final d = path.contourLength(0) * .42;
    path.sampleAtContourDistance(0, d, p, t);
    path.pointAtContourDistance(0, d, ep);
    path.tangentAtContourDistance(0, d, et);
    expect(p.x, closeTo(ep.x, 1e-10));
    expect(p.y, closeTo(ep.y, 1e-10));
    expect(t.x, closeTo(et.x, 1e-10));
    expect(t.y, closeTo(et.y, 1e-10));
  });
}

GPath _expectStableClosedFit(
  List<GPoint> points, {
  required double tolerance,
}) {
  final path = GPath.fit(
    points,
    closed: true,
    tolerance: tolerance,
    pathTolerance: .02,
  );
  final repeated = GPath.fit(
    points,
    closed: true,
    tolerance: tolerance,
    pathTolerance: .02,
  );

  final cubics = path.toCubics();
  final repeatedCubics = repeated.toCubics();
  expect(cubics.contourCount, 1);
  expect(cubics.isContourClosed(0), isTrue);
  expect(cubics.coordinateCount, repeatedCubics.coordinateCount);

  var minX = double.infinity;
  var minY = double.infinity;
  var maxX = double.negativeInfinity;
  var maxY = double.negativeInfinity;
  for (final point in points) {
    minX = math.min(minX, point.x);
    minY = math.min(minY, point.y);
    maxX = math.max(maxX, point.x);
    maxY = math.max(maxY, point.y);
  }
  final dx = maxX - minX;
  final dy = maxY - minY;
  final diagonal = math.sqrt(dx * dx + dy * dy);
  final margin = math.max(tolerance * 16, diagonal * 2);

  for (var i = 0; i < cubics.coordinateCount; i += 2) {
    final x = cubics.coordinateAt(i);
    final y = cubics.coordinateAt(i + 1);
    expect(x.isFinite && y.isFinite, isTrue);
    expect(x, inInclusiveRange(minX - margin, maxX + margin));
    expect(y, inInclusiveRange(minY - margin, maxY + margin));
    expect(cubics.coordinateAt(i), repeatedCubics.coordinateAt(i));
    expect(cubics.coordinateAt(i + 1), repeatedCubics.coordinateAt(i + 1));
  }

  final closest = GPoint();
  for (final source in points) {
    path.closestPoint(source.x, source.y, closest);
    final ex = closest.x - source.x;
    final ey = closest.y - source.y;
    expect(
      math.sqrt(ex * ex + ey * ey),
      lessThanOrEqualTo(tolerance + .12),
    );
  }

  final start = path.pointAt(0);
  final end = path.pointAt(1);
  expect(start.x, closeTo(end.x, 1e-8));
  expect(start.y, closeTo(end.y, 1e-8));
  return path;
}

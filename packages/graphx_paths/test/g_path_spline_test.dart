// Copyright (c) 2026 GraphX by roipeker.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:graphx/graphx.dart';
import 'package:graphx_paths/graphx_paths.dart';

void main() {
  group('GPath.spline', () {
    test('passes through every supplied waypoint in order', () {
      final points = <GPoint>[
        GPoint(0, 100),
        GPoint(100, 30),
        GPoint(250, 80),
        GPoint(400, 0),
      ];
      final path = GPath.spline(points, tolerance: .02);

      expect(path.segmentCount, points.length - 1);
      for (final waypoint in points) {
        final nearest = path.closestPoint(waypoint.x, waypoint.y);
        expect(nearest.x, closeTo(waypoint.x, 1e-7));
        expect(nearest.y, closeTo(waypoint.y, 1e-7));
      }
      expect(path.pointAt(0).x, closeTo(points.first.x, 1e-9));
      expect(path.pointAt(1).x, closeTo(points.last.x, 1e-9));
    });

    test('0, 1, and 2 point inputs have deterministic fallback semantics', () {
      final empty = GPath.spline(const <GPoint>[]);
      expect(empty.isEmpty, isTrue);
      expect(empty.length, 0);

      final one = GPath.spline(<GPoint>[GPoint(7, 9)]);
      expect(one.contourCount, 1);
      expect(one.segmentCount, 0);
      expect(one.length, 0);
      expect(one.pointAt(.5).x, 7);
      expect(one.pointAt(.5).y, 9);

      final two = GPath.spline(<GPoint>[GPoint(0, 0), GPoint(30, 40)]);
      expect(two.segmentCount, 1);
      expect(two.length, closeTo(50, 1e-9));
      expect(two.pointAt(.5).x, closeTo(15, 1e-9));
      expect(two.pointAt(.5).y, closeTo(20, 1e-9));
    });

    test('duplicates and nearly coincident points stay finite', () {
      final path = GPath.spline(<GPoint>[
        GPoint(0, 0),
        GPoint(80, 30),
        GPoint(80, 30),
        GPoint(80.00000001, 30.00000001),
        GPoint(180, -20),
      ]);

      expect(path.length.isFinite, isTrue);
      for (var i = 0; i <= 100; ++i) {
        final progress = i / 100;
        final point = path.pointAt(progress);
        final tangent = path.tangentAt(progress);
        expect(point.x.isFinite && point.y.isFinite, isTrue);
        expect(tangent.x.isFinite && tangent.y.isFinite, isTrue);
      }
    });

    test('closed spline closes continuously through the seam', () {
      final points = <GPoint>[
        GPoint(0, 0),
        GPoint(120, 10),
        GPoint(140, 100),
        GPoint(20, 130),
      ];
      final path = GPath.spline(points, closed: true, tolerance: .02);

      final start = path.pointAt(0);
      final seam = path.pointAt(1);
      expect(start.x, closeTo(seam.x, 1e-9));
      expect(start.y, closeTo(seam.y, 1e-9));

      for (final waypoint in points) {
        final nearest = path.closestPoint(waypoint.x, waypoint.y);
        expect(nearest.x, closeTo(waypoint.x, 1e-7));
        expect(nearest.y, closeTo(waypoint.y, 1e-7));
      }

      final before = path.tangentAt(.99999);
      final after = path.tangentAt(.00001);
      final dot = before.x * after.x + before.y * after.y;
      expect(dot, greaterThan(.995));
    });

    test('uneven waypoint spacing remains stable', () {
      final path = GPath.spline(<GPoint>[
        GPoint(0, 0),
        GPoint(2, 35),
        GPoint(180, 45),
        GPoint(190, -60),
        GPoint(600, 0),
      ]);

      expect(path.length, greaterThan(600));
      for (var i = 0; i <= 200; ++i) {
        final tangent = path.tangentAt(i / 200);
        final magnitude = math.sqrt(tangent.x * tangent.x + tangent.y * tangent.y);
        expect(magnitude.isFinite, isTrue);
        expect(magnitude, anyOf(closeTo(1, 1e-8), 0));
      }
    });

    test('closed two-point spline is a deterministic out-and-back loop', () {
      final path = GPath.spline(
        <GPoint>[GPoint(0, 0), GPoint(10, 0)],
        closed: true,
      );
      expect(path.length, closeTo(20, 1e-9));
      expect(path.pointAt(1).x, closeTo(0, 1e-9));
      expect(path.pointAt(1).y, closeTo(0, 1e-9));
    });

    test('invalid waypoint coordinates fail early', () {
      expect(
        () => GPath.spline(<GPoint>[GPoint(0, 0), GPoint(double.nan, 2)]),
        throwsArgumentError,
      );
    });
  });
}

// Copyright (c) 2026 GraphX by roipeker.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:graphx/graphx.dart';
import 'package:graphx_paths/graphx_paths.dart';

void main() {
  group('GPath sampling', () {
    test('line sampling is arc-length based and can reuse output', () {
      final path = GPath().moveTo(0, 0).lineTo(90, 0).lineTo(100, 0);
      final out = GPoint();
      expect(path.length, closeTo(100, 1e-9));
      expect(identical(path.pointAt(.5, out), out), isTrue);
      expect(out.x, closeTo(50, 1e-9));
      expect(out.y, 0);
      path.tangentAt(.5, out);
      expect(out.x, closeTo(1, 1e-9));
      expect(out.y, closeTo(0, 1e-9));
      path.normalAt(.5, out);
      expect(out.x, closeTo(0, 1e-9));
      expect(out.y, closeTo(1, 1e-9));
    });

    test('quadratic and cubic endpoints and bounds are stable', () {
      final path = GPath(
        tolerance: .05,
      ).moveTo(0, 0).quadraticTo(50, 100, 100, 0).cubicTo(130, -80, 170, 80, 200, 0);
      final start = path.pointAt(0);
      final end = path.pointAt(1);
      final bounds = path.bounds;
      expect(start.x, closeTo(0, 1e-9));
      expect(start.y, closeTo(0, 1e-9));
      expect(end.x, closeTo(200, 1e-9));
      expect(end.y, closeTo(0, 1e-9));
      expect(bounds.x1, closeTo(0, 1e-9));
      expect(bounds.x2, closeTo(200, 1e-9));
      expect(bounds.y2, greaterThanOrEqualTo(50));
      expect(bounds.y1, lessThan(0));
    });

    test('multiple contours do not count move gaps', () {
      final path = GPath().moveTo(0, 0).lineTo(100, 0).moveTo(1000, 50).lineTo(1100, 50);
      expect(path.contourCount, 2);
      expect(path.length, closeTo(200, 1e-9));
      expect(path.contourLength(0), closeTo(100, 1e-9));
      expect(path.contourLength(1), closeTo(100, 1e-9));
      final boundary = path.pointAt(.5);
      expect(boundary.x, closeTo(1000, 1e-9));
      expect(boundary.y, closeTo(50, 1e-9));
      expect(path.pointAt(.499).x, lessThan(100));
    });

    test('closed seam resolves to start with outgoing tangent', () {
      final path = GPath().moveTo(0, 0).lineTo(100, 0).lineTo(100, 100).lineTo(0, 100).close();
      expect(path.length, closeTo(400, 1e-9));
      final seam = path.pointAt(1);
      final tangent = path.tangentAt(1);
      expect(seam.x, closeTo(0, 1e-9));
      expect(seam.y, closeTo(0, 1e-9));
      expect(tangent.x, closeTo(1, 1e-9));
      expect(tangent.y, closeTo(0, 1e-9));
    });

    test('zero-length geometry is deterministic', () {
      final path = GPath().moveTo(7, 9).lineTo(7, 9).quadraticTo(7, 9, 7, 9).close();
      final point = path.pointAt(.7);
      final tangent = path.tangentAt(.7);
      final normal = path.normalAt(.7);
      expect(path.length, 0);
      expect(point.x, 7);
      expect(point.y, 9);
      expect(tangent.x, 0);
      expect(tangent.y, 0);
      expect(normal.x, 0);
      expect(normal.y, 0);
      expect(tangent.x.isNaN || tangent.y.isNaN, isFalse);
    });

    test('mutation invalidates retained length and bounds', () {
      final path = GPath().moveTo(0, 0).lineTo(10, 0);
      final version = path.geometryVersion;
      expect(path.length, 10);
      expect(path.bounds.x2, 10);
      path.lineTo(30, 0);
      expect(path.geometryVersion, version + 1);
      expect(path.length, 30);
      expect(path.bounds.x2, 30);
    });

    test('closestPoint reuses prepared geometry and refines curves', () {
      final line = GPath().moveTo(0, 0).lineTo(100, 0);
      final out = GPoint();
      line.closestPoint(30, 40, out);
      expect(out.x, closeTo(30, 1e-9));
      expect(out.y, closeTo(0, 1e-9));
      final curve = GPath(tolerance: .05).moveTo(0, 0).quadraticTo(50, 100, 100, 0);
      curve.closestPoint(50, 80, out);
      expect(out.x, closeTo(50, .2));
      expect(out.y, closeTo(50, .2));
    });
  });

  group('GPathFollower', () {
    test('applies progress, normal offset, and tangent orientation', () {
      final path = GPath().moveTo(0, 0).lineTo(100, 0);
      final node = GNode();
      final follower = GPathFollower(
        path,
        target: node,
        progress: .5,
        orientToPath: true,
        normalOffset: 10,
      );
      expect(node.x, closeTo(50, 1e-9));
      expect(node.y, closeTo(10, 1e-9));
      expect(node.rotation, closeTo(0, 1e-9));
      path.clear().moveTo(0, 0).lineTo(0, 100);
      follower.apply();
      expect(node.x, closeTo(-10, 1e-9));
      expect(node.y, closeTo(50, 1e-9));
      expect(node.rotation, closeTo(math.pi / 2, 1e-9));
    });
  });

  test('invalid tolerance and coordinates fail early', () {
    expect(() => GPath(tolerance: 0), throwsArgumentError);
    expect(() => GPath().moveTo(double.nan, 0), throwsArgumentError);
  });
}

// Copyright (c) 2026 GraphX by roipeker.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:graphx/graphx.dart';
import 'package:graphx_paths/graphx_paths.dart';

void main() {
  test('reverse twice preserves mixed open geometry and sampling', () {
    for (var seed = 0; seed < 24; seed++) {
      final random = math.Random(seed);
      final path = _mixedOpenPath(random);
      final length = path.length;
      final samples = <GPoint>[
        for (var i = 0; i <= 20; i++) path.pointAt(i / 20),
      ];

      path.reverse().reverse();

      expect(path.length, closeTo(length, 1e-7), reason: 'seed $seed');
      for (var i = 0; i < samples.length; i++) {
        final actual = path.pointAt(i / 20);
        expect(actual.x, closeTo(samples[i].x, 1e-7), reason: 'seed $seed sample $i x');
        expect(actual.y, closeTo(samples[i].y, 1e-7), reason: 'seed $seed sample $i y');
      }
    }
  });

  test('open reverse maps progress and tangent to opposite traversal', () {
    final path = GPath()
        .moveTo(-20, 15)
        .quadraticTo(50, 120, 130, -10)
        .cubicTo(180, -80, 260, 100, 330, 20);

    final points = <GPoint>[];
    final tangents = <GPoint>[];
    for (var i = 0; i <= 16; i++) {
      final p = i / 16;
      points.add(path.pointAt(p));
      tangents.add(path.tangentAt(p));
    }

    path.reverse();

    for (var i = 0; i <= 16; i++) {
      final actualPoint = path.pointAt(i / 16);
      final actualTangent = path.tangentAt(i / 16);
      final expectedPoint = points[16 - i];
      final expectedTangent = tangents[16 - i];
      expect(actualPoint.x, closeTo(expectedPoint.x, .03));
      expect(actualPoint.y, closeTo(expectedPoint.y, .03));
      expect(actualTangent.x, closeTo(-expectedTangent.x, .01));
      expect(actualTangent.y, closeTo(-expectedTangent.y, .01));
    }
  });

  test('trim and split boundaries agree with normal arc-length sampling', () {
    final path = GPath.spline([
      GPoint(0, 30),
      GPoint(70, -20),
      GPoint(160, 80),
      GPoint(250, 10),
      GPoint(340, 60),
    ]);

    for (final range in <(double, double)>[
      (0.0, 1.0),
      (.1, .9),
      (.25, .75),
      (.48, .52),
    ]) {
      final section = path.subpath(range.$1, range.$2);
      final start = path.pointAt(range.$1);
      final end = path.pointAt(range.$2);
      expect(section.pointAt(0).x, closeTo(start.x, .03));
      expect(section.pointAt(0).y, closeTo(start.y, .03));
      expect(section.pointAt(1).x, closeTo(end.x, .03));
      expect(section.pointAt(1).y, closeTo(end.y, .03));
    }

    for (final progress in <double>[0, .01, .25, .5, .99, 1]) {
      final split = path.splitAt(progress);
      final expected = path.pointAt(progress);
      expect(split.before.pointAt(1).x, closeTo(expected.x, .03));
      expect(split.before.pointAt(1).y, closeTo(expected.y, .03));
      expect(split.after.pointAt(0).x, closeTo(expected.x, .03));
      expect(split.after.pointAt(0).y, closeTo(expected.y, .03));
    }
  });

  test('degenerate mixed geometry stays finite through all spatial APIs', () {
    final path = GPath()
        .moveTo(5, 5)
        .lineTo(5, 5)
        .quadraticTo(5, 5, 5, 5)
        .cubicTo(5, 5, 5, 5, 5, 5)
        .lineTo(30, 5)
        .cubicTo(30, 5, 30, 5, 30, 5)
        .lineTo(30, 40)
        .moveTo(100, 100)
        .lineTo(100, 100)
        .close();

    for (var i = 0; i <= 32; i++) {
      final progress = i / 32;
      _expectFinite(path.pointAt(progress));
      _expectFinite(path.tangentAt(progress));
      _expectFinite(path.normalAt(progress));
    }

    _expectFinite(path.closestPoint(17, 12));

    final section = path.subpath(.1, .9);
    _expectFinite(section.pointAt(0));
    _expectFinite(section.pointAt(1));

    path.reverse();
    for (var i = 0; i <= 16; i++) {
      _expectFinite(path.pointAt(i / 16));
      _expectFinite(path.tangentAt(i / 16));
    }
  });

  test('flatten metadata is monotonic, finite, and contour-safe', () {
    final path = GPath()
        .moveTo(0, 0)
        .cubicTo(30, 90, 70, -40, 100, 20)
        .moveTo(150, 10)
        .quadraticTo(210, 100, 260, 30)
        .lineTo(180, -20)
        .close()
        .moveTo(400, 400);

    final flat = path.flatten();
    expect(flat.contourCount, 3);
    expect(flat.contourStartIndex(0), 0);
    expect(flat.contourEndIndex(flat.contourCount - 1), flat.pointCount);

    var previousEnd = 0;
    for (var contour = 0; contour < flat.contourCount; contour++) {
      final start = flat.contourStartIndex(contour);
      final end = flat.contourEndIndex(contour);
      expect(start, previousEnd);
      expect(end, greaterThanOrEqualTo(start));
      expect(flat.contourPointCount(contour), end - start);
      for (var i = start; i < end; i++) {
        expect(flat.xAt(i).isFinite, isTrue);
        expect(flat.yAt(i).isFinite, isTrue);
      }
      previousEnd = end;
    }

    expect(flat.isContourClosed(0), isFalse);
    expect(flat.isContourClosed(1), isTrue);
    expect(flat.isContourClosed(2), isFalse);
  });
}

GPath _mixedOpenPath(math.Random random) {
  final path = GPath().moveTo(0, 0);
  var x = 0.0;
  var y = 0.0;

  for (var i = 0; i < 10; i++) {
    final nextX = x + 15 + random.nextDouble() * 60;
    final nextY = y + (random.nextDouble() - .5) * 100;
    switch (random.nextInt(3)) {
      case 0:
        path.lineTo(nextX, nextY);
      case 1:
        path.quadraticTo(
          x + (nextX - x) * .5,
          y + (random.nextDouble() - .5) * 160,
          nextX,
          nextY,
        );
      case 2:
        path.cubicTo(
          x + (nextX - x) * .3,
          y + (random.nextDouble() - .5) * 160,
          x + (nextX - x) * .7,
          nextY + (random.nextDouble() - .5) * 160,
          nextX,
          nextY,
        );
    }
    x = nextX;
    y = nextY;
  }
  return path;
}

void _expectFinite(GPoint point) {
  expect(point.x.isFinite, isTrue);
  expect(point.y.isFinite, isTrue);
}

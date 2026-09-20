// Copyright (c) 2026 GraphX by roipeker.

import 'package:flutter_test/flutter_test.dart';
import 'package:graphx/graphx.dart';
import 'package:graphx_paths/graphx_paths.dart';

void main() {
  test('sampleAt matches separate point and tangent queries', () {
    final path = GPath()
        .moveTo(0, 0)
        .quadraticTo(80, -50, 160, 30)
        .cubicTo(220, 120, 300, -80, 400, 20);

    final point = GPoint();
    final tangent = GPoint();
    final expectedPoint = GPoint();
    final expectedTangent = GPoint();

    for (final progress in <double>[0, .1, .25, .5, .75, .9, 1]) {
      path.sampleAt(progress, point, tangent);
      path.pointAt(progress, expectedPoint);
      path.tangentAt(progress, expectedTangent);

      expect(point.x, closeTo(expectedPoint.x, 1e-10));
      expect(point.y, closeTo(expectedPoint.y, 1e-10));
      expect(tangent.x, closeTo(expectedTangent.x, 1e-10));
      expect(tangent.y, closeTo(expectedTangent.y, 1e-10));
    }
  });

  test('sampleAtDistance matches separate distance queries', () {
    final path = GPath.spline(<GPoint>[
      GPoint(0, 0),
      GPoint(70, -30),
      GPoint(160, 50),
      GPoint(260, 0),
    ]);

    final point = GPoint();
    final tangent = GPoint();
    final expectedPoint = GPoint();
    final expectedTangent = GPoint();

    for (final fraction in <double>[0, .2, .5, .8, 1]) {
      final distance = path.length * fraction;
      path.sampleAtDistance(distance, point, tangent);
      path.pointAtDistance(distance, expectedPoint);
      path.tangentAtDistance(distance, expectedTangent);

      expect(point.x, closeTo(expectedPoint.x, 1e-10));
      expect(point.y, closeTo(expectedPoint.y, 1e-10));
      expect(tangent.x, closeTo(expectedTangent.x, 1e-10));
      expect(tangent.y, closeTo(expectedTangent.y, 1e-10));
    }
  });

  test('combined sampling keeps degenerate paths finite', () {
    final path = GPath().moveTo(4, 7).lineTo(4, 7).quadraticTo(4, 7, 4, 7);
    final point = GPoint();
    final tangent = GPoint();

    path.sampleAt(.5, point, tangent);

    expect(point.x, 4);
    expect(point.y, 7);
    expect(tangent.x, 0);
    expect(tangent.y, 0);
  });

  test('combined sampling preserves closed seam semantics', () {
    final path = GPath().moveTo(0, 0).lineTo(40, 0).lineTo(40, 30).close();
    final point = GPoint();
    final tangent = GPoint();
    final expectedPoint = GPoint();
    final expectedTangent = GPoint();

    path.sampleAt(1, point, tangent);
    path.pointAt(1, expectedPoint);
    path.tangentAt(1, expectedTangent);

    expect(point.x, expectedPoint.x);
    expect(point.y, expectedPoint.y);
    expect(tangent.x, expectedTangent.x);
    expect(tangent.y, expectedTangent.y);
  });

  test('combined sampling rejects non-finite inputs', () {
    final path = GPath().lineTo(20, 0);
    final point = GPoint();
    final tangent = GPoint();

    expect(
      () => path.sampleAt(double.nan, point, tangent),
      throwsArgumentError,
    );
    expect(
      () => path.sampleAtDistance(double.infinity, point, tangent),
      throwsArgumentError,
    );
  });
}

// Copyright (c) 2026 GraphX by roipeker.

import 'package:flutter_test/flutter_test.dart';
import 'package:graphx/graphx.dart';
import 'package:graphx_paths/graphx_paths.dart';

void main() {
  test('three-point spline passes through the authored apex', () {
    final apex = GPoint(100, 20);
    final path = GPath.spline(<GPoint>[
      GPoint(0, 100),
      apex,
      GPoint(200, 100),
    ]);

    final nearest = path.closestPoint(apex.x, apex.y);
    expect(nearest.x, closeTo(apex.x, 1e-7));
    expect(nearest.y, closeTo(apex.y, 1e-7));
    expect(path.length, greaterThan(200));
  });
}

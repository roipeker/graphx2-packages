// Copyright (c) 2026 GraphX by roipeker.

import 'package:flutter_test/flutter_test.dart';
import 'package:graphx_paths/graphx_paths.dart';

void main() {
  test('exact interior segment boundary uses outgoing tangent', () {
    final path = GPath().moveTo(0, 0).lineTo(100, 0).lineTo(100, 100);

    final point = path.pointAt(.5);
    final tangent = path.tangentAt(.5);
    final normal = path.normalAt(.5);

    expect(point.x, closeTo(100, 1e-9));
    expect(point.y, closeTo(0, 1e-9));
    expect(tangent.x, closeTo(0, 1e-9));
    expect(tangent.y, closeTo(1, 1e-9));
    expect(normal.x, closeTo(-1, 1e-9));
    expect(normal.y, closeTo(0, 1e-9));
  });

  test('zero-length transition segments do not destabilize sampling', () {
    final path = GPath().moveTo(0, 0).lineTo(100, 0).lineTo(100, 0).lineTo(100, 100);

    final point = path.pointAt(.5);
    final tangent = path.tangentAt(.5);

    expect(point.x, closeTo(100, 1e-9));
    expect(point.y, closeTo(0, 1e-9));
    expect(tangent.x, closeTo(0, 1e-9));
    expect(tangent.y, closeTo(1, 1e-9));
  });
}

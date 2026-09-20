// Copyright (c) 2026 GraphX by roipeker.

import 'package:flutter_test/flutter_test.dart';
import 'package:graphx/graphx.dart';
import 'package:graphx_paths/graphx_paths.dart';

void main() {
  test('subpath preserves exact line range and split meeting point', () {
    final path = GPath().moveTo(0, 0).lineTo(100, 0);
    final middle = path.subpath(.25, .75);

    expect(middle.length, closeTo(50, 1e-9));
    expect(middle.pointAt(0).x, closeTo(25, 1e-9));
    expect(middle.pointAt(1).x, closeTo(75, 1e-9));

    final split = path.splitAt(.4);
    expect(split.before.length + split.after.length, closeTo(path.length, 1e-9));
    expect(split.before.pointAt(1).x, closeTo(split.after.pointAt(0).x, 1e-9));
  });

  test('cubic subpath keeps curve geometry instead of flattening', () {
    final path = GPath().moveTo(0, 0).cubicTo(20, 100, 80, -100, 100, 0);
    final start = path.pointAt(.2);
    final end = path.pointAt(.8);
    final section = path.subpath(.2, .8);

    expect(section.segmentCount, 1);
    expect(section.pointAt(0).x, closeTo(start.x, .05));
    expect(section.pointAt(0).y, closeTo(start.y, .05));
    expect(section.pointAt(1).x, closeTo(end.x, .05));
    expect(section.pointAt(1).y, closeTo(end.y, .05));
  });

  test('multiple contours remain separate and complete closed contour stays closed', () {
    final path = GPath()
        .moveTo(0, 0)
        .lineTo(10, 0)
        .moveTo(20, 0)
        .lineTo(30, 0)
        .lineTo(30, 10)
        .close();

    final copy = path.subpath(0, 1);
    final flat = copy.flatten();
    expect(copy.contourCount, 2);
    expect(flat.isContourClosed(0), isFalse);
    expect(flat.isContourClosed(1), isTrue);
  });

  test('reverse inverts open traversal and preserves closed contours', () {
    final open = GPath().moveTo(0, 0).quadraticTo(50, 100, 100, 0);
    const progresses = <double>[0, .2, .5, .8, 1];
    final samples = <GPoint>[
      for (final p in progresses) open.pointAt(p),
    ];

    open.reverse();
    for (var i = 0; i < progresses.length; i++) {
      final actual = open.pointAt(1 - progresses[i]);
      final expected = samples[i];
      expect(actual.x, closeTo(expected.x, .05));
      expect(actual.y, closeTo(expected.y, .05));
    }

    final closed = GPath().moveTo(0, 0).lineTo(20, 0).lineTo(20, 20).close();
    final length = closed.length;
    closed.reverse();
    expect(closed.length, closeTo(length, 1e-9));
    expect(closed.flatten().isContourClosed(0), isTrue);
  });

  test('flatten snapshot is compact, contour-aware, and independent after mutation', () {
    final path = GPath().moveTo(0, 0).lineTo(10, 0).lineTo(10, 10).close();
    final flat = path.flatten();

    expect(flat.contourCount, 1);
    expect(flat.contourPointCount(0), 3);
    expect(flat.isContourClosed(0), isTrue);
    expect(flat.pointAtIndex(0).x, 0);
    expect(flat.pointAtIndex(2).y, 10);

    final version = flat.sourceGeometryVersion;
    path.lineTo(30, 30);
    expect(flat.sourceGeometryVersion, version);
    expect(flat.contourPointCount(0), 3);
  });

  test('invalid reversed ranges fail deterministically', () {
    final path = GPath().moveTo(0, 0).lineTo(10, 0);
    expect(() => path.subpath(.8, .2), throwsArgumentError);
    expect(() => path.subpathByDistance(8, 2), throwsArgumentError);
  });
}

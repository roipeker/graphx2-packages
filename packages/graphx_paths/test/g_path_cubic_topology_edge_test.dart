// Copyright (c) 2026 GraphX by roipeker.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:graphx_paths/graphx_paths.dart';

// Reconciled acceptance coverage for the canonical topology contract.
void main() {
  test('empty contour topology operations stay deterministic', () {
    final cubics = (GPath().moveTo(3, 4)).toCubics();
    expect(cubics.contourCount, 1);
    expect(cubics.contourSegmentCount(0), 0);
    expect(identical(cubics.subdivideContourToCount(0, 0), cubics), isTrue);
    expect(identical(cubics.reverseContour(0), cubics), isTrue);
    expect(() => cubics.rotateClosedContourSeam(0, 1), throwsStateError);
  });

  test('no-op batch subdivision reuses immutable snapshot', () {
    final cubics = (GPath().moveTo(0, 0).lineTo(10, 0).lineTo(20, 0)).toCubics();
    final counts = Int32List.fromList(<int>[1, 1]);
    expect(identical(cubics.subdivideByCounts(counts), cubics), isTrue);
  });

  test('removing the only segment preserves contour metadata', () {
    final cubics = (GPath().moveTo(0, 0).lineTo(10, 0)).toCubics();
    final removed = cubics.removeSegment(0);
    expect(removed.segmentCount, 0);
    expect(removed.contourCount, 1);
    expect(removed.contourSegmentCount(0), 0);
    expect(removed.isContourClosed(0), isFalse);
  });

  test('packed copy helpers reject undersized output', () {
    final cubics = (GPath().moveTo(0, 0).lineTo(10, 0)).toCubics();
    expect(
      () => cubics.copySegmentCoordinatesInto(0, Float64List(7)),
      throwsRangeError,
    );
    expect(
      () => cubics.copyContourCoordinatesInto(0, Float64List(7)),
      throwsRangeError,
    );
  });
}

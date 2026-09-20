// Copyright (c) 2026 GraphX by roipeker.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:graphx/graphx.dart';
import 'package:graphx_paths/graphx_paths.dart';

// Final reconciled gate: these invariants are shared consumer contracts.
void main() {
  group('GPathCubics segment evaluation', () {
    test('point derivative and tangent use raw cubic parameter space', () {
      final cubics = (GPath().moveTo(0, 0).cubicTo(10, 0, 10, 10, 20, 10)).toCubics();

      final point = cubics.pointAtSegment(0, .5);
      expect(point.x, closeTo(10, 1e-12));
      expect(point.y, closeTo(5, 1e-12));

      final derivative = cubics.derivativeAtSegment(0, .5);
      expect(derivative.x, closeTo(15, 1e-12));
      expect(derivative.y, closeTo(15, 1e-12));

      final tangent = cubics.tangentAtSegment(0, .5);
      final invSqrt2 = 1 / math.sqrt(2);
      expect(tangent.x, closeTo(invSqrt2, 1e-12));
      expect(tangent.y, closeTo(invSqrt2, 1e-12));
    });

    test('degenerate tangent is deterministic and finite', () {
      final cubics = (GPath().moveTo(4, 7).cubicTo(4, 7, 4, 7, 4, 7)).toCubics();
      final tangent = cubics.tangentAtSegment(0, .5);
      expect(tangent.x, 0);
      expect(tangent.y, 0);
      expect(tangent.x.isFinite && tangent.y.isFinite, isTrue);
    });
  });

  group('GPathCubics exact topology operations', () {
    test('batched subdivision preserves cubic geometry', () {
      final cubics = (GPath().moveTo(0, 0).cubicTo(20, 35, 55, -15, 80, 10)).toCubics();
      final split = cubics.subdivideByCounts(Int32List.fromList(<int>[4]));
      expect(split.segmentCount, 4);

      final expected = GPoint();
      final actual = GPoint();
      for (var piece = 0; piece < 4; ++piece) {
        cubics.pointAtSegment(0, piece / 4, expected);
        split.pointAtSegment(piece, 0, actual);
        expect(actual.x, closeTo(expected.x, 1e-10));
        expect(actual.y, closeTo(expected.y, 1e-10));

        cubics.pointAtSegment(0, (piece + 1) / 4, expected);
        split.pointAtSegment(piece, 1, actual);
        expect(actual.x, closeTo(expected.x, 1e-10));
        expect(actual.y, closeTo(expected.y, 1e-10));
      }
    });

    test('contour subdivision changes only requested contour topology', () {
      final cubics =
          (GPath()
                  .moveTo(0, 0)
                  .lineTo(10, 0)
                  .cubicTo(15, 5, 20, -5, 30, 0)
                  .moveTo(50, 0)
                  .lineTo(60, 0)
                  .lineTo(60, 10)
                  .close())
              .toCubics();

      final secondCount = cubics.contourSegmentCount(1);
      final split = cubics.subdivideContourToCount(0, 5);
      expect(split.contourSegmentCount(0), 5);
      expect(split.contourSegmentCount(1), secondCount);
      expect(split.isContourClosed(0), isFalse);
      expect(split.isContourClosed(1), isTrue);
      expect(split.contourStartSegment(1), 5);
    });

    test('removeSegment updates packed contour offsets without healing geometry', () {
      final cubics = (GPath().moveTo(0, 0).lineTo(10, 0).lineTo(20, 0).moveTo(40, 0).lineTo(50, 0))
          .toCubics();
      final removed = cubics.removeSegment(0);
      expect(removed.segmentCount, 2);
      expect(removed.contourSegmentCount(0), 1);
      expect(removed.contourSegmentCount(1), 1);
      expect(removed.contourStartSegment(1), 1);
      expect(removed.coordinateAt(0), closeTo(10, 1e-12));
      expect(removed.coordinateAt(6), closeTo(20, 1e-12));
    });

    test('reverseContour reverses exact cubic traversal only in that contour', () {
      final cubics =
          (GPath()
                  .moveTo(0, 0)
                  .cubicTo(10, 20, 20, -5, 30, 0)
                  .cubicTo(40, 5, 55, 15, 70, 10)
                  .moveTo(100, 0)
                  .lineTo(110, 0))
              .toCubics();
      final reversed = cubics.reverseContour(0);
      final a = GPoint();
      final b = GPoint();

      for (var segment = 0; segment < 2; ++segment) {
        for (final t in <double>[0, .2, .5, .8, 1]) {
          cubics.pointAtSegment(1 - segment, 1 - t, a);
          reversed.pointAtSegment(segment, t, b);
          expect(b.x, closeTo(a.x, 1e-10));
          expect(b.y, closeTo(a.y, 1e-10));
        }
      }

      final originalSecond = Float64List(8);
      final reversedSecond = Float64List(8);
      cubics.copyContourCoordinatesInto(1, originalSecond);
      reversed.copyContourCoordinatesInto(1, reversedSecond);
      expect(reversedSecond, orderedEquals(originalSecond));
    });

    test('closed seam rotation only changes canonical segment ordering', () {
      final cubics = (GPath().moveTo(0, 0).lineTo(10, 0).lineTo(10, 10).lineTo(0, 10).close())
          .toCubics();
      final rotated = cubics.rotateClosedContourSeam(0, 1);
      expect(rotated.segmentCount, cubics.segmentCount);
      expect(rotated.isContourClosed(0), isTrue);

      final count = cubics.contourSegmentCount(0);
      final source = Float64List(8);
      final target = Float64List(8);
      for (var segment = 0; segment < count; ++segment) {
        cubics.copySegmentCoordinatesInto((segment + 1) % count, source);
        rotated.copySegmentCoordinatesInto(segment, target);
        expect(target, orderedEquals(source));
      }

      final restored = rotated.rotateClosedContourSeam(0, -1);
      final allA = Float64List(cubics.coordinateCount);
      final allB = Float64List(restored.coordinateCount);
      cubics.copyCoordinatesInto(allA);
      restored.copyCoordinatesInto(allB);
      expect(allB, orderedEquals(allA));
    });
  });

  group('GPathCubics validation', () {
    test('rejects invalid raw parameters and topology requests', () {
      final cubics = (GPath().moveTo(0, 0).lineTo(10, 0)).toCubics();

      expect(() => cubics.pointAtSegment(0, -0.1), throwsArgumentError);
      expect(() => cubics.pointAtSegment(0, double.nan), throwsArgumentError);
      expect(
        () => cubics.subdivideByCounts(Int32List.fromList(<int>[0])),
        throwsRangeError,
      );
      expect(() => cubics.subdivideContourToCount(0, 0), throwsRangeError);
      expect(() => cubics.rotateClosedContourSeam(0, 1), throwsStateError);
    });
  });
}

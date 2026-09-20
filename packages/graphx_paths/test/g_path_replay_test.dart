// Copyright (c) 2026 GraphX by roipeker.

import 'package:flutter_test/flutter_test.dart';
import 'package:graphx_paths/graphx_paths.dart';

void main() {
  test('replayCommands preserves exact authored verbs and coordinates', () {
    final path = GPath()
        .moveTo(1, 2)
        .lineTo(3, 4)
        .quadraticTo(5, 6, 7, 8)
        .cubicTo(9, 10, 11, 12, 13, 14)
        .close();
    final sink = _RecordingSink();
    path.replayCommands(sink);

    expect(sink.events, <String>[
      'M 1.0 2.0',
      'L 3.0 4.0',
      'Q 5.0 6.0 7.0 8.0',
      'C 9.0 10.0 11.0 12.0 13.0 14.0',
      'Z',
    ]);
  });
}

final class _RecordingSink implements GPathCommandSink {
  final List<String> events = <String>[];

  @override
  void moveTo(double x, double y) => events.add('M $x $y');

  @override
  void lineTo(double x, double y) => events.add('L $x $y');

  @override
  void quadraticTo(double controlX, double controlY, double x, double y) =>
      events.add('Q $controlX $controlY $x $y');

  @override
  void cubicTo(
    double controlX1,
    double controlY1,
    double controlX2,
    double controlY2,
    double x,
    double y,
  ) => events.add(
    'C $controlX1 $controlY1 $controlX2 $controlY2 $x $y',
  );

  @override
  void close() => events.add('Z');
}

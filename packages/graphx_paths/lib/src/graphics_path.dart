// Copyright (c) 2026 GraphX by roipeker.

part of '../graphx_paths.dart';

/// Setup-time bridge from retained [GPath] commands into [GGraphics].
///
/// The commands are replayed into the graphics object's retained native path.
/// Later mutations to [source] do not mutate already-authored graphics.
extension GGraphicsPathExtension on GGraphics {
  GGraphics drawGPath(GPath source, [double x = 0.0, double y = 0.0]) {
    _checkPoint(x, y);
    var valueIndex = 0;
    for (final verb in source._verbs) {
      switch (verb) {
        case _verbMove:
          moveTo(source._values[valueIndex++] + x, source._values[valueIndex++] + y);
          break;
        case _verbLine:
          lineTo(source._values[valueIndex++] + x, source._values[valueIndex++] + y);
          break;
        case _verbQuadratic:
          curveTo(
            source._values[valueIndex++] + x,
            source._values[valueIndex++] + y,
            source._values[valueIndex++] + x,
            source._values[valueIndex++] + y,
          );
          break;
        case _verbCubic:
          cubicCurveTo(
            source._values[valueIndex++] + x,
            source._values[valueIndex++] + y,
            source._values[valueIndex++] + x,
            source._values[valueIndex++] + y,
            source._values[valueIndex++] + x,
            source._values[valueIndex++] + y,
          );
          break;
        case _verbClose:
          closePath();
          break;
      }
    }
    return this;
  }
}

# graphx_paths

Retained 2D paths for GraphX, with distance-based sampling and allocation-aware geometry tools.

`GPath` stores authored line, quadratic, and cubic geometry. Sampling uses real arc length rather than raw Bézier parameter values, and retained lookup data is rebuilt only after geometry changes.

```dart
final path = GPath();
path.moveTo(0, 80);
path.cubicTo(120, 0, 260, 160, 400, 60);

final point = path.pointAt(.5);
```

For hot loops, reuse caller-owned outputs and combine position and tangent sampling:

```dart
final point = GPoint();
final tangent = GPoint();
path.sampleAt(progress, point, tangent);
```

The package also provides spline authoring, sampled-point simplification and fitting, exact retained trimming, contour-aware flattening, command replay, packed canonical cubic geometry, path following for `GNode`, and a `GGraphics.drawGPath` bridge.

See [TECHNICAL.md](TECHNICAL.md) for runtime and numerical contracts and [VECTOR_GEOMETRY.md](VECTOR_GEOMETRY.md) for fitting and canonical cubic topology operations.

# graphx_paths vector geometry contract

This document defines the sampled-data and canonical-geometry primitives that sit beside the retained path contract in [TECHNICAL.md](TECHNICAL.md).

The boundary is deliberate: `graphx_paths` owns deterministic 2D geometry. Drawing tools, editors and morphing packages own interaction, correspondence and animation policy.

## Through-points vs sampled fitting

These APIs solve different authoring problems.

```dart
final rail = GPath.spline(waypoints);
final stroke = GPath.fit(samples, tolerance: .75);
```

`GPath.spline()` interpolates authored waypoints. Every waypoint lies on the resulting curve.

`GPath.fit()` approximates sampled/noisy geometry with a compact sequence of ordinary cubic Bézier segments. It preserves the first and last retained sample, but interior samples are observations rather than mandatory interpolation points.

After construction both are normal `GPath` instances. There is no spline or fitting runtime representation and no repeated control-handle derivation during sampling/rendering.

## Curve fitting algorithm

Open-path fitting follows Philip J. Schneider's Graphics Gems curve-fitting algorithm:

1. remove consecutive duplicate samples;
2. estimate endpoint tangents;
3. chord-length parameterize the sample range;
4. solve cubic handle lengths with least squares;
5. measure sample error;
6. perform guarded Newton reparameterization when useful;
7. reject locally pathological control handles instead of clamping them;
8. split at the largest-error or stable midpoint sample and continue iteratively.

The implementation uses an explicit task stack rather than recursive Dart calls, so dense input cannot overflow the VM stack.

### Fitting tolerance

For a candidate cubic, the algorithm associates every retained input sample with a curve parameter and requires the Euclidean distance at those sample/parameter pairs to be no greater than `tolerance` before accepting that cubic.

Therefore the accepted fit guarantees a one-sided bound for retained input samples: each retained sample has a point on its fitted cubic no farther than the requested tolerance.

This is **not** a Hausdorff bound between the entire fitted curve and the source polyline between samples. Sparse sampling can never provide that guarantee without additional assumptions.

`GPath.fit(..., pathTolerance:)` has a separate purpose. `pathTolerance` is the normal retained arc-length preparation tolerance used later by `GPath`; changing it does not change the fitting acceptance threshold.

### Endpoint / degenerate behavior

- zero samples -> empty path;
- one retained sample -> move-only contour;
- two retained samples -> exact line segment;
- three or more -> one or more cubic Bézier segments;
- consecutive duplicates -> removed before fitting;
- collinear data -> stable compact cubic/line-equivalent geometry;
- non-finite coordinates -> rejected;
- non-positive/non-finite fit tolerance -> rejected.

Closed fitting is first-class through `GPath.fit(points, closed: true)`. Input is treated as a cyclic contour: a duplicated terminal sample is removed, the seam uses one shared cyclic tangent, and the fitted contour is closed after cubic preparation. The authored first sample remains the seam.

Candidate cubics are accepted only when their sample error is within tolerance and their local control-handle scale is sane relative to the fitted sample span. A candidate that becomes non-finite, ill-conditioned, non-monotonic during Newton refinement, or geometrically pathological is split and refit rather than clamped into place.

Near-consecutive duplicates within a tiny fraction of the fit tolerance are removed before fitting so tiny edges do not destabilize tangent or least-squares calculations.

## Point simplification

```dart
final simple = GPath.simplifyPoints(samples, tolerance: 1.5);
```

This is iterative Ramer-Douglas-Peucker over sampled points. It is intentionally **not** `path.simplify()`: rewriting arbitrary retained Bézier geometry has different semantics and is not implied by sampled-point reduction.

The simplifier:

- removes consecutive duplicate samples first;
- preserves first/last retained samples;
- retains points needed to keep recursive point-to-chord deviation within tolerance;
- uses squared-distance tests internally;
- returns new `GPoint` values owned by the caller.

A common drawing/editor pipeline is:

```text
pointer samples -> simplifyPoints -> GPath.fit -> retained GPath
```

Both simplification and fitting are one-time authoring work. They are not intended for per-frame path traversal.

## Canonical cubic geometry

```dart
final cubics = path.toCubics();
```

`GPathCubics` is a read-only packed derived snapshot. It exists so tooling, serialization and topology algorithms do not need to understand GraphX's authored line/quadratic/cubic verb mix.

Every segment occupies eight doubles:

```text
p0.x, p0.y,
c1.x, c1.y,
c2.x, c2.y,
p3.x, p3.y
```

Conversion is exact:

- line -> cubic degree elevation at 1/3 and 2/3;
- quadratic -> exact quadratic-to-cubic degree elevation;
- cubic -> copied unchanged.

No flattening, arc-length lookup or approximation is involved in this conversion.

`GPathCubics` also retains packed contour offsets and a closed flag per contour. The prepared geometric closing edge of a closed contour is included as a cubic segment, while the closed flag preserves seam/topology information separately.

Empty contours remain represented in contour metadata even though they own zero cubic segments.

The snapshot owns its numeric storage. Mutating the source `GPath` later does not change an existing `GPathCubics`.

### Raw segment evaluation

Algorithms that already know the canonical segment and raw Bézier parameter should not go back through whole-path arc-length sampling:

```dart
cubics.pointAtSegment(segment, t, point);
cubics.derivativeAtSegment(segment, t, derivative);
cubics.tangentAtSegment(segment, t, tangent);
```

These calls evaluate the packed cubic directly. `t` is raw local cubic parameter in `[0, 1]`, not normalized path distance. Caller-owned output avoids allocation.

`derivativeAtSegment()` returns the unnormalized first derivative. `tangentAtSegment()` normalizes it and uses deterministic chord/control-edge fallbacks at derivative singularities; a completely degenerate cubic returns `(0, 0)`.

This boundary is intended for editor handles, topology preparation, curvature/tessellation heuristics, procedural geometry and diagnostics. Ordinary motion/text/particle traversal should continue using the retained arc-length APIs on `GPath`.

### Packed copying

Consumers can copy exactly the slice they need without exposing mutable internals:

```dart
cubics.copySegmentCoordinatesInto(segment, out);
cubics.copyContourCoordinatesInto(contour, out);
```

`contourCoordinateCount()` reports the required packed size for a contour.

## Exact cubic subdivision

```dart
final split = cubics.subdivide(segmentIndex, .5);
```

Subdivision uses de Casteljau and returns a new packed snapshot with the selected cubic replaced by two cubics. The union of those two segments is geometrically identical to the source segment.

The containing contour gains one segment; contour order, closed state and seam metadata do not change.

`t` must be finite and strictly inside `(0, 1)`. Endpoints are deliberately rejected because they would create a zero-length topology segment and are not useful for topology normalization.

### Batched subdivision

Repeatedly allocating a whole snapshot for many preparation splits is unnecessary. Use one batch when the desired output piece counts are already known:

```dart
final pieces = Int32List.fromList([1, 3, 2]);
final normalized = cubics.subdivideByCounts(pieces);
```

Each entry says how many equal-local-parameter pieces the corresponding source segment should become. Every count is at least one. The operation computes the final topology first, allocates the packed result once, and preserves contour boundaries/closed state exactly.

For the common case of equalizing one contour to a known segment count:

```dart
final normalized = cubics.subdivideContourToCount(contour, 24);
```

This only subdivides; it never merges or refits. Existing segments are distributed deterministically across the target count and split exactly.

These operations are geometry. Choosing the desired count or correspondence remains consumer policy.

## Deterministic topology transforms

The canonical snapshot owns a few single-path operations that are reusable beyond morphing.

### Remove one segment

```dart
final next = cubics.removeSegment(segment);
```

This removes one packed cubic and updates contour offsets. It deliberately does **not** reconnect neighbors, repair continuity or invent controls. Those decisions belong to the calling authoring/import/topology layer.

### Reverse one contour

```dart
final next = cubics.reverseContour(contour);
```

Segment order and cubic control direction are reversed exactly for that contour. Other contours and contour ordering remain untouched.

### Rotate a closed seam

```dart
final next = cubics.rotateClosedContourSeam(contour, segmentOffset);
```

This rotates whole canonical segments in a closed contour without changing geometry or traversal direction. Positive/negative offsets are normalized by the segment count.

The operation deliberately does not decide which seam is visually best. Morphing may score correspondence, an editor may expose “set start point”, path text may choose a reading start, and a racing/trajectory system may choose a lap origin. Paths only performs the deterministic rotation once a caller has chosen it.

## Cross-package topology boundary

This layer is intentionally useful to more than one package:

- **Authoring** can split anchors exactly, inspect raw segment handles and later build delete/knife commands while keeping interaction/history outside Paths.
- **Morph** can normalize segment counts, reverse traversal and rotate chosen closed seams without maintaining private Bézier subdivision code.
- **SVG / font / import tooling** can normalize mixed path commands to one cubic representation before serialization or downstream processing.
- **Mesh / ribbons / trails** can inspect raw cubic geometry or deliberately subdivide before flatten/tessellation preparation.
- **DevTools** can inspect canonical controls, segment parameters and topology without reverse-engineering authored verbs.
- **Procedural animation / trajectories** can define deterministic seam/start changes or pre-segment geometry without changing runtime arc-length traversal.

Paths should not acquire the consumer policies that choose those operations.

## Morph boundary

A morph package can use these primitives as follows:

```text
Path A / Path B
 -> inspect contours
 -> align contour correspondence/orientation/seams      [morph policy]
 -> toCubics()                                          [paths geometry]
 -> choose compatible segment topology                  [morph policy]
 -> subdivide / subdivideContourToCount exactly         [paths geometry]
 -> reverseContour / rotateClosedContourSeam if chosen  [paths geometry]
 -> build packed compatible interpolation buffers       [morph policy]
 -> interpolate control data per frame                   [morph runtime]
```

Paths should not acquire APIs such as `match`, `normalizeForMorph`, winding heuristics or correspondence scoring. Those decisions depend on visual/morph policy, not deterministic single-path geometry.

## Performance ownership

Sampled authoring can allocate: input cleaning, simplification and fitting are expected to be editor/input-processing operations.

The result of `fit()` is ordinary retained `GPath` geometry, so repeated `pointAt`, `sampleAt`, rendering, Motion, text layout and particle use have no special fitting overhead.

`GPathCubics` intentionally allocates packed snapshots rather than one Dart object per cubic/control point. Single `subdivide()` allocates one new snapshot; `subdivideByCounts()` is the preferred preparation primitive when many known splits are needed because it sizes and writes the final packed topology once.

Topology preparation belongs outside animation hot loops. Runtime morphing should interpolate already-prepared packed buffers rather than repeatedly subdividing or rotating snapshots.

Benchmarks for sampled geometry live in `examples/labs/benchmark/paths_fit_benchmark.dart` and cover representative 100 / 1,000 / 10,000 sample authoring workloads separately from retained sampling.

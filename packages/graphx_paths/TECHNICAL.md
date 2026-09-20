# graphx_paths technical contract

This document is the maintainer/agent reference for `graphx_paths`. The public README is intentionally small; this file defines the behavior other GraphX packages may rely on.

## Purpose and ownership

`graphx_paths` owns retained 2D geometric paths and spatial queries.

It owns:

- authored path geometry;
- contour structure;
- arc-length preparation and sampling;
- bounds;
- closest-point queries;
- spline-through-points authoring;
- exact curve-preserving range extraction after distance-to-parameter resolution;
- traversal reversal;
- derived flattened snapshots;
- the small `GPathFollower` adapter.

It does **not** own rendering policy, animation timelines, particles, text layout, camera behavior, tessellation, meshes, polygon booleans, or editor state.

Dependency direction matters: consumers depend on `graphx_paths`; `graphx_paths` should know as little as possible about them.

## Canonical representation

`GPath` stores one authored verb stream:

- `moveTo`;
- `lineTo`;
- `quadraticTo`;
- `cubicTo`;
- `close`.

There is no parallel runtime spline representation. `GPath.spline()` converts waypoint splines to ordinary cubic Bézier verbs at construction time.

Derived data is prepared lazily and discarded when authored geometry changes.

## Mutation and cache lifetime

Every geometry mutation increments `geometryVersion` and clears the prepared cache.

The prepared cache contains the data required by bounds, lengths, distance mapping, sampling, closest-point queries, and flattening. Expensive subdivision is therefore paid after mutation, not on every sample.

A `GPathFlattened` is an owned snapshot. It is intentionally independent from later mutations of its source path and records the source `geometryVersion` and tolerance used to create it.

## Coordinates and input validity

Public path coordinates must be finite. Non-finite values are rejected.

`GPath.tolerance` must be finite and greater than zero.

Zero-length segments and contours are valid geometry. They must not produce NaNs or unstable normalized tangents.

## Contours

A `moveTo` starts a new contour. Move gaps have no geometric length and are never implicitly connected by spatial operations.

`close()` creates the closing edge from the current point to the contour start. The edge exists even when its length is zero.

Total path length is the sum of contour lengths. Per-contour length is available with `contourLength()`.

At a total-distance boundary shared by two non-empty contours, the following contour owns the boundary. This keeps forward traversal deterministic.

## Progress and distance semantics

Normalized APIs are normalized **arc length**, not raw Bézier parameter space.

```dart
path.pointAt(.5);
path.tangentAt(.5);
```

means 50% of the prepared total travel distance.

Progress and distance inputs are clamped after validating that the supplied value is finite.

Distance APIs use path-local units:

```dart
path.pointAtDistance(distance);
path.tangentAtDistance(distance);
```

Per-contour distance APIs do not cross `moveTo` boundaries.

## Arc-length preparation

Curves are adaptively subdivided with de Casteljau subdivision. A leaf is accepted when:

```text
controlPolygonLength - chordLength <= tolerance
```

or the bounded maximum subdivision depth is reached.

The default tolerance is `0.25` path-local units.

This tolerance is a local subdivision criterion. It is **not** a global Hausdorff-distance guarantee and it does not make distance-to-Bézier-parameter inversion mathematically exact.

Prepared data retains cumulative lengths and per-segment lookup samples. Repeated point/tangent/distance queries use binary search plus scalar evaluation and do not resubdivide curves.

## Points, tangents, and normals

Sampling a non-zero path resolves an arc-length distance to a source segment and local Bézier parameter, then evaluates the analytic segment.

Tangents are normalized direction vectors. At a derivative singularity, tangent resolution falls back to a short local chord and then to a non-zero segment chord in the same contour. If no stable direction exists, `(0, 0)` is returned.

Normals are left-hand normals:

```text
(-tangent.y, tangent.x)
```

For an entirely zero-length path, point queries resolve deterministically to the first available contour start (or origin for an empty path), and tangent/normal queries return zero vectors.

Closed final contours resolve total progress `1` / total distance to their seam/start with the outgoing first-segment tangent.

### Combined sampling

Consumers that need both position and tangent at the same location should use:

```dart
path.sampleAt(progress, pointOut, tangentOut);
path.sampleAtDistance(distance, pointOut, tangentOut);
```

These have the same clamping, contour-boundary, closed-seam, tangent fallback, and zero-length semantics as the corresponding separate point/tangent queries, but resolve the retained arc-length lookup only once. They write into caller-owned `GPoint` outputs and perform no convenience allocation. The two output objects must be distinct.

Prefer combined sampling in hot consumers such as followers, particle births, glyph placement, and camera/rail evaluation when both values are required. Do not use it when only one value is needed; `pointAt` or `tangentAt` remains the smaller operation in that case.

## Bounds

Bounds are analytic for lines, quadratics, and cubics; they are not derived from the adaptive flattening samples.

`bounds` returns a defensive `GBounds` value. `boundsInto(out)` should be used where allocation matters.

## Through-points splines

`GPath.spline(points, closed: ...)` is an authoring convenience.

Three or more waypoints use centripetal Catmull-Rom parameterization (`alpha = 0.5`) and are converted immediately into cubic Bézier segments. The resulting path passes through every supplied waypoint in order.

Endpoint behavior:

- 0 points → empty path;
- 1 point → move-only contour;
- 2 points → straight segment;
- 3+ points → centripetal spline;
- duplicate/nearly coincident neighborhoods → stable line fallback where needed;
- non-finite coordinates → error.

Closed splines wrap their waypoint neighborhood so the authored seam has continuous spline tangent behavior before conversion to cubics.

There is deliberately no public tension/parameterization hierarchy today.

## Closest point

`closestPoint(x, y)` uses the retained adaptive polyline as a candidate search, then performs bounded Newton refinement on the winning source segment.

No curve subdivision occurs per closest-point query after preparation.

Complexity is linear in retained adaptive sample count. Consumers handling very large path sets or very high query counts should add an external broad phase rather than changing `GPath` into a spatial-index framework.

## Range extraction and splitting

```dart
path.subpath(startProgress, endProgress);
path.subpathByDistance(startDistance, endDistance);
path.splitAt(progress);
```

Range boundaries are first mapped through the same tolerance-based retained distance lookup used by normal sampling. The resulting source-segment parameters are then used to produce analytic line/quadratic/cubic pieces.

Important wording: the returned **curve representation is exact for the resolved source parameters**. Arc-length boundary inversion remains subject to the configured lookup tolerance.

Semantics:

- input ranges are finite;
- start must not exceed end before clamping;
- values outside the path range clamp to valid endpoints;
- move gaps remain contour boundaries;
- a fully selected closed contour remains closed;
- a partial selection of a closed contour is open;
- closed-seam wrapping is not implicit;
- a zero-width range produces a move-only path at the sampled location;
- `splitAt(p)` leaves the source unchanged and is equivalent to `[0,p]` plus `[p,1]` extraction.

Do not use `subpath()` as a per-frame substitute for scalar progress when a follower or renderer can sample the original retained path directly. It creates new authored geometry by design.

## Reversal

`path.reverse()` mutates the path and invalidates prepared data.

It reverses:

- contour order;
- segment order within each contour;
- segment direction.

Quadratic controls remain the same geometric control point under reversal. Cubic controls swap order. Closed contours remain closed without adding a synthetic closing segment.

For ordinary animation playback, prefer progress `1 -> 0`; reverse geometry only when direction is itself part of the authored/processed path semantics.

## Flattened snapshots

`path.flatten()` produces a `GPathFlattened` using the already prepared adaptive subdivision. It copies that derived geometry into owned packed storage; it does not perform a second subdivision pass.

The public snapshot is read-only and contour-aware:

- `pointCount` / `contourCount`;
- `xAt()` / `yAt()`;
- `pointAtIndex()`;
- `contourStartIndex()` / `contourEndIndex()`;
- `contourPointCount()`;
- `isContourClosed()`.

Closed contours omit a duplicated final seam point. Consumers must use `isContourClosed()` if they need the final-to-first edge.

Flattening is appropriate for bulk/polyline consumers, editor proxies, broad phases, particles, ribbons/trails, and future GPU/mesh preparation. It should not replace path-distance sampling where actual path distance/tangent semantics matter.

## Follower ownership

`GPathFollower` is a convenience adapter, not part of the geometry representation.

It owns reusable sampling scratch state and can apply:

- progress;
- position;
- optional tangent orientation;
- signed normal offset;
- rotation offset.

The follower uses combined sampling so position and orientation share one retained distance lookup. If path geometry mutates without follower progress changing, call `apply()` to re-resolve the current sample.

Motion integration belongs in a separate motion package; graphx_paths stays independent of animation infrastructure.

## Graphics bridge

`GGraphics.drawGPath(path)` replays authored verbs into `GGraphics` at setup time.

It is not a live binding. Later `GPath` mutation does not mutate already-replayed graphics.

Core `GGraphics` rendering intentionally does not depend on `graphx_paths`; this keeps ordinary graphics hot paths independent and avoids dependency cycles around GraphX geometry primitives.

## Allocation/performance contract

Expected usage is retained geometry sampled repeatedly.

- construction/mutation may allocate and invalidate preparation;
- spline construction derives cubic controls once;
- first spatial query after mutation may perform adaptive preparation;
- repeated point/tangent/distance sampling should avoid transient geometry allocation when callers supply reusable `GPoint` outputs;
- combined point+tangent sampling performs one retained lookup and writes into caller-owned outputs;
- `GPathFollower` reuses scratch points and combined sampling;
- closest-point queries reuse preparation;
- `subpath` / `splitAt` intentionally allocate new paths;
- `reverse()` rebuilds authored geometry and invalidates caches;
- `flatten()` intentionally allocates an independent snapshot.

Typed arrays are an internal retained-storage choice, not a public API requirement.

## Consumer rules

The detailed adoption checklist lives in [CONSUMERS.md](CONSUMERS.md). The short version:

- Motion: animate progress/distance; do not rebuild paths per frame.
- Text: use combined distance sampling when glyph placement needs both position and tangent.
- Particles: use combined sampling when births need both position and path direction; flatten only for bulk polyline workloads when measured useful.
- Camera rails: consume point/tangent/distance semantics; future 3D orientation needs its own stable frame model.
- DevTools/editors: authored verbs remain source of truth; flattening is derived display/query data.
- Graphics: migrate native patterned/dash internals only when it removes duplicated work without hurting the rendering hot path.
- Mesh/ribbons: flattening is the intended first common polyline boundary; tessellation ownership remains outside this package.

## Explicit non-goals

`graphx_paths` is not a general computational-geometry package.

Out of scope for this layer unless future evidence changes the boundary:

- polygon union/intersection/difference;
- general offset paths;
- self-intersection repair;
- stroke expansion;
- triangulation/tessellation;
- mesh generation;
- generic segment visitor frameworks;
- generic vector/spline hierarchies.

## Reliability expectations

Because multiple packages can build behavior on path semantics, changes to any of the following require focused regression coverage:

- distance/progress boundary ownership;
- closed seams;
- tangent fallback;
- zero-length geometry;
- spline conversion;
- mutation/cache invalidation;
- combined sampling equivalence with separate point/tangent queries;
- range extraction across segment/contour boundaries;
- reversal of all segment kinds and closed contours;
- flatten contour offsets/closure;
- allocation-sensitive repeated sampling.

When a consumer needs a new geometry behavior, prefer adding one well-defined primitive here over duplicating Bézier/subdivision logic in the consumer — but only when that primitive is truly geometry rather than behavior.

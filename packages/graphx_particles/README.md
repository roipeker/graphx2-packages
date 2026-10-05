# graphx_particles

Data-oriented retained particle systems for GraphX.

`GParticleEmitter` is one GraphX node backed by fixed-capacity packed numeric
storage. Individual particles are not scene nodes or Dart objects, which keeps
high-volume effects predictable and allocation-aware.

## Basic burst

```dart
final emitter = GParticleEmitter(
  texture: sparkTexture,
  capacity: 256,
);

emitter.life = const GParticleRange(.25, .55);
emitter.speed = const GParticleRange(80, 220);
emitter.angle = const GParticleRange(-3.14, 3.14);
emitter.particleScale = const GParticleRange(.4, 1.1);
emitter.alphaOverLife = GParticleCurve.linear(1, 0);

root.addChild(emitter);
emitter.burstAt(x, y, 32);
```

## Continuous emission

```dart
emitter.rate = 40;
emitter.start();

// Later:
emitter.stop();
```

Distance-based emission is available through `distanceRate`. World-space
emitters can inherit source velocity with `sourceVelocityFactor`.

## Shapes and direction

Built-in shapes:

- point
- rectangle
- circle
- line
- retained `graphx_paths.GPath`

Direction can be authored as an absolute angle, radial direction, path tangent,
or path normal.

## Lifetime styling

Emitters support retained curves and palettes for:

- scale over life
- alpha over life
- color over life
- independently sampled end scale/color/alpha
- random or over-life atlas frames

All configured frames must share one backing image so the common path remains
batchable through `drawRawAtlas`.

## Simulation space

`GParticleSpace.local` keeps particles under the emitter hierarchy.

`GParticleSpace.world` stores particle positions in Stage/root space, so moving,
rotating, or reparenting the emitter after birth does not drag existing
particles with it.

## Fields and constraints

Retained force fields include wind, point attraction/repulsion, vortex, and
deterministic turbulence.

Built-in constraints include bounds, planes, and circles with bounce, kill, or
bounds-wrap responses.

## Secondary emission

`GParticleSpawn` can trigger a second retained emitter on natural particle
death or supported constraint impacts. The source and target remain ordinary
emitters; particles never own callback or emitter objects.

## Trails

`GParticleTrail` provides a cheap retained line trail.

`GParticleTrail.ribbon` uses packed tapered triangle geometry and can optionally
use a texture. Trail history remains fixed-capacity numeric storage rather than
one path object per particle.

## Prewarm

```dart
emitter.rate = 80;
emitter.prewarm(1.5, step: 1 / 120);
```

Prewarm uses the normal deterministic simulation path and restores the
emitter's previous running state afterward.

## Performance model

The package preserves the proven Satechi architecture:

- fixed-capacity structure-of-arrays simulation storage;
- swap-remove active slots;
- deterministic seeded random generation;
- retained optional endpoint/trail/field state;
- one atlas draw in the common same-image particle case;
- no per-particle scene nodes;
- optional metrics through `GParticleStats`.

The package consumes only public GraphX and `graphx_paths` APIs.

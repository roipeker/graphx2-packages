# Particle trail compositing

Particle sprites, trail primitives, and the emitter node have separate compositing responsibilities.

```dart
emitter.particleBlendMode = BlendMode.plus;
emitter.trail = GParticleTrail.ribbon(
  blendMode: BlendMode.screen,
  alpha: GParticleCurve.linear(1, 0),
);
emitter.blendMode = BlendMode.srcOver;
```

- `particleBlendMode` controls sprite fragments submitted by the emitter's `drawRawAtlas` batch.
- `GParticleTrail.blendMode` controls line/ribbon trail fragments against the current destination.
- inherited `GNode.blendMode` controls the emitter subtree as scene compositing state.

The default for all three axes is `BlendMode.srcOver`. Trail blend mode is one retained value per trail configuration; it adds no per-particle state and does not add a draw call.

## Trail alpha

`GParticleTrail.alpha` is spatial: normalized trail position `0` is the live head and `1` is the oldest retained sample.

Cheap line trails quantize that curve into at most four retained draw bands. A line trail with `alpha == null` preserves the one-`drawRawPoints` fast path. Line trails do not evaluate each owning particle's lifetime opacity per segment; author an explicit spatial `alpha` curve when decay is desired.

Ribbon trails already carry per-vertex color. Their effective vertex alpha composes the spatial trail alpha with the owning particle's current effective opacity:

```text
ribbon vertex alpha
  = trail spatial alpha
  × sampled/interpolated particle color alpha
  × colorOverLife alpha
  × alphaOverLife
```

This makes the whole ribbon decay with its particle instead of remaining visually bright until slot removal. It adds no particle storage and is evaluated in the existing ribbon packing pass.

A trail still has the same lifetime ownership as its particle. When the particle slot dies, its retained trail history is removed with it; trail-after-death linger would require a separate packed lifecycle and is intentionally not implied by opacity decay.

## Textured ribbons

For textured ribbons, `Canvas.drawVertices(..., BlendMode.modulate, paint)` keeps its existing meaning: texture samples are multiplied by retained vertex color. `GParticleTrail.blendMode` is applied through the trail paint and controls the resulting ribbon against the framebuffer. These are independent operations.

For tintable creative effects, prefer neutral white/grayscale ribbon textures with shape/softness encoded in alpha, then use retained ribbon colors plus `blendMode` for the final effect.

# GraphX 2 Packages

Official first-party ecosystem packages for [GraphX 2](https://github.com/roipeker/graphx2).

These packages are not on pub.dev yet. Each package can be consumed directly from this public GitHub monorepo using Dart's Git dependency `path` support.

## Packages

- `graphx_paths` — retained geometric paths and allocation-aware spatial sampling.
- `graphx_motion` — tweens, retained timelines, keyframes, stagger, and motion physics.
- `graphx_atlas` — TexturePacker atlas decoding and GraphX asset-loading helpers.
- `graphx_particles` — packed retained particle emitters, fields, constraints, trails, and secondary effects.
- `graphx_arcade` — small deterministic fixed-step 2D arcade physics.

## Install

The current compatible package-set tag is `v0.1.0-dev.1`. Add only the packages you need.

### graphx_paths

```yaml
dependencies:
  graphx_paths:
    git:
      url: https://github.com/roipeker/graphx2-packages.git
      path: packages/graphx_paths
      ref: v0.1.0-dev.1
```

### graphx_motion

```yaml
dependencies:
  graphx_motion:
    git:
      url: https://github.com/roipeker/graphx2-packages.git
      path: packages/graphx_motion
      ref: v0.1.0-dev.1
```

### graphx_atlas

```yaml
dependencies:
  graphx_atlas:
    git:
      url: https://github.com/roipeker/graphx2-packages.git
      path: packages/graphx_atlas
      ref: v0.1.0-dev.1
```

### graphx_particles

```yaml
dependencies:
  graphx_particles:
    git:
      url: https://github.com/roipeker/graphx2-packages.git
      path: packages/graphx_particles
      ref: v0.1.0-dev.1
```

### graphx_arcade

```yaml
dependencies:
  graphx_arcade:
    git:
      url: https://github.com/roipeker/graphx2-packages.git
      path: packages/graphx_arcade
      ref: v0.1.0-dev.1
```

Then run:

```bash
flutter pub get
```

Package dependencies on GraphX and on other GraphX ecosystem packages are resolved transitively. If your own application imports `package:graphx/graphx.dart` directly, declare `graphx` as a direct dependency as shown in the [GraphX 2 README](https://github.com/roipeker/graphx2#use-graphx).

To follow the latest development revision instead of the package-set tag, use `ref: main`. For reproducible projects, prefer a package-set tag or commit SHA.

## Development

```bash
flutter pub get
flutter analyze
flutter test
```

The repository is an ordinary Dart workspace; package-specific tests may also be run from each package directory.

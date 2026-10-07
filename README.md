# GraphX 2 Packages

Official first-party ecosystem packages for [GraphX 2](https://github.com/roipeker/graphx2).

These packages are consumed directly from this public GitHub monorepo. Dart
3.9+ Git tag version solving keeps GraphX core and ecosystem packages
compatible without hard-coding one literal Git ref into every dependency.

## Packages

- `graphx_paths` — retained geometric paths and allocation-aware spatial sampling.
- `graphx_motion` — tweens, retained timelines, keyframes, stagger, and motion physics.
- `graphx_atlas` — TexturePacker atlas decoding and GraphX asset-loading helpers.
- `graphx_particles` — packed retained particle emitters, fields, constraints, trails, and secondary effects.
- `graphx_arcade` — small deterministic fixed-step 2D arcade physics.
- `graphx_connect` — small fast LAN/WebRTC peer sessions for games, remotes, and tools.

## Install

Use `tag_pattern` plus a normal version constraint. Do not mix literal
`ref: main` / tag refs for the same package in the dependency graph; Pub
treats those as different sources.

If your app imports GraphX directly:

```yaml
graphx:
  git:
    url: https://github.com/roipeker/graphx2.git
    tag_pattern: v{{version}}
  version: ^2.0.0-dev.2
```

Add only the ecosystem packages you need.

### graphx_paths

```yaml
graphx_paths:
  git:
    url: https://github.com/roipeker/graphx2-packages.git
    path: packages/graphx_paths
    tag_pattern: v{{version}}
  version: ^0.1.0-dev.3
```

### graphx_motion

```yaml
graphx_motion:
  git:
    url: https://github.com/roipeker/graphx2-packages.git
    path: packages/graphx_motion
    tag_pattern: v{{version}}
  version: ^0.1.0-dev.3
```

### graphx_atlas

```yaml
graphx_atlas:
  git:
    url: https://github.com/roipeker/graphx2-packages.git
    path: packages/graphx_atlas
    tag_pattern: v{{version}}
  version: ^0.1.0-dev.3
```

### graphx_particles

```yaml
graphx_particles:
  git:
    url: https://github.com/roipeker/graphx2-packages.git
    path: packages/graphx_particles
    tag_pattern: v{{version}}
  version: ^0.1.0-dev.3
```

### graphx_arcade

```yaml
graphx_arcade:
  git:
    url: https://github.com/roipeker/graphx2-packages.git
    path: packages/graphx_arcade
    tag_pattern: v{{version}}
  version: ^0.1.0-dev.3
```

### graphx_connect

```yaml
graphx_connect:
  git:
    url: https://github.com/roipeker/graphx2-packages.git
    path: packages/graphx_connect
    tag_pattern: v{{version}}
  version: ^0.1.0-dev.6
```

Then run:

```bash
flutter pub get
```

Applications should commit `pubspec.lock` for exact reproducibility.

Current public baselines:

- GraphX core: `v2.0.0-dev.2`
- Existing GraphX packages: `v0.1.0-dev.3`
- `graphx_connect`: `v0.1.0-dev.6`

## Unreleased local development

Keep the committed declarations above. For local GraphX work, use an ignored
`pubspec_overrides.yaml`:

```yaml
dependency_overrides:
  graphx:
    path: ../graphx
```

A root app can also temporarily override GraphX to `main` when deliberately
testing unreleased core changes. Root overrides replace the source consistently;
public package manifests themselves remain version-solved.

## Validation

```bash
./tool/check.sh
```

This verifies dependency-source policy, resolves the workspace, analyzes it,
and runs every package test suite.

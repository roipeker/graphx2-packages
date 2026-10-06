# GraphX 2 Packages

Official first-party ecosystem packages for [GraphX 2](https://github.com/roipeker/graphx2).

## Packages

- `graphx_paths` — retained geometric paths and allocation-aware spatial sampling.
- `graphx_motion` — tweens, retained timelines, keyframes, stagger, and motion physics.
- `graphx_atlas` — TexturePacker atlas decoding and GraphX asset-loading helpers.
- `graphx_particles` — packed retained particle emitters, fields, constraints, trails, and secondary effects.
- `graphx_arcade` — small deterministic fixed-step 2D arcade physics.

## Consuming from GitHub

The ecosystem uses Dart 3.9+ Git tag version solving. Do not mix literal Git
`ref` values such as `main` and `v2.0.0-dev.2` for the same package: Pub
treats those as different dependency sources.

Use `tag_pattern` plus a normal version constraint for both GraphX core and
GraphX ecosystem packages:

```yaml
dependencies:
  graphx:
    git:
      url: https://github.com/roipeker/graphx2.git
      tag_pattern: v{{version}}
    version: ^2.0.0-dev.2

  graphx_atlas:
    git:
      url: https://github.com/roipeker/graphx2-packages.git
      path: packages/graphx_atlas
      tag_pattern: v{{version}}
    version: ^0.1.0-dev.2
```

Pub can then select one compatible tagged GraphX revision for the entire
dependency graph. Applications should commit their `pubspec.lock` for exact
reproducibility.

The current coordinated baselines are:

- GraphX core: `v2.0.0-dev.2`
- GraphX package set: `v0.1.0-dev.2`

## Local development

For work against local checkouts, keep the committed dependency declarations
above and use an ignored `pubspec_overrides.yaml`:

```yaml
dependency_overrides:
  graphx:
    path: ../graphx
```

A root project may also temporarily override GraphX to `main` when explicitly
testing unreleased core work. Root overrides replace the transitive source
consistently; package manifests themselves must remain version-solved.

## Validation

```bash
./tool/check.sh
```

This resolves the workspace, verifies the dependency-source policy, analyzes
the monorepo, and runs each package's tests.

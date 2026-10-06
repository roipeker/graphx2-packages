# GraphX 2 Packages

Official first-party ecosystem packages for GraphX 2:
https://github.com/roipeker/graphx2

## Packages

- graphx_paths — retained geometric paths and allocation-aware spatial sampling.
- graphx_motion — tweens, retained timelines, keyframes, stagger, and motion physics.
- graphx_atlas — TexturePacker atlas decoding and GraphX asset-loading helpers.
- graphx_particles — packed retained particle emitters, fields, constraints, trails, and secondary effects.
- graphx_arcade — small deterministic fixed-step 2D arcade physics.

Each package is independently consumable from this monorepo using Dart Git
dependency path support. The package-set tag pins compatible public baselines.

Example:

    dependencies:
      graphx_arcade:
        git:
          url: https://github.com/roipeker/graphx2-packages.git
          path: packages/graphx_arcade
          ref: v0.1.0-dev.1

GraphX core is resolved from the public graphx2 repository. Local development
may use an ignored pubspec_overrides.yaml to point graphx at a sibling checkout
without changing committed dependency metadata.

## Development

    flutter pub get
    flutter analyze
    flutter test

The repository is an ordinary Dart workspace; package-specific tests may also
be run from each package directory.

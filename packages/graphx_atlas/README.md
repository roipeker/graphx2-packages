# graphx_atlas

Texture atlas decoding helpers for GraphX.

The runtime package decodes TexturePacker JSON into GraphX `GTextureAtlas` and
`GTexture` primitives and adds asset/network loading helpers to `GAssets`.

```dart
final atlas = await stage.assets.atlas('assets/game.json');
final player = atlas['player_idle'];
```

The package intentionally keeps build-time packing separate from runtime
decoding. Use a stable atlas packing CLI in the asset pipeline and consume the
generated JSON/image pair here.

## Install from GitHub

```yaml
dependencies:
  graphx_atlas:
    git:
      url: https://github.com/roipeker/graphx2-packages.git
      path: packages/graphx_atlas
      tag_pattern: v{{version}}
    version: ^0.1.0-dev.3
```

If the application also imports GraphX directly, declare GraphX using the same
version-solved Git form documented in the monorepo README.

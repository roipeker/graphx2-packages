# graphx_atlas

Texture atlas decoding helpers for GraphX.

The runtime package decodes TexturePacker JSON into GraphX GTextureAtlas and
GTexture primitives and adds asset/network loading helpers to GAssets.

Example:

    final atlas = await stage.assets.atlas('assets/game.json');
    final player = atlas['player_idle'];

The package intentionally keeps build-time packing separate from runtime
decoding. Use a stable atlas packing CLI in your asset pipeline and consume the
generated JSON/image pair here.

## Install from GitHub

    dependencies:
      graphx_atlas:
        git:
          url: https://github.com/roipeker/graphx2-packages.git
          path: packages/graphx_atlas
          ref: v0.1.0-dev.1

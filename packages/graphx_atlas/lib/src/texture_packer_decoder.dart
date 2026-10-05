import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:graphx/graphx.dart';

extension GTextureAtlasAssets on GAssets {
  /// Loads a TexturePacker JSON atlas from the Flutter asset bundle.
  Future<GTextureAtlas> atlas(
    String assetPath, {
    AssetBundle? bundle,
    bool cache = true,
  }) {
    final resolved = bundle ?? rootBundle;
    return load<GTextureAtlas>(
      ('texture-atlas', assetPath, resolved),
      () async {
        final data = await bytes(assetPath, bundle: resolved);
        final source = utf8.decode(data);
        final root = _parseAtlasJson(source);
        final image = _metaImage(root);
        final imagePath = _resolveAssetPath(assetPath, image);
        final page = await texture(imagePath, bundle: resolved);
        return _decodeTexturePacker(root, page);
      },
      cache: cache,
    );
  }

  /// Loads a TexturePacker JSON atlas and its page from the network.
  Future<GTextureAtlas> atlasUrl(String url, {bool cache = true}) {
    final uri = Uri.parse(url);
    return load<GTextureAtlas>(('texture-atlas-url', uri), () async {
      final data = await bytesUrl(url);
      final source = utf8.decode(data);
      final root = _parseAtlasJson(source);
      final image = _metaImage(root);
      final imageUrl = uri.resolve(image).toString();
      final page = await textureUrl(imageUrl);
      return _decodeTexturePacker(root, page);
    }, cache: cache);
  }

  /// Decodes TexturePacker JSON against an already loaded page texture.
  Future<GTextureAtlas> atlasString(
    String source, {
    required GTexture page,
    Object? key,
    bool cache = false,
  }) {
    Future<GTextureAtlas> decode() async {
      return _decodeTexturePacker(_parseAtlasJson(source), page);
    }

    if (!cache) return decode();
    if (key == null) {
      throw ArgumentError('key is required when caching atlas strings.');
    }
    return load<GTextureAtlas>(('texture-atlas-string', key), decode);
  }

  /// Decodes UTF-8 TexturePacker JSON bytes against an already loaded page.
  Future<GTextureAtlas> atlasBytes(
    Uint8List bytes, {
    required GTexture page,
    Object? key,
    bool cache = false,
  }) {
    return atlasString(utf8.decode(bytes), page: page, key: key, cache: cache);
  }
}

/// Decodes TexturePacker JSON metadata into Satechi's core atlas primitive.
///
/// Supports the common hash and array frame layouts. The supplied [page] is
/// borrowed; the returned atlas does not own or dispose it.
GTextureAtlas decodeTexturePackerAtlas(
  String source, {
  required GTexture page,
}) {
  return _decodeTexturePacker(_parseAtlasJson(source), page);
}

Map<String, Object?> _parseAtlasJson(String source) {
  final value = jsonDecode(source);
  if (value is! Map) {
    throw const FormatException('Texture atlas JSON root must be an object.');
  }
  return value.cast<String, Object?>();
}

String _metaImage(Map<String, Object?> root) {
  final meta = root['meta'];
  if (meta is! Map) {
    throw const FormatException('Texture atlas is missing meta data.');
  }
  final image = meta['image'];
  if (image is! String || image.isEmpty) {
    throw const FormatException('Texture atlas meta.image is missing.');
  }
  return image;
}

GTextureAtlas _decodeTexturePacker(Map<String, Object?> root, GTexture page) {
  final rawFrames = root['frames'];
  if (rawFrames == null) {
    throw const FormatException('Texture atlas is missing frames.');
  }

  final textures = <String, GTexture>{};

  if (rawFrames is Map) {
    for (final entry in rawFrames.entries) {
      final name = entry.key;
      final value = entry.value;
      if (name is! String || value is! Map) {
        throw const FormatException('Invalid TexturePacker frame entry.');
      }
      textures[name] = _decodeFrame(value.cast<String, Object?>(), page);
    }
  } else if (rawFrames is List) {
    for (final value in rawFrames) {
      if (value is! Map) {
        throw const FormatException('Invalid TexturePacker frame entry.');
      }
      final map = value.cast<String, Object?>();
      final name = map['filename'];
      if (name is! String || name.isEmpty) {
        throw const FormatException(
          'TexturePacker array frame has no filename.',
        );
      }
      textures[name] = _decodeFrame(map, page);
    }
  } else {
    throw const FormatException(
      'Texture atlas frames must be an object or list.',
    );
  }

  return GTextureAtlas(pages: <GTexture>[page], textures: textures);
}

GTexture _decodeFrame(Map<String, Object?> data, GTexture page) {
  final packed = _rect(data['frame'], 'frame');
  final rotated = data['rotated'] == true;

  final sourceSize = data['sourceSize'];
  final double sourceWidth;
  final double sourceHeight;
  if (sourceSize is Map) {
    sourceWidth = _number(sourceSize['w'], 'sourceSize.w');
    sourceHeight = _number(sourceSize['h'], 'sourceSize.h');
  } else if (rotated) {
    sourceWidth = packed.h;
    sourceHeight = packed.w;
  } else {
    sourceWidth = packed.w;
    sourceHeight = packed.h;
  }

  var offsetX = 0.0;
  var offsetY = 0.0;
  final spriteSource = data['spriteSourceSize'];
  if (spriteSource is Map) {
    offsetX = _number(spriteSource['x'], 'spriteSourceSize.x');
    offsetY = _number(spriteSource['y'], 'spriteSourceSize.y');
  }

  return page.region(
    region: packed,
    sourceWidth: sourceWidth,
    sourceHeight: sourceHeight,
    offsetX: offsetX,
    offsetY: offsetY,
    rotated: rotated,
  );
}

GRect _rect(Object? value, String field) {
  if (value is! Map) {
    throw FormatException('TexturePacker $field must be an object.');
  }
  return GRect(
    _number(value['x'], '$field.x'),
    _number(value['y'], '$field.y'),
    _number(value['w'], '$field.w'),
    _number(value['h'], '$field.h'),
  );
}

double _number(Object? value, String field) {
  if (value is num) return value.toDouble();
  throw FormatException('TexturePacker $field must be numeric.');
}

String _resolveAssetPath(String atlasPath, String imagePath) {
  if (imagePath.startsWith('/')) return imagePath.substring(1);
  return Uri(path: atlasPath).resolve(imagePath).path;
}

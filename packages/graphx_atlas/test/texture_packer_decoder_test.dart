import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:graphx/graphx.dart';
import 'package:graphx_atlas/graphx_atlas.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('decodes trimmed TexturePacker frame', () async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final paint = ui.Paint();
    paint.color = const ui.Color(0xffffffff);
    canvas.drawRect(const ui.Rect.fromLTWH(0, 0, 16, 16), paint);
    final picture = recorder.endRecording();
    final image = await picture.toImage(16, 16);
    final page = GTexture.owned(image);

    try {
      const source = '''
{
  "frames": {
    "coin": {
      "frame": {"x": 2, "y": 3, "w": 5, "h": 6},
      "rotated": false,
      "trimmed": true,
      "spriteSourceSize": {"x": 4, "y": 1, "w": 5, "h": 6},
      "sourceSize": {"w": 12, "h": 10}
    }
  },
  "meta": {"image": "atlas.png"}
}
''';

      final atlas = decodeTexturePackerAtlas(source, page: page);
      final coin = atlas['coin'];
      expect(coin.frame.region.x, 2);
      expect(coin.frame.region.y, 3);
      expect(coin.frame.region.w, 5);
      expect(coin.frame.region.h, 6);
      expect(coin.frame.sourceWidth, 12);
      expect(coin.frame.sourceHeight, 10);
      expect(coin.frame.offsetX, 4);
      expect(coin.frame.offsetY, 1);
    } finally {
      page.dispose();
    }
  });
}

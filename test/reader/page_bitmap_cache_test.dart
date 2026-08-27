import 'dart:ui' as ui;

import 'package:eink_launcher/reader/services/page_bitmap_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('evicts the least recently used bitmap to stay within budget', () async {
    final cache = PageBitmapCache(maxBytes: 800);
    const firstKey = PdfBitmapCacheKey(
      pageIndex: 0,
      pixelWidth: 10,
      pixelHeight: 10,
    );
    const secondKey = PdfBitmapCacheKey(
      pageIndex: 1,
      pixelWidth: 10,
      pixelHeight: 10,
    );
    const thirdKey = PdfBitmapCacheKey(
      pageIndex: 2,
      pixelWidth: 10,
      pixelHeight: 10,
    );

    expect(cache.put(firstKey, await _makeImage(10, 10)), isTrue);
    expect(cache.put(secondKey, await _makeImage(10, 10)), isTrue);
    expect(cache.currentBytes, 800);

    // Touch page 0, making page 1 the least recently used entry.
    expect(cache.get(firstKey), isNotNull);
    expect(cache.put(thirdKey, await _makeImage(10, 10)), isTrue);

    expect(cache.containsKey(firstKey), isTrue);
    expect(cache.containsKey(secondKey), isFalse);
    expect(cache.containsKey(thirdKey), isTrue);
    expect(cache.currentBytes, 800);

    cache.clear();
    expect(cache.isEmpty, isTrue);
    expect(cache.currentBytes, 0);
  });

  test('rejects a bitmap larger than the entire cache budget', () async {
    final cache = PageBitmapCache(maxBytes: 100);
    final image = await _makeImage(10, 10);

    expect(
      cache.put(
        const PdfBitmapCacheKey(pageIndex: 0, pixelWidth: 10, pixelHeight: 10),
        image,
      ),
      isFalse,
    );
    expect(cache.isEmpty, isTrue);

    // Rejected images remain owned by the caller.
    image.dispose();
  });
}

Future<ui.Image> _makeImage(int width, int height) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = const ui.Color(0xffffffff),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  picture.dispose();
  return image;
}

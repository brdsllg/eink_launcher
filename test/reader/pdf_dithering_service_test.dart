import 'dart:typed_data';

import 'package:eink_launcher/reader/services/pdf_dithering_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'quantizes gradients without bias and preserves black, white, alpha',
    () {
      final pixels = Uint8List.fromList(
        List.generate(
          64,
          (_) => [128, 128, 128, 255],
        ).expand((p) => p).toList(),
      );
      final result = PdfDitheringService.transformSync(
        pixels,
        8,
        8,
        colorEnabled: false,
      );
      final levels = [for (var i = 0; i < result.length; i += 4) result[i]];
      expect(levels.toSet(), {119, 136});
      expect(levels.reduce((a, b) => a + b) / levels.length, closeTo(128, .3));
      final extremes = Uint8List.fromList([
        0,
        0,
        0,
        255,
        255,
        255,
        255,
        255,
        20,
        30,
        40,
        128,
      ]);
      expect(
        PdfDitheringService.transformSync(extremes, 3, 1, colorEnabled: true),
        [0, 0, 0, 255, 255, 255, 255, 255, 20, 30, 40, 128],
      );
    },
  );
  test(
    'color mode retains channels and tile origins keep the pattern aligned',
    () {
      final pixel = Uint8List.fromList([0, 0, 255, 255]);
      expect(
        PdfDitheringService.transformSync(pixel, 1, 1, colorEnabled: true),
        [0, 0, 255, 255],
      );
      final whole = Uint8List.fromList(
        List.filled(16, [70, 110, 170, 255]).expand((p) => p).toList(),
      );
      final right = Uint8List.fromList(whole.sublist(8 * 4));
      PdfDitheringService.transformSync(whole, 16, 1, colorEnabled: true);
      PdfDitheringService.transformSync(
        right,
        8,
        1,
        colorEnabled: true,
        originX: 8,
      );
      expect(right, whole.sublist(8 * 4));
    },
  );
}

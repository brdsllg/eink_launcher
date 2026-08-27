import 'dart:typed_data';

import 'package:eink_launcher/reader/services/pdf_crop_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const width = 10;
  const height = 10;
  late PdfCropService service;

  setUp(() {
    service = PdfCropService();
  });

  test('finds normalized ink bounds', () async {
    final pixels = _whiteBgra(width, height);
    _fillBlack(pixels, width, left: 2, top: 3, right: 6, bottom: 7);

    final crop = await service.detectBgraCrop(
      pixels,
      width: width,
      height: height,
      minimumInkRun: 2,
      paddingFraction: 0,
    );

    expect(crop.left, closeTo(0.2, 0.0001));
    expect(crop.top, closeTo(0.3, 0.0001));
    expect(crop.right, closeTo(0.6, 0.0001));
    expect(crop.bottom, closeTo(0.7, 0.0001));
  });

  test('ignores isolated scanner specks', () async {
    final pixels = _whiteBgra(width, height);
    _fillBlack(pixels, width, left: 2, top: 3, right: 6, bottom: 7);
    _setBgra(pixels, width, 9, 9, blue: 0, green: 0, red: 0);

    final crop = await service.detectBgraCrop(
      pixels,
      width: width,
      height: height,
      minimumInkRun: 2,
      paddingFraction: 0,
    );

    expect(crop.toList(), [0.2, 0.3, 0.6, 0.7]);
  });

  test('returns the full page when no ink is found', () async {
    final crop = await service.detectBgraCrop(
      _whiteBgra(width, height),
      width: width,
      height: height,
    );

    expect(crop.toList(), PdfCropRect.fullPage.toList());
  });

  test('composites transparent pixels over white', () async {
    final pixels = _whiteBgra(width, height);
    _setBgra(pixels, width, 5, 5, blue: 0, green: 0, red: 0, alpha: 0);

    final crop = await service.detectBgraCrop(
      pixels,
      width: width,
      height: height,
      minimumInkRun: 1,
      paddingFraction: 0,
    );

    expect(crop.toList(), PdfCropRect.fullPage.toList());
  });
}

Uint8List _whiteBgra(int width, int height) {
  final pixels = Uint8List(width * height * 4);
  for (var offset = 0; offset < pixels.length; offset += 4) {
    pixels[offset] = 255;
    pixels[offset + 1] = 255;
    pixels[offset + 2] = 255;
    pixels[offset + 3] = 255;
  }
  return pixels;
}

void _fillBlack(
  Uint8List pixels,
  int width, {
  required int left,
  required int top,
  required int right,
  required int bottom,
}) {
  for (var y = top; y < bottom; y++) {
    for (var x = left; x < right; x++) {
      _setBgra(pixels, width, x, y, blue: 0, green: 0, red: 0);
    }
  }
}

void _setBgra(
  Uint8List pixels,
  int width,
  int x,
  int y, {
  required int blue,
  required int green,
  required int red,
  int alpha = 255,
}) {
  final offset = (y * width + x) * 4;
  pixels[offset] = blue;
  pixels[offset + 1] = green;
  pixels[offset + 2] = red;
  pixels[offset + 3] = alpha;
}

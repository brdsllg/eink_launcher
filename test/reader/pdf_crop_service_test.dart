import 'dart:typed_data';

import 'package:eink_launcher/reader/services/pdf_crop_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

void main() {
  const width = 10;
  const height = 10;
  late PdfCropService service;

  setUp(() {
    service = PdfCropService();
  });

  test('caps crop samples before rendering extreme page geometry', () async {
    for (final size in [
      (width: 1.0, height: 1e100),
      (width: 1e100, height: 1.0),
      (width: 1e-300, height: 1e300),
    ]) {
      final page = _RecordingCropPage(size.width, size.height);
      await service.detectPageCrop(page);
      expect(page.renderWidth, inInclusiveRange(1, 512));
      expect(page.renderHeight, inInclusiveRange(1, 512));
    }
    final ordinary = _RecordingCropPage(200, 300);
    await service.detectPageCrop(ordinary);
    expect((ordinary.renderWidth, ordinary.renderHeight), (200, 300));
  });

  test(
    'rejects invalid crop geometry before submitting a native render',
    () async {
      for (final width in [0.0, -1.0, double.nan, double.infinity]) {
        final page = _RecordingCropPage(width, 300);
        await expectLater(service.detectPageCrop(page), throwsFormatException);
        expect(page.renderWidth, isNull);
      }
    },
  );

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

  test('reports blank samples separately from full-page crop bounds', () async {
    final detection = await service.detectBgraCropResult(
      _whiteBgra(width, height),
      width: width,
      height: height,
    );

    expect(detection.hasInk, isFalse);
    expect(detection.rect.toList(), PdfCropRect.fullPage.toList());
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

  test('spreads uniform-crop samples across the whole document', () {
    expect(PdfCropService.samplePageIndices(100), [
      0,
      11,
      22,
      33,
      44,
      55,
      66,
      77,
      88,
      99,
    ]);
    expect(PdfCropService.samplePageIndices(3), [0, 1, 2]);
  });

  test('unions sampled ink rectangles', () {
    final crop = PdfCropService.unionCropRects(const [
      PdfCropRect(left: 0.2, top: 0.1, right: 0.8, bottom: 0.9),
      PdfCropRect(left: 0.1, top: 0.2, right: 0.9, bottom: 0.8),
    ]);

    expect(crop.toList(), [0.1, 0.1, 0.9, 0.9]);
    expect(
      PdfCropService.unionCropRects(const []).toList(),
      PdfCropRect.fullPage.toList(),
    );
  });
}

class _RecordingCropPage implements PdfPage {
  @override
  final double width;
  @override
  final double height;
  int? renderWidth;
  int? renderHeight;

  _RecordingCropPage(this.width, this.height);

  @override
  Future<PdfImage?> render({
    int x = 0,
    int y = 0,
    int? width,
    int? height,
    double? fullWidth,
    double? fullHeight,
    int? backgroundColor,
    PdfPageRotation? rotationOverride,
    PdfAnnotationRenderingMode annotationRenderingMode =
        PdfAnnotationRenderingMode.annotationAndForms,
    int flags = PdfPageRenderFlags.none,
    PdfPageRenderCancellationToken? cancellationToken,
  }) async {
    renderWidth = width;
    renderHeight = height;
    // Capture dimensions without allocating the very buffer this test protects.
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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

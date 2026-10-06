import 'dart:ui';

import 'package:eink_launcher/reader/models/reader_settings.dart';
import 'package:eink_launcher/reader/services/pdf_crop_service.dart';
import 'package:eink_launcher/reader/services/pdf_document_service.dart';
import 'package:eink_launcher/reader/services/pdf_fit_geometry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

void main() {
  PdfPageInfo info(double w, double h) => PdfPageInfo(
        pageIndex: 0,
        width: w,
        height: h,
        rotation: PdfPageRotation.none,
      );

  test('fitHeight keeps aspect and full crop', () {
    final out = pdfFitGeometry(
      info: info(600, 800),
      crop: PdfCropRect.fullPage,
      viewport: const Size(400, 600),
      withinPage: 0,
      devicePixelRatio: 2,
      fitMode: PdfFitMode.fitHeight,
    );
    expect(out.pixelHeight, 1200);
    expect(out.pixelWidth, 900);
    expect(out.crop, PdfCropRect.fullPage);
  });

  test('fitWidth slices to one viewport and zoom throws', () {
    final out = pdfFitGeometry(
      info: info(600, 1200),
      crop: PdfCropRect.fullPage,
      viewport: const Size(400, 600),
      withinPage: 0,
      devicePixelRatio: 1,
      fitMode: PdfFitMode.fitWidth,
    );
    expect(out.pixelWidth, 400);
    expect(out.crop.left, 0);
    expect(
      () => pdfFitGeometry(
        info: info(600, 800),
        crop: PdfCropRect.fullPage,
        viewport: const Size(400, 600),
        withinPage: 0,
        devicePixelRatio: 1,
        fitMode: PdfFitMode.zoom,
      ),
      throwsStateError,
    );
  });

  test('sub-screen starts cover tall pages with overlap', () {
    final starts = pdfSubScreenStarts(
      croppedWidth: 400,
      croppedHeight: 1200,
      viewport: const Size(400, 600),
      overlap: 0.1,
    );
    expect(starts.first, 0);
    expect(starts.last, greaterThan(0));
    expect(
      pdfSubScreenStarts(
        croppedWidth: 400,
        croppedHeight: 400,
        viewport: const Size(400, 600),
        overlap: 0.1,
      ),
      const [0.0],
    );
    expect(pdfNearestIndex([0.0, 0.5, 1.0], 0.6), 1);
  });
}

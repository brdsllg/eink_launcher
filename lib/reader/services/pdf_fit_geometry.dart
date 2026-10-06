import 'dart:ui';

import '../models/reader_settings.dart';
import 'pdf_crop_service.dart';
import 'pdf_document_service.dart';

/// Pure page math pulled out of `PdfReaderSession` so it can be tested
/// without a document handle. No behavior change: the session calls these.
({int pixelWidth, int pixelHeight, PdfCropRect crop}) pdfFitGeometry({
  required PdfPageInfo info,
  required PdfCropRect crop,
  required Size viewport,
  required double withinPage,
  required double devicePixelRatio,
  required PdfFitMode fitMode,
}) {
  final croppedWidth = info.width * crop.width;
  final croppedHeight = info.height * crop.height;

  switch (fitMode) {
    case PdfFitMode.fitHeight:
      final pixelHeight = (viewport.height * devicePixelRatio).round();
      final pixelWidth =
          (viewport.height * croppedWidth / croppedHeight * devicePixelRatio)
              .round();
      return (pixelWidth: pixelWidth, pixelHeight: pixelHeight, crop: crop);

    case PdfFitMode.fitWidth:
      final scale = viewport.width / croppedWidth;
      final scaledHeight = croppedHeight * scale;
      final subFracHeight = scaledHeight <= 0
          ? 1.0
          : clampDouble(viewport.height / scaledHeight, 0.0, 1.0);
      final top = clampDouble(
        crop.top + withinPage * crop.height,
        crop.top,
        crop.bottom - 0.0001,
      );
      final bottom = clampDouble(
        top + subFracHeight * crop.height,
        top + 0.0001,
        crop.bottom,
      );
      final subCrop = PdfCropRect(
        left: crop.left,
        top: top,
        right: crop.right,
        bottom: bottom,
      );
      return (
        pixelWidth: (viewport.width * devicePixelRatio).round(),
        pixelHeight: (info.height * subCrop.height * scale * devicePixelRatio)
            .round()
            .clamp(1, 2147483647),
        crop: subCrop,
      );

    case PdfFitMode.zoom:
      throw StateError(
        'Zoom / Scroll geometry is owned by PdfContinuousLayout',
      );
  }
}

/// Vertical start fractions (of the *cropped* page) for each fit-width
/// sub-screen. `[0.0]` when the page fits in one screen.
List<double> pdfSubScreenStarts({
  required double croppedWidth,
  required double croppedHeight,
  required Size viewport,
  required double overlap,
}) {
  if (croppedWidth <= 0 ||
      croppedHeight <= 0 ||
      viewport.width <= 0 ||
      viewport.height <= 0) {
    return const [0.0];
  }
  final scale = viewport.width / croppedWidth;
  final scaledHeight = croppedHeight * scale;
  if (scaledHeight <= viewport.height) return const [0.0];

  final clampedOverlap = clampDouble(overlap, 0.0, 0.9);
  final step = viewport.height * (1 - clampedOverlap);
  final starts = <double>[0.0];
  var offset = step;
  while (offset < scaledHeight - viewport.height) {
    starts.add(offset / scaledHeight);
    offset += step;
  }
  starts.add(
    clampDouble((scaledHeight - viewport.height) / scaledHeight, 0.0, 1.0),
  );
  return starts;
}

int pdfNearestIndex(List<double> values, double target) {
  var bestIndex = 0;
  var bestDelta = double.infinity;
  for (var i = 0; i < values.length; i++) {
    final delta = (values[i] - target).abs();
    if (delta < bestDelta) {
      bestDelta = delta;
      bestIndex = i;
    }
  }
  return bestIndex;
}

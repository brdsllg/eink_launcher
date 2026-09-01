import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdfrx/pdfrx.dart';

import '../../constants.dart';
import 'pdf_render_scheduler.dart';

/// A normalized PDF crop rectangle. All edges are fractions of page size.
class PdfCropRect {
  final double left;
  final double top;
  final double right;
  final double bottom;

  const PdfCropRect({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  }) : assert(left >= 0 && left < right),
       assert(top >= 0 && top < bottom),
       assert(right <= 1),
       assert(bottom <= 1);

  static const fullPage = PdfCropRect(left: 0, top: 0, right: 1, bottom: 1);

  double get width => right - left;
  double get height => bottom - top;

  List<double> toList() => [left, top, right, bottom];

  factory PdfCropRect.fromList(List<double> values) {
    if (values.length != 4) {
      throw ArgumentError.value(values, 'values', 'Expected four crop edges');
    }
    return PdfCropRect(
      left: values[0],
      top: values[1],
      right: values[2],
      bottom: values[3],
    );
  }
}

class PdfCropDetection {
  final PdfCropRect rect;
  final bool hasInk;

  const PdfCropDetection({required this.rect, required this.hasInk});
}

/// Detects PDF content bounds from low-resolution BGRA page renders.
class PdfCropService {
  static const int defaultSampleWidth = 200;
  static const int maxSampleDimension = 512;
  static const int defaultMinimumInkRun = 3;
  static const double defaultPaddingFraction = 0.015;

  /// Renders a small page preview and scans it outside the UI isolate.
  Future<PdfCropRect> detectPageCrop(
    PdfPage page, {
    int sampleWidth = defaultSampleWidth,
    int luminanceThreshold = kPdfInkLuminanceThreshold,
    int minimumInkRun = defaultMinimumInkRun,
    double paddingFraction = defaultPaddingFraction,
    PdfRenderRequest? request,
  }) async {
    return (await detectPageCropResult(
      page,
      sampleWidth: sampleWidth,
      luminanceThreshold: luminanceThreshold,
      minimumInkRun: minimumInkRun,
      paddingFraction: paddingFraction,
      request: request,
    )).rect;
  }

  /// Like [detectPageCrop], but preserves whether qualifying ink was found so
  /// blank sampled pages do not expand a document-uniform crop to full-page.
  Future<PdfCropDetection> detectPageCropResult(
    PdfPage page, {
    int sampleWidth = defaultSampleWidth,
    int luminanceThreshold = kPdfInkLuminanceThreshold,
    int minimumInkRun = defaultMinimumInkRun,
    double paddingFraction = defaultPaddingFraction,
    PdfRenderRequest? request,
  }) {
    return PdfRenderScheduler.instance.schedule(
      () => _detectPageCropResultNow(
        page,
        sampleWidth: sampleWidth,
        luminanceThreshold: luminanceThreshold,
        minimumInkRun: minimumInkRun,
        paddingFraction: paddingFraction,
      ),
      request: request,
    );
  }

  Future<PdfCropDetection> _detectPageCropResultNow(
    PdfPage page, {
    required int sampleWidth,
    required int luminanceThreshold,
    required int minimumInkRun,
    required double paddingFraction,
  }) async {
    if (sampleWidth <= 0) {
      throw ArgumentError.value(sampleWidth, 'sampleWidth', 'Must be positive');
    }
    if (!page.width.isFinite ||
        !page.height.isFinite ||
        page.width <= 0 ||
        page.height <= 0) {
      throw const FormatException('PDF contains invalid page geometry.');
    }
    final ratio = page.width / page.height;
    // Cap both dimensions BEFORE page.render allocates its native buffer.
    // This also handles very tall/narrow pages without rounding infinity.
    final outputWidth = math.max(
      1,
      math
          .min(
            sampleWidth.toDouble(),
            math.min(maxSampleDimension.toDouble(), maxSampleDimension * ratio),
          )
          .round(),
    );
    final sampleHeight = math.max(
      1,
      math.min(maxSampleDimension.toDouble(), outputWidth / ratio).round(),
    );
    final rendered = await page.render(
      fullWidth: outputWidth.toDouble(),
      fullHeight: sampleHeight.toDouble(),
      width: outputWidth,
      height: sampleHeight,
      flags:
          PdfPageRenderFlags.grayscale | PdfPageRenderFlags.limitedImageCache,
    );
    if (rendered == null) {
      return const PdfCropDetection(rect: PdfCropRect.fullPage, hasInk: false);
    }

    try {
      // Copy before disposing the native PdfImage backing store.
      final pixels = Uint8List.fromList(rendered.pixels);
      return await detectBgraCropResult(
        pixels,
        width: rendered.width,
        height: rendered.height,
        luminanceThreshold: luminanceThreshold,
        minimumInkRun: minimumInkRun,
        paddingFraction: paddingFraction,
      );
    } finally {
      rendered.dispose();
    }
  }

  /// Scans a BGRA8888 image for ink and returns its padded normalized bounds.
  Future<PdfCropRect> detectBgraCrop(
    Uint8List pixels, {
    required int width,
    required int height,
    int luminanceThreshold = kPdfInkLuminanceThreshold,
    int minimumInkRun = defaultMinimumInkRun,
    double paddingFraction = defaultPaddingFraction,
  }) async {
    return (await detectBgraCropResult(
      pixels,
      width: width,
      height: height,
      luminanceThreshold: luminanceThreshold,
      minimumInkRun: minimumInkRun,
      paddingFraction: paddingFraction,
    )).rect;
  }

  Future<PdfCropDetection> detectBgraCropResult(
    Uint8List pixels, {
    required int width,
    required int height,
    int luminanceThreshold = kPdfInkLuminanceThreshold,
    int minimumInkRun = defaultMinimumInkRun,
    double paddingFraction = defaultPaddingFraction,
  }) async {
    if (width <= 0 || height <= 0) {
      throw ArgumentError('Image dimensions must be positive');
    }
    if (pixels.lengthInBytes != width * height * 4) {
      throw ArgumentError.value(
        pixels.lengthInBytes,
        'pixels',
        'Expected ${width * height * 4} BGRA bytes',
      );
    }
    if (luminanceThreshold < 0 || luminanceThreshold > 255) {
      throw RangeError.range(luminanceThreshold, 0, 255, 'luminanceThreshold');
    }
    if (minimumInkRun <= 0) {
      throw ArgumentError.value(
        minimumInkRun,
        'minimumInkRun',
        'Must be positive',
      );
    }
    if (paddingFraction < 0 || paddingFraction >= 0.5) {
      throw ArgumentError.value(
        paddingFraction,
        'paddingFraction',
        'Must be at least 0 and less than 0.5',
      );
    }

    final transferable = TransferableTypedData.fromList([pixels]);
    final result = await Isolate.run<List<double>>(
      () => _scanBgraCrop(
        transferable.materialize().asUint8List(),
        width,
        height,
        luminanceThreshold,
        minimumInkRun,
        paddingFraction,
      ),
    );
    return PdfCropDetection(
      rect: PdfCropRect.fromList(result.take(4).toList(growable: false)),
      hasInk: result[4] != 0,
    );
  }

  /// Samples pages spread across a document and unions their detected ink
  /// bounds. Page dimensions remain stable throughout continuous scrolling.
  Future<PdfCropRect> detectDocumentCrop({
    required int pageCount,
    required PdfPage Function(int pageIndex) pageAt,
    int maxSamples = 10,
    PdfRenderRequest? request,
  }) async {
    if (pageCount <= 0) return PdfCropRect.fullPage;
    final crops = <PdfCropRect>[];
    for (final pageIndex in samplePageIndices(
      pageCount,
      maxSamples: maxSamples,
    )) {
      try {
        request?.throwIfCancelled();
        final detection = await detectPageCropResult(
          pageAt(pageIndex),
          request: request,
        );
        if (detection.hasInk) crops.add(detection.rect);
      } on PdfRenderCancelledException {
        rethrow;
      } catch (_) {
        // One malformed page should not disable continuous mode for the book.
      }
    }
    return unionCropRects(crops);
  }

  static List<int> samplePageIndices(int pageCount, {int maxSamples = 10}) {
    if (pageCount <= 0) return const [];
    if (maxSamples <= 0) {
      throw ArgumentError.value(maxSamples, 'maxSamples', 'Must be positive');
    }
    final count = math.min(pageCount, maxSamples);
    if (count == 1) return const [0];
    return List<int>.generate(
      count,
      (index) => (index * (pageCount - 1) / (count - 1)).round(),
      growable: false,
    );
  }

  static PdfCropRect unionCropRects(Iterable<PdfCropRect> crops) {
    final values = crops.toList(growable: false);
    if (values.isEmpty) return PdfCropRect.fullPage;
    return PdfCropRect(
      left: values.map((crop) => crop.left).reduce(math.min),
      top: values.map((crop) => crop.top).reduce(math.min),
      right: values.map((crop) => crop.right).reduce(math.max),
      bottom: values.map((crop) => crop.bottom).reduce(math.max),
    );
  }
}

List<double> _scanBgraCrop(
  Uint8List pixels,
  int width,
  int height,
  int threshold,
  int minimumRun,
  double paddingFraction,
) {
  final ink = Uint8List(width * height);
  for (var pixelIndex = 0; pixelIndex < ink.length; pixelIndex++) {
    final offset = pixelIndex * 4;
    final blue = pixels[offset];
    final green = pixels[offset + 1];
    final red = pixels[offset + 2];
    final alpha = pixels[offset + 3];
    final rawLuminance = (299 * red + 587 * green + 114 * blue) ~/ 1000;
    final compositedLuminance =
        (rawLuminance * alpha + 255 * (255 - alpha)) ~/ 255;
    if (compositedLuminance < threshold) ink[pixelIndex] = 1;
  }

  var minX = width;
  var minY = height;
  var maxX = -1;
  var maxY = -1;

  void includeRun(int startX, int startY, int endX, int endY) {
    minX = math.min(minX, math.min(startX, endX));
    minY = math.min(minY, math.min(startY, endY));
    maxX = math.max(maxX, math.max(startX, endX));
    maxY = math.max(maxY, math.max(startY, endY));
  }

  // A pixel is accepted when it belongs to a sufficiently long horizontal or
  // vertical run. This removes isolated scanner dust without erasing strokes.
  for (var y = 0; y < height; y++) {
    var runStart = -1;
    for (var x = 0; x <= width; x++) {
      final isInk = x < width && ink[y * width + x] != 0;
      if (isInk && runStart == -1) runStart = x;
      if (!isInk && runStart != -1) {
        if (x - runStart >= minimumRun) {
          includeRun(runStart, y, x - 1, y);
        }
        runStart = -1;
      }
    }
  }
  for (var x = 0; x < width; x++) {
    var runStart = -1;
    for (var y = 0; y <= height; y++) {
      final isInk = y < height && ink[y * width + x] != 0;
      if (isInk && runStart == -1) runStart = y;
      if (!isInk && runStart != -1) {
        if (y - runStart >= minimumRun) {
          includeRun(x, runStart, x, y - 1);
        }
        runStart = -1;
      }
    }
  }

  if (maxX < minX || maxY < minY) return [0, 0, 1, 1, 0];

  final paddingX = (width * paddingFraction).ceil();
  final paddingY = (height * paddingFraction).ceil();
  minX = math.max(0, minX - paddingX);
  minY = math.max(0, minY - paddingY);
  maxX = math.min(width - 1, maxX + paddingX);
  maxY = math.min(height - 1, maxY + paddingY);

  return [
    minX / width,
    minY / height,
    (maxX + 1) / width,
    (maxY + 1) / height,
    1,
  ];
}

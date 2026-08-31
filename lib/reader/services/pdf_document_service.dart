import 'dart:math' as math;
import 'dart:io';
import 'dart:ui';

import 'package:pdfrx/pdfrx.dart';

import '../../constants.dart';
import '../models/reading_position.dart';
import '../models/toc_entry.dart';
import 'pdf_crop_service.dart';
import 'pdf_runtime_service.dart';

typedef PdfDocumentOpener = Future<PdfDocument> Function(
  String filePath,
  PdfPasswordProvider? passwordProvider,
);

class PdfPageInfo {
  final int pageIndex;
  final double width;
  final double height;
  final PdfPageRotation rotation;

  const PdfPageInfo({
    required this.pageIndex,
    required this.width,
    required this.height,
    required this.rotation,
  });
}

/// Owns a single pdfrx document handle and exposes reader-oriented operations.
class PdfDocumentService {
  final String filePath;
  final PdfDocumentOpener _documentOpener;
  PdfDocument? _document;
  int _generation = 0;

  PdfDocumentService(this.filePath, {PdfDocumentOpener? documentOpener})
    : _documentOpener = documentOpener ?? _openPdfDocument;

  bool get isOpen => _document != null;

  int get pageCount => _requireDocument().pages.length;

  Future<void> open({PdfPasswordProvider? passwordProvider}) async {
    if (_document != null) return;
    final generation = _generation;
    final document = await _documentOpener(filePath, passwordProvider);
    if (generation != _generation) {
      await document.dispose();
      throw StateError('PDF opening was cancelled.');
    }
    if (document.pages.isEmpty ||
        document.pages.any(
          (page) =>
              !page.width.isFinite ||
              !page.height.isFinite ||
              page.width <= 0 ||
              page.height <= 0,
        )) {
      await document.dispose();
      throw const FormatException('PDF contains no valid page geometry.');
    }
    _document = document;
  }

  PdfPageInfo pageInfo(int pageIndex) {
    final page = pageAt(pageIndex);
    return PdfPageInfo(
      pageIndex: pageIndex,
      width: page.width,
      height: page.height,
      rotation: page.rotation,
    );
  }

  /// Returns a borrowed page handle that is valid until [close].
  PdfPage pageAt(int pageIndex) {
    final pages = _requireDocument().pages;
    if (pageIndex < 0 || pageIndex >= pages.length) {
      throw RangeError.index(pageIndex, pages, 'pageIndex');
    }
    return pages[pageIndex];
  }

  /// Renders [crop] into a Flutter image at the requested output size.
  ///
  /// The output is capped on its long edge to protect the e-ink device from
  /// unexpectedly large allocations. The caller owns and must dispose it.
  Future<Image> renderPage({
    required int pageIndex,
    required int pixelWidth,
    required int pixelHeight,
    PdfCropRect crop = PdfCropRect.fullPage,
    PdfPageRotation? rotationOverride,
    double maxDimension = kPdfMaxRenderDimension,
  }) async {
    final dimensions = constrainedRenderSize(
      pixelWidth,
      pixelHeight,
      maxDimension: maxDimension,
    );
    final fullWidth = dimensions.width / crop.width;
    final fullHeight = dimensions.height / crop.height;
    final x = (crop.left * fullWidth).round();
    final y = (crop.top * fullHeight).round();
    final page = pageAt(pageIndex);
    final rendered = await page.render(
      x: x,
      y: y,
      width: dimensions.width,
      height: dimensions.height,
      fullWidth: fullWidth,
      fullHeight: fullHeight,
      rotationOverride: rotationOverride,
      flags: PdfPageRenderFlags.limitedImageCache,
    );
    if (rendered == null) {
      throw StateError('PDF page ${pageIndex + 1} render was cancelled');
    }
    try {
      return await rendered.createImage();
    } finally {
      rendered.dispose();
    }
  }

  Future<List<TocEntry>> loadOutline() async {
    final nodes = await _requireDocument().loadOutline();
    return _convertOutline(nodes, 0);
  }

  Future<void> close() async {
    _generation++;
    final document = _document;
    _document = null;
    await document?.dispose();
  }

  PdfDocument _requireDocument() {
    final document = _document;
    if (document == null) {
      throw StateError('PDF document is not open');
    }
    return document;
  }

  List<TocEntry> _convertOutline(List<PdfOutlineNode> nodes, int level) {
    return nodes
        .map((node) {
          final destination = node.dest;
          final pageIndex = destination == null
              ? null
              : math.max(
                  0,
                  math.min(pageCount - 1, destination.pageNumber - 1),
                );
          return TocEntry(
            title: node.title,
            level: level,
            position: pageIndex == null
                ? null
                : PdfReadingPosition(pageIndex: pageIndex),
            children: _convertOutline(node.children, level + 1),
          );
        })
        .toList(growable: false);
  }

  static ({int width, int height}) constrainedRenderSize(
    int width,
    int height, {
    double maxDimension = kPdfMaxRenderDimension,
  }) {
    if (width <= 0 || height <= 0) {
      throw ArgumentError('Render dimensions must be positive');
    }
    if (maxDimension <= 0) {
      throw ArgumentError.value(
        maxDimension,
        'maxDimension',
        'Must be positive',
      );
    }
    final longestEdge = math.max(width, height);
    if (longestEdge <= maxDimension) return (width: width, height: height);
    final scale = maxDimension / longestEdge;
    return (
      width: math.max(1, (width * scale).round()),
      height: math.max(1, (height * scale).round()),
    );
  }

  static Future<PdfDocument> _openPdfDocument(
    String filePath,
    PdfPasswordProvider? passwordProvider,
  ) async {
    if (!await File(filePath).exists()) {
      throw PathNotFoundException(
        filePath,
        const OSError('PDF file is missing.', 2),
      );
    }
    await PdfRuntimeService.ensureInitialized();
    return PdfDocument.openFile(filePath, passwordProvider: passwordProvider);
  }
}

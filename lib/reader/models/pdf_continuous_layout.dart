import 'dart:ui';

import 'reading_position.dart';

/// Exact page extents and cumulative offsets for fit-width PDF scrolling.
class PdfContinuousLayout {
  final double viewportWidth;
  final List<double> pageHeights;
  final List<double> cumulativeOffsets;

  const PdfContinuousLayout._({
    required this.viewportWidth,
    required this.pageHeights,
    required this.cumulativeOffsets,
  });

  factory PdfContinuousLayout.fromPageSizes({
    required List<Size> pageSizes,
    required double viewportWidth,
    double cropWidth = 1,
    double cropHeight = 1,
  }) {
    if (viewportWidth <= 0 || cropWidth <= 0 || cropHeight <= 0) {
      throw ArgumentError('Viewport and crop dimensions must be positive');
    }
    final heights = <double>[];
    final offsets = <double>[0];
    for (final size in pageSizes) {
      if (size.width <= 0 || size.height <= 0) {
        throw ArgumentError('PDF page dimensions must be positive');
      }
      final height =
          viewportWidth * (size.height * cropHeight) / (size.width * cropWidth);
      heights.add(height);
      offsets.add(offsets.last + height);
    }
    return PdfContinuousLayout._(
      viewportWidth: viewportWidth,
      pageHeights: List.unmodifiable(heights),
      cumulativeOffsets: List.unmodifiable(offsets),
    );
  }

  int get pageCount => pageHeights.length;
  double get totalHeight => cumulativeOffsets.last;

  double pageTop(int pageIndex) => cumulativeOffsets[_clampPage(pageIndex)];

  double offsetForPosition(
    PdfReadingPosition position, {
    required double viewportHeight,
  }) {
    if (pageCount == 0) return 0;
    final pageIndex = _clampPage(position.pageIndex);
    final fraction = position.withinPage.clamp(0.0, 1.0).toDouble();
    final raw = pageTop(pageIndex) + pageHeights[pageIndex] * fraction;
    return raw.clamp(0.0, maxScrollOffset(viewportHeight)).toDouble();
  }

  PdfReadingPosition positionForOffset(double offset) {
    if (pageCount == 0) return const PdfReadingPosition(pageIndex: 0);
    final clamped = offset.clamp(0.0, totalHeight).toDouble();
    final pageIndex = pageAtOffset(clamped);
    final withinPage = pageHeights[pageIndex] == 0
        ? 0.0
        : ((clamped - pageTop(pageIndex)) / pageHeights[pageIndex])
              .clamp(0.0, 0.999999)
              .toDouble();
    return PdfReadingPosition(pageIndex: pageIndex, withinPage: withinPage);
  }

  int pageAtOffset(double offset) {
    if (pageCount == 0) return 0;
    final target = offset.clamp(0.0, totalHeight).toDouble();
    var low = 0;
    var high = pageCount;
    while (low < high) {
      final middle = (low + high) >> 1;
      if (cumulativeOffsets[middle + 1] <= target && middle < pageCount - 1) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low.clamp(0, pageCount - 1).toInt();
  }

  int dominantPage(double offset, double viewportHeight) {
    if (pageCount == 0) return 0;
    final viewportTop = offset.clamp(0.0, totalHeight).toDouble();
    final viewportBottom = viewportTop + viewportHeight;
    var page = pageAtOffset(viewportTop);
    var bestPage = page;
    var bestVisible = -1.0;
    while (page < pageCount && pageTop(page) < viewportBottom) {
      final visibleTop = pageTop(page) > viewportTop
          ? pageTop(page)
          : viewportTop;
      final pageBottom = cumulativeOffsets[page + 1];
      final visibleBottom = pageBottom < viewportBottom
          ? pageBottom
          : viewportBottom;
      final visible = (visibleBottom - visibleTop)
          .clamp(0.0, double.infinity)
          .toDouble();
      if (visible > bestVisible) {
        bestVisible = visible;
        bestPage = page;
      }
      page += 1;
    }
    return bestPage;
  }

  double maxScrollOffset(double viewportHeight) =>
      (totalHeight - viewportHeight).clamp(0.0, double.infinity).toDouble();

  int _clampPage(int pageIndex) => pageIndex.clamp(0, pageCount - 1).toInt();
}

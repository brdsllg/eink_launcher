import 'dart:ui';

import 'package:eink_launcher/reader/models/pdf_continuous_layout.dart';
import 'package:eink_launcher/reader/models/reading_position.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final layout = PdfContinuousLayout.fromPageSizes(
    pageSizes: const [Size(100, 200), Size(100, 100), Size(200, 100)],
    viewportWidth: 200,
  );

  test('calculates exact page heights and cumulative offsets', () {
    expect(layout.pageHeights, [400, 200, 100]);
    expect(layout.cumulativeOffsets, [0, 400, 600, 700]);
    expect(layout.totalHeight, 700);
  });

  test('maps offsets and logical positions in both directions', () {
    final position = layout.positionForOffset(450);
    expect(position.pageIndex, 1);
    expect(position.withinPage, closeTo(0.25, 0.0001));
    expect(
      layout.offsetForPosition(position, viewportHeight: 200),
      closeTo(450, 0.0001),
    );
  });

  test('selects the page occupying the most viewport area', () {
    // Viewport 350..550 contains 50 px of page 0 and 150 px of page 1.
    expect(layout.dominantPage(350, 200), 1);
  });

  test('clamps restored positions to the reachable scroll extent', () {
    const end = PdfReadingPosition(pageIndex: 2, withinPage: 0.8);
    expect(layout.offsetForPosition(end, viewportHeight: 200), 500);
  });
}

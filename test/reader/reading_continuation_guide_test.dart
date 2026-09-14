import 'dart:ui' as ui;

import 'package:eink_launcher/reader/widgets/reading_continuation_guide.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'arrows mark both screen edges without blocking touch or covering the center',
    (tester) async {
      var taps = 0;
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: RepaintBoundary(
              key: boundaryKey,
              child: SizedBox(
                width: 300,
                height: 200,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    GestureDetector(
                      onTap: () => taps++,
                      child: const ColoredBox(color: Colors.white),
                    ),
                    const ReadingContinuationGuide(y: 60),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      final bounds = tester.getRect(find.byType(ReadingContinuationGuide));
      await tester.tapAt(bounds.topLeft + const Offset(12, 60));
      await tester.tapAt(bounds.topLeft + const Offset(288, 60));
      expect(taps, 2);
      final boundary =
          boundaryKey.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
      final bytes = (await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        image.dispose();
        return bytes;
      }))!;
      int redAt(int x, int y) => bytes.getUint8((y * 300 + x) * 4);
      expect(redAt(12, 60), 0);
      expect(redAt(288, 60), 0);
      expect(redAt(150, 60), 255);
      expect(redAt(12, 40), 255);
    },
  );
}

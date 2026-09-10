import 'dart:io';
import 'dart:ui' as ui;

import 'package:eink_launcher/reader/models/content_block.dart';
import 'package:eink_launcher/reader/models/laid_out_page.dart';
import 'package:eink_launcher/reader/models/reader_settings.dart';
import 'package:eink_launcher/reader/services/epub_paginator_service.dart';
import 'package:eink_launcher/reader/widgets/block_slice_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'painted hyphens contain visible ink using the bundled reading font',
    (tester) async {
      final loader = FontLoader('Literata')
        ..addFont(rootBundle.load('assets/fonts/Literata-Regular.ttf'));
      await loader.load();
      const block = ContentBlock(
        type: BlockType.paragraph,
        runs: [
          InlineRun(
            text:
                'Extraordinary internationalization demonstrates encyclopedia typography. '
                'Another extraordinary paragraph demonstrates automatic hyphenation.',
          ),
        ],
      );
      const settings = ReaderSettings(justify: false);
      final layout = TextBlockLayout.measure(
        block: block,
        width: 210,
        pageHeight: 600,
        settings: settings,
      );
      final painter = TextBlockLayout.createPainter(block, settings, 210);
      final hyphens = TextBlockLayout.hyphenOffsets(painter, block, settings);
      painter.dispose();
      expect(hyphens, isNotEmpty);
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: RepaintBoundary(
                key: key,
                child: ColoredBox(
                  color: Colors.white,
                  child: SizedBox(
                    width: 210,
                    child: BlockSliceView(
                      block: block,
                      settings: settings,
                      pageHeight: 600,
                      slice: BlockSlice(
                        blockIndex: 0,
                        startCharOffset: 0,
                        endCharOffset: block.characterCount,
                        sourceTop: 0,
                        height: layout.height,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() async {
        final image =
            await (key.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
        try {
          final data = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          for (final offset in hyphens) {
            var darkPixels = 0;
            for (
              var y = (offset.dy - settings.fontSize).floor().clamp(
                0,
                image.height - 1,
              );
              y < offset.dy.ceil().clamp(0, image.height);
              y++
            ) {
              for (
                var x = offset.dx.ceil();
                x <
                    (offset.dx + settings.fontSize * .5).floor().clamp(
                      0,
                      image.width,
                    );
                x++
              ) {
                if (data.getUint8((y * image.width + x) * 4) < 128) {
                  darkPixels++;
                }
              }
            }
            expect(
              darkPixels,
              greaterThan(0),
              reason: 'A visible hyphen must follow the broken word at $offset',
            );
          }
          if (Platform.environment['READER_VISUAL_QA'] == '1') {
            final png = (await image.toByteData(
              format: ui.ImageByteFormat.png,
            ))!;
            await File('/tmp/epub-hyphens.png')
                .writeAsBytes(png.buffer.asUint8List());
          }
        } finally {
          image.dispose();
        }
      });
      expect(tester.takeException(), isNull);
    },
  );
}

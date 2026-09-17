import 'dart:async';

import 'package:eink_launcher/reader/models/content_block.dart';
import 'package:eink_launcher/reader/models/laid_out_page.dart';
import 'package:eink_launcher/reader/models/reader_settings.dart';
import 'package:eink_launcher/reader/services/epub_paginator_service.dart';
import 'package:eink_launcher/reader/services/text_word_selection.dart';
import 'package:eink_launcher/reader/widgets/block_slice_view.dart';
import 'package:eink_launcher/reader/widgets/tap_zone_layer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('selects whole wrapped words across discretionary hyphens', (
    tester,
  ) async {
    const block = ContentBlock(
      type: BlockType.paragraph,
      runs: [InlineRun(text: 'extra\u00adordinary hello')],
    );
    const settings = ReaderSettings(hyphenate: false, justify: false);
    final painter = TextBlockLayout.createPainter(block, settings, 170);
    addTearDown(painter.dispose);
    final boxes = painter.getBoxesForSelection(
      const TextSelection(baseOffset: 0, extentOffset: 14),
    );
    for (final box in boxes) {
      expect(wordAtOffset(painter, box.toRect().center)?.word, 'extraordinary');
    }
    expect(wordAtOffset(painter, const Offset(1000, 1000)), isNull);
  });

  testWidgets('long press on a clipped slice selects without turning pages', (
    tester,
  ) async {
    const block = ContentBlock(
      type: BlockType.paragraph,
      runs: [InlineRun(text: 'first\nsecond')],
    );
    const settings = ReaderSettings(hyphenate: false, justify: false);
    final painter = TextBlockLayout.createPainter(block, settings, 240);
    final box = painter
        .getBoxesForSelection(
          const TextSelection(baseOffset: 6, extentOffset: 12),
        )
        .single
        .toRect();
    painter.dispose();
    var turns = 0;
    String? selected;
    final pending = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 240,
              height: box.height,
              child: TapZoneLayer(
                onPrevious: () => turns++,
                onMenu: () => turns++,
                onNext: () => turns++,
                child: BlockSliceView(
                  block: block,
                  settings: settings,
                  pageHeight: 400,
                  slice: BlockSlice(
                    blockIndex: 0,
                    startCharOffset: 6,
                    endCharOffset: 12,
                    sourceTop: box.top,
                    height: box.height,
                  ),
                  onDefineWord: (word) {
                    selected = word;
                    return pending.future;
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.longPressAt(Offset(box.center.dx, box.height / 2));
    await tester.pump();
    expect(selected, isNull);
    await tester.tap(find.byKey(const Key('selection-dictionary')));
    await tester.pump();
    expect(selected, 'second');
    expect(turns, 0);
    pending.complete();
    await tester.pump();
    await tester.tapAt(Offset(box.center.dx, box.height / 2));
    expect(turns, 1);
    expect(tester.takeException(), isNull);
  });
}

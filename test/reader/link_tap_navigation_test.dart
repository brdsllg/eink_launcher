import 'package:eink_launcher/reader/models/content_block.dart';
import 'package:eink_launcher/reader/models/laid_out_page.dart';
import 'package:eink_launcher/reader/models/reader_settings.dart';
import 'package:eink_launcher/reader/services/epub_paginator_service.dart';
import 'package:eink_launcher/reader/widgets/block_slice_view.dart';
import 'package:eink_launcher/reader/widgets/tap_zone_layer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Non-link text in a paragraph with a link still opens the menu', (
    tester,
  ) async {
    const block = ContentBlock(
      type: BlockType.paragraph,
      runs: [
        InlineRun(
          text: 'This ordinary paragraph contains many words before its ',
        ),
        InlineRun(text: 'link', href: '#note'),
      ],
    );
    const settings = ReaderSettings(hyphenate: false, justify: false);
    final layout = TextBlockLayout.measure(
      block: block,
      width: 600,
      pageHeight: 400,
      settings: settings,
    );
    var menuTaps = 0;
    var linkTaps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 600,
              height: 400,
              child: TapZoneLayer(
                onPrevious: () {},
                onNext: () {},
                onMenu: () => menuTaps++,
                child: Column(
                  children: [
                    BlockSliceView(
                      key: const Key('paragraph'),
                      block: block,
                      slice: BlockSlice(
                        blockIndex: 0,
                        startCharOffset: 0,
                        endCharOffset: block.plainText.length,
                        sourceTop: 0,
                        height: layout.height,
                      ),
                      settings: settings,
                      pageHeight: 400,
                      onOpenLink: (_) async => linkTaps++,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final origin = tester.getTopLeft(find.byKey(const Key('paragraph')));
    const local = Offset(300, 10);
    expect(TextBlockLayout.linkAtOffset(block, settings, 600, local), isNull);
    await tester.tapAt(origin + local);
    await tester.pump();
    expect(linkTaps, 0);
    expect(menuTaps, 1);
    final painter = TextBlockLayout.createPainter(block, settings, 600);
    final boxes = painter.getBoxesForSelection(
      TextSelection(
        baseOffset: block.runs.first.text.length,
        extentOffset: block.plainText.length,
      ),
    );
    final linkPosition = boxes.first.toRect().center;
    expect(
      TextBlockLayout.linkAtOffset(block, settings, 600, linkPosition),
      '#note',
    );
    painter.dispose();
    await tester.tapAt(origin + linkPosition);
    await tester.pump();
    expect(linkTaps, 1);
    expect(menuTaps, 1, reason: 'A real link must not also open the menu');
  });
}

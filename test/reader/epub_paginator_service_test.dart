import 'package:eink_launcher/reader/models/content_block.dart';
import 'package:eink_launcher/reader/models/reader_settings.dart';
import 'package:eink_launcher/reader/services/epub_paginator_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const paginator = EpubPaginatorService();

  test('packs short blocks and keeps logical positions stable', () {
    final blocks = [
      const ContentBlock(
        type: BlockType.heading1,
        runs: [InlineRun(text: 'Chapter')],
      ),
      const ContentBlock(
        type: BlockType.paragraph,
        runs: [InlineRun(text: 'A short paragraph.')],
      ),
    ];

    final pages = paginator.paginateSpine(
      spineIndex: 2,
      blocks: blocks,
      contentSize: const Size(500, 500),
      settings: const ReaderSettings(),
    );

    expect(pages, hasLength(1));
    expect(pages.single.slices, hasLength(2));
    expect(pages.single.start.spineIndex, 2);
    expect(pages.single.start.blockIndex, 0);
    expect(pages.single.end.blockIndex, 1);
    expect(pages.single.end.charOffset, blocks[1].characterCount);
  });

  test('splits a paragraph only at complete line boundaries', () {
    const text =
        'one two three four five six seven eight nine ten eleven twelve '
        'thirteen fourteen fifteen sixteen seventeen eighteen nineteen twenty';
    final pages = paginator.paginateSpine(
      spineIndex: 0,
      blocks: const [
        ContentBlock(
          type: BlockType.paragraph,
          runs: [InlineRun(text: text)],
        ),
      ],
      contentSize: const Size(120, 80),
      settings: const ReaderSettings(fontSizeStep: 0, lineHeight: 1.2),
    );

    expect(pages.length, greaterThan(1));
    for (var i = 0; i < pages.length - 1; i++) {
      final current = pages[i].slices.single;
      final next = pages[i + 1].slices.single;
      expect(current.endCharOffset, next.startCharOffset);
      expect(current.endCharOffset, inInclusiveRange(1, text.length - 1));
    }
    expect(pages.last.end.charOffset, text.length);
  });

  test('avoids leaving a single orphan line on the final page', () {
    const block = ContentBlock(
      type: BlockType.paragraph,
      runs: [
        InlineRun(
          text:
              'alpha beta gamma delta epsilon zeta eta theta iota kappa '
              'lambda mu nu xi omicron pi rho sigma tau upsilon phi chi psi omega',
        ),
      ],
    );
    final pages = paginator.paginateSpine(
      spineIndex: 0,
      blocks: const [block],
      contentSize: const Size(145, 92),
      settings: const ReaderSettings(fontSizeStep: 0, lineHeight: 1.2),
    );

    expect(pages.length, greaterThan(1));
    final lastSlice = pages.last.slices.single;
    final layout = TextBlockLayout.measure(
      block: block,
      width: 145,
      pageHeight: 92,
      settings: const ReaderSettings(fontSizeStep: 0, lineHeight: 1.2),
    );
    final finalLines = layout.lines
        .where((line) => line.startCharOffset >= lastSlice.startCharOffset)
        .length;
    expect(finalLines, greaterThanOrEqualTo(2));
  });

  test('publisher alignment is ignored when its setting is disabled', () {
    const block = ContentBlock(
      type: BlockType.heading2,
      alignment: BlockAlignment.center,
      runs: [InlineRun(text: 'Publisher heading')],
    );

    expect(
      TextBlockLayout.alignmentFor(
        block,
        const ReaderSettings(honorPublisherCss: false, justify: true),
      ),
      TextAlign.start,
    );
    expect(
      TextBlockLayout.alignmentFor(block, const ReaderSettings()),
      TextAlign.center,
    );
  });
}

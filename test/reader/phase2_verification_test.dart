import 'package:eink_launcher/reader/models/content_block.dart';
import 'package:eink_launcher/reader/models/laid_out_page.dart';
import 'package:eink_launcher/reader/models/reader_settings.dart';
import 'package:eink_launcher/reader/services/epub_paginator_service.dart';
import 'package:eink_launcher/reader/services/html_block_parser.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bundled Latin and Hebrew font assets load and lay out text', () async {
    const fonts = {
      'Literata': 'assets/fonts/Literata-Regular.ttf',
      'EB Garamond': 'assets/fonts/EBGaramond-Regular.ttf',
      'Inter': 'assets/fonts/Inter-Regular.ttf',
      'Frank Ruhl Libre': 'assets/fonts/FrankRuhlLibre-Regular.ttf',
      'Noto Serif Hebrew': 'assets/fonts/NotoSerifHebrew-Regular.ttf',
      'Heebo': 'assets/fonts/Heebo-Regular.ttf',
    };

    for (final entry in fonts.entries) {
      final bytes = await rootBundle.load(entry.value);
      expect(bytes.lengthInBytes, greaterThan(10000), reason: entry.key);
      final rtl =
          entry.key == 'Frank Ruhl Libre' ||
          entry.key == 'Noto Serif Hebrew' ||
          entry.key == 'Heebo';
      final painter = TextPainter(
        text: TextSpan(
          text: rtl ? 'שָׁלוֹם עוֹלָם' : 'Readable typography',
          style: TextStyle(fontFamily: entry.key, fontSize: 24),
        ),
        textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
      )..layout(maxWidth: 300);
      expect(painter.width, greaterThan(0), reason: entry.key);
      expect(painter.height, greaterThan(0), reason: entry.key);
    }
  });

  test('bilingual EPUB blocks paginate exactly in both orientations', () {
    final repeatedEnglish = List.filled(
      8,
      'English typography should wrap cleanly without clipping any lines. ',
    ).join();
    final repeatedHebrew = List.filled(
      8,
      'שָׁלוֹם עוֹלָם, זֶהוּ טֶקְסְט עִבְרִי לִבְדִיקַת עִמּוּד. ',
    ).join();
    final blocks = HtmlBlockParser.parseSync('''
      <h1>English and עברית</h1>
      <p id="english">$repeatedEnglish</p>
      <p id="hebrew">$repeatedHebrew</p>
      <p id="mixed-ltr">English first, ואז עברית בתוך אותה פסקה.</p>
      <p id="mixed-rtl">עברית תחילה, followed by English in one paragraph.</p>
    ''');

    expect(blocks[1].direction, BlockTextDirection.ltr);
    expect(blocks[2].direction, BlockTextDirection.rtl);
    expect(blocks[3].direction, BlockTextDirection.ltr);
    expect(blocks[4].direction, BlockTextDirection.rtl);

    const settings = ReaderSettings(
      fontSizeStep: 2,
      lineHeight: 1.4,
      hyphenate: true,
    );
    const paginator = EpubPaginatorService();
    final stopwatch = Stopwatch()..start();
    final portrait = paginator.paginateSpine(
      spineIndex: 0,
      blocks: blocks,
      contentSize: const Size(240, 340),
      settings: settings,
    );
    final landscape = paginator.paginateSpine(
      spineIndex: 0,
      blocks: blocks,
      contentSize: const Size(420, 190),
      settings: settings,
    );
    stopwatch.stop();

    expect(portrait, isNotEmpty);
    expect(landscape, isNotEmpty);
    expect(
      portrait
          .expand((page) => page.slices)
          .map((slice) => slice.endCharOffset)
          .toList(),
      isNot(
        landscape
            .expand((page) => page.slices)
            .map((slice) => slice.endCharOffset)
            .toList(),
      ),
    );
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));
    _expectExactCoverage(
      pages: portrait,
      blocks: blocks,
      pageHeight: 340,
      pageWidth: 240,
      settings: settings,
    );
    _expectExactCoverage(
      pages: landscape,
      blocks: blocks,
      pageHeight: 190,
      pageWidth: 420,
      settings: settings,
    );
  });
}

void _expectExactCoverage({
  required List<LaidOutPage> pages,
  required List<ContentBlock> blocks,
  required double pageHeight,
  required double pageWidth,
  required ReaderSettings settings,
}) {
  final slicesByBlock = <int, List<BlockSlice>>{};
  for (final page in pages) {
    final usedHeight = page.slices.fold<double>(
      0,
      (height, slice) => height + slice.height,
    );
    expect(usedHeight, lessThanOrEqualTo(pageHeight + 0.01));
    expect(page.start.blockIndex, page.slices.first.blockIndex);
    expect(page.start.charOffset, page.slices.first.startCharOffset);
    expect(page.end.blockIndex, page.slices.last.blockIndex);
    expect(page.end.charOffset, page.slices.last.endCharOffset);
    for (final slice in page.slices) {
      expect(slice.height, greaterThan(0));
      slicesByBlock.putIfAbsent(slice.blockIndex, () => []).add(slice);
    }
  }

  for (var blockIndex = 0; blockIndex < blocks.length; blockIndex++) {
    final block = blocks[blockIndex];
    final slices = slicesByBlock[blockIndex]!;
    expect(slices.first.startCharOffset, 0);
    expect(slices.last.endCharOffset, block.characterCount);
    for (var index = 1; index < slices.length; index++) {
      expect(slices[index - 1].endCharOffset, slices[index].startCharOffset);
    }

    final layout = TextBlockLayout.measure(
      block: block,
      width: pageWidth,
      pageHeight: pageHeight,
      settings: settings,
    );
    final validStarts = layout.lines
        .map((line) => line.startCharOffset)
        .toSet();
    final validEnds = layout.lines.map((line) => line.endCharOffset).toSet();
    for (final slice in slices) {
      expect(validStarts, contains(slice.startCharOffset));
      expect(validEnds, contains(slice.endCharOffset));
    }
  }
}

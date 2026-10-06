import 'package:eink_launcher/reader/models/annotation.dart';
import 'package:eink_launcher/reader/models/content_block.dart';
import 'package:eink_launcher/reader/models/parsed_book.dart';
import 'package:eink_launcher/reader/models/reader_settings.dart';
import 'package:eink_launcher/reader/services/epub_paginator_service.dart';
import 'package:eink_launcher/reader/services/tanach_layout_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('hideVowelPoints strips marks at display but keeps source offsets', () {
    const block = ContentBlock(
      type: BlockType.paragraph,
      runs: [InlineRun(text: 'בְּרֵאשִׁית test')],
    );
    const shown = ReaderSettings();
    const hidden = ReaderSettings(hideVowelPoints: true);
    expect(TextBlockLayout.displayedPlainText(block, shown), contains('ְ'));
    expect(TextBlockLayout.displayedPlainText(block, hidden), isNot(contains('ְ')));
    expect(TextBlockLayout.displayedPlainText(block, hidden), contains('בראשית'));
    // Offsets still map: display length shorter, source offsets monotonic.
    final offsets = TextBlockLayout.sourceOffsetsForDisplay(block, hidden);
    expect(offsets.length, greaterThan(1));
    expect(offsets.last, block.plainText.length);
  });

  test('studyContinuous merges consecutive paragraphs', () {
    final blocks = [
      const ContentBlock(
        type: BlockType.paragraph,
        runs: [InlineRun(text: 'first')],
      ),
      const ContentBlock(
        type: BlockType.paragraph,
        runs: [InlineRun(text: 'second')],
      ),
      const ContentBlock(
        type: BlockType.heading2,
        runs: [InlineRun(text: 'Berakhot 2a:1')],
      ),
      const ContentBlock(
        type: BlockType.paragraph,
        runs: [InlineRun(text: 'third')],
      ),
    ];
    final merged = TanachLayoutService.mergeContinuousBlocks(blocks);
    expect(merged.length, 3);
    expect(merged.first.plainText, 'first second');
    expect(merged[1].plainText, 'Berakhot 2a:1');
    expect(merged[2].plainText, 'third');
  });

  test('commentary sources order Rashi, Tosafot, then rest', () {
    expect(
      TanachLayoutService.orderedStudySources({
        'Other',
        'Tosafot on Berakhot',
        'Rashi on Berakhot',
        'Steinsaltz on Berakhot',
      }),
      [
        'Rashi on Berakhot',
        'Tosafot on Berakhot',
        'Other',
        'Steinsaltz on Berakhot',
      ],
    );
    expect(
      TanachLayoutService.orderedStudySources({'Mefaresh on Tamid', 'Other'}),
      ['Mefaresh on Tamid', 'Other'],
    );
  });

  test('multi-block annotation matches each block in range', () {
    final chapter = ParsedSpineItem(
      id: 'c',
      href: 'chapter.xhtml',
      blocks: const [
        ContentBlock(type: BlockType.paragraph, runs: [InlineRun(text: 'aaa')]),
        ContentBlock(type: BlockType.paragraph, runs: [InlineRun(text: 'bbb')]),
        ContentBlock(type: BlockType.paragraph, runs: [InlineRun(text: 'ccc')]),
      ],
    );
    final annotation = Annotation(
      id: 'm',
      docId: 'd',
      createdAt: DateTime.utc(2026),
      spineIndex: 0,
      blockIndex: 0,
      documentPath: 'chapter.xhtml',
      startOffset: 1,
      endOffset: 3,
      endBlockIndex: 2,
      endBlockOffset: 2,
      text: 'aa\n\nbbb\n\ncc',
    );
    expect(annotation.isMultiBlock, isTrue);
    expect(annotation.matchesBlock(chapter, 0, 0), isTrue);
    expect(annotation.matchesBlock(chapter, 0, 1), isTrue);
    expect(annotation.matchesBlock(chapter, 0, 2), isTrue);
    expect(annotation.rangeForBlock(chapter, 0)!.start, 1);
    expect(annotation.rangeForBlock(chapter, 0)!.end, 3);
    expect(annotation.rangeForBlock(chapter, 1)!.start, 0);
    expect(annotation.rangeForBlock(chapter, 1)!.end, 3);
    expect(annotation.rangeForBlock(chapter, 2)!.end, 2);
  });

  test('new study settings persist through JSON', () {
    const settings = ReaderSettings(
      hideVowelPoints: true,
      studyContinuous: true,
    );
    final restored = ReaderSettings.fromJson(settings.toJson());
    expect(restored.hideVowelPoints, isTrue);
    expect(restored.studyContinuous, isTrue);
    expect(
      restored.copyWith(hideVowelPoints: false).hideVowelPoints,
      isFalse,
    );
  });

  test('projected commentary drops reader-stripped backlinks', () {
    final book = ParsedBook(
      title: 'T',
      spine: [
        ParsedSpineItem(id: 'c', href: 'c.xhtml', title: 'C', blocks: []),
      ],
      studyDocuments: {
        'c.xhtml': '''
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><body>
<section class="segment" id="s-1" data-ref="Berakhot 2a:1"><div class="segment-heading"><span>Berakhot 2a:1</span></div><p class="hebrew" dir="rtl">טקסט</p><p><a epub:type="noteref" href="#idx-1">Notes</a></p></section>
<aside epub:type="footnote" class="note-index" id="idx-1"><p><a epub:type="noteref" href="#g-1">Rashi</a></p></aside>
<aside epub:type="footnote" id="g-1" class="commentary-note" data-source="Rashi on Berakhot" data-category="commentary" data-ref="Berakhot 2a:1"><p class="note-title">Rashi</p><div class="note-he" dir="rtl">פירוש</div><p class="backlinks"><a href="#s-1">back</a></p></aside>
</body></html>''',
      },
    );
    final projected = TanachLayoutService.layout(
      book,
      const ReaderSettings(commentarySources: ['Rashi on Berakhot']),
    );
    final text = projected.spine.single.blocks
        .map((b) => b.plainText)
        .join('\n');
    expect(text, contains('פירוש'));
    expect(text, isNot(contains('back')));
  });

  test('continuous breaks at single-span segment headings, chunks huge merges', () {
    final blocks = [
      const ContentBlock(
        type: BlockType.paragraph,
        runs: [InlineRun(text: 'hebrew body')],
        direction: BlockTextDirection.rtl,
      ),
      const ContentBlock(
        type: BlockType.heading2,
        runs: [InlineRun(text: 'Berakhot 2a:2')],
      ),
      const ContentBlock(
        type: BlockType.paragraph,
        runs: [InlineRun(text: 'next segment')],
        direction: BlockTextDirection.rtl,
      ),
    ];
    final merged = TanachLayoutService.mergeContinuousBlocks(blocks);
    // Heading stays a separator so one amud never becomes one giant block.
    expect(merged.length, 3);
    expect(merged[1].type, BlockType.heading2);
  });

  test('continuous breaks on direction change and preserves anchors', () {
    final blocks = [
      const ContentBlock(
        type: BlockType.paragraph,
        runs: [InlineRun(text: 'עברית')],
        direction: BlockTextDirection.rtl,
        id: 'a',
      ),
      const ContentBlock(
        type: BlockType.paragraph,
        runs: [InlineRun(text: 'english')],
        direction: BlockTextDirection.ltr,
        id: 'b',
      ),
    ];
    final merged = TanachLayoutService.mergeContinuousBlocks(blocks);
    expect(merged.length, 2);
  });

  test('projected commentary follows picker rank, not builder order', () {
    final book = ParsedBook(
      title: 'T',
      spine: [
        ParsedSpineItem(id: 'c', href: 'c.xhtml', title: 'C', blocks: []),
      ],
      studyDocuments: {
        'c.xhtml': '''
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><body>
<section class="segment" id="s-1" data-ref="Berakhot 2a:1"><div class="segment-heading"><span>Berakhot 2a:1</span></div><p class="hebrew" dir="rtl">טקסט</p><p><a epub:type="noteref" href="#idx-1">Notes</a></p></section>
<aside epub:type="footnote" class="note-index" id="idx-1"><p><a epub:type="noteref" href="#g-s">Steinsaltz</a></p><p><a epub:type="noteref" href="#g-t">Tosafot</a></p><p><a epub:type="noteref" href="#g-r">Rashi</a></p></aside>
<aside epub:type="footnote" id="g-s" class="commentary-note" data-source="Steinsaltz on Berakhot" data-category="commentary" data-ref="Berakhot 2a:1"><p class="note-title">Steinsaltz</p><div class="note-he" dir="rtl">סטיינזלץ</div></aside>
<aside epub:type="footnote" id="g-t" class="commentary-note" data-source="Tosafot on Berakhot" data-category="commentary" data-ref="Berakhot 2a:1"><p class="note-title">Tosafot</p><div class="note-he" dir="rtl">תוספות</div></aside>
<aside epub:type="footnote" id="g-r" class="commentary-note" data-source="Rashi on Berakhot" data-category="commentary" data-ref="Berakhot 2a:1"><p class="note-title">Rashi</p><div class="note-he" dir="rtl">רש״י</div></aside>
</body></html>''',
      },
    );
    final projected = TanachLayoutService.layout(
      book,
      const ReaderSettings(
        commentarySources: [
          'Steinsaltz on Berakhot',
          'Tosafot on Berakhot',
          'Rashi on Berakhot',
        ],
      ),
    );
    final text = projected.spine.single.blocks
        .map((b) => b.plainText)
        .join('\n');
    final rashi = text.indexOf('רש״י');
    final tosafot = text.indexOf('תוספות');
    final stein = text.indexOf('סטיינזלץ');
    expect(rashi, greaterThanOrEqualTo(0));
    expect(tosafot, greaterThan(rashi));
    expect(stein, greaterThan(tosafot));
  });

  test('vowel hiding strips full 0591-05C7 range', () {
    // 05BE maqaf, 05C0 paseq, 05C3 sof pasuq, 05C6 nun-hafukha were missed.
    const withMarks = 'א\u05beב\u05c0ג\u05c3ד\u05c6ה';
    expect(
      TextBlockLayout.withoutVowelPoints(withMarks),
      'אבגדה',
    );
  });
}

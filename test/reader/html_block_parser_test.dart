import 'package:eink_launcher/reader/models/content_block.dart';
import 'package:eink_launcher/reader/services/html_block_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const parser = HtmlBlockParser();

  test('walks semantic blocks, inline styles, lists, and images', () async {
    final blocks = await parser.parse('''
      <section>
        <h1 id="top">A heading</h1>
        <p>Hello <strong>bold <em>and italic</em></strong>.</p>
        <blockquote dir="rtl">שלום עולם</blockquote>
        <ol>
          <li>First</li>
          <li>Second<ul><li>Nested</li></ul></li>
        </ol>
        <p id="picture"><img src="images/map.png" alt="Map"></p>
      </section>
    ''', resourceBasePath: 'OPS');

    expect(blocks.map((block) => block.type), [
      BlockType.heading1,
      BlockType.paragraph,
      BlockType.blockquote,
      BlockType.listItem,
      BlockType.listItem,
      BlockType.listItem,
      BlockType.image,
    ]);
    expect(blocks[0].id, 'top');
    expect(blocks[1].plainText, 'Hello bold and italic.');
    expect(blocks[1].runs.any((run) => run.bold), isTrue);
    expect(
      blocks[1].runs.singleWhere((run) => run.text == 'and italic').italic,
      isTrue,
    );
    expect(blocks[2].direction, BlockTextDirection.rtl);
    expect(blocks[3].orderedList, isTrue);
    expect(blocks[5].nestingLevel, 1);
    expect(blocks[6].resourcePath, 'OPS/images/map.png');
    expect(blocks[6].alternateText, 'Map');
    expect(blocks[6].id, 'picture');
  });

  test(
    'honors only supported publisher style semantics when enabled',
    () async {
      const source = '''
      <p style="font-family: fantasy; font-size: 80px; color: red;
                text-align: center">
        <span style="font-weight: 700; font-style: italic">Styled</span>
      </p>
    ''';
      final enabled = await parser.parse(source);
      final disabled = await parser.parse(source, honorPublisherCss: false);

      expect(enabled.single.alignment, BlockAlignment.center);
      expect(enabled.single.runs.single.bold, isTrue);
      expect(enabled.single.runs.single.italic, isTrue);
      expect(disabled.single.alignment, BlockAlignment.start);
      expect(disabled.single.runs.single.bold, isFalse);
      expect(disabled.single.runs.single.italic, isFalse);
    },
  );

  test('inherits an explicit direction from an ancestor', () async {
    final blocks = await parser.parse(
      '<section dir="rtl"><p>123 — neutral opening</p></section>',
    );
    expect(blocks.single.direction, BlockTextDirection.rtl);
  });

  test(
    'preserves revision-5 Tanach layout semantics and the 1.1 Hebrew scale',
    () {
      final blocks = HtmlBlockParser.parseSync('''
      <section class="verse" id="v-ruth-3-1">
        <h2 class="verse-heading" dir="ltr">
          <span lang="en" dir="ltr">Verse 1</span>
          <span lang="he" dir="rtl">פסוק א׳</span>
        </h2>
        <p class="hebrew" dir="rtl">בְּרֵאשִׁית</p>
        <div class="translation" dir="ltr">In the beginning</div>
        <aside class="commentary-note">
          <p class="note-title">Ibn Ezra on Ruth 3:1</p>
          <div class="note-he" dir="rtl">
            <div class="comment-segment"><div class="note-paragraph">אחד</div></div>
            <div class="comment-segment"><div class="note-paragraph">שנים</div></div>
          </div>
        </aside>
      </section>
    ''');

      final heading = blocks.first;
      expect(heading.plainText, 'Verse 1 פסוק א׳');
      expect(heading.hasSplitLayout, isTrue);
      expect(heading.direction, BlockTextDirection.ltr);
      expect(heading.trailingDirection, BlockTextDirection.rtl);
      expect(heading.fontSizeMultiplier, 1.0);
      expect(heading.forceBold, isTrue);

      final hebrew = blocks.firstWhere(
        (block) => block.plainText == 'בְּרֵאשִׁית',
      );
      expect(hebrew.alignment, BlockAlignment.right);
      expect(hebrew.lineHeight, 1.7);
      expect(hebrew.textIndentEm, 0);
      expect(hebrew.fontSizeMultiplier, 1.1);
      final english = blocks.firstWhere(
        (block) => block.plainText == 'In the beginning',
      );
      expect(english.alignment, BlockAlignment.left);
      expect(english.lineHeight, 1.55);
      expect(english.fontSizeMultiplier, isNull);
      final title = blocks.firstWhere(
        (block) => block.plainText == 'Ibn Ezra on Ruth 3:1',
      );
      expect(title.fontSizeMultiplier, 0.9);
      expect(title.forceBold, isTrue);
      final hebrewNoteBlocks = blocks
          .where((block) => {'אחד', 'שנים'}.contains(block.plainText))
          .toList();
      expect(hebrewNoteBlocks, hasLength(2));
      expect(
        hebrewNoteBlocks.every((block) => block.fontSizeMultiplier == 1.1),
        isTrue,
      );
    },
  );

  test('parses a complete XHTML document on a background isolate', () async {
    final blocks = await parser.parse('''
      <?xml version="1.0" encoding="utf-8"?>
      <!DOCTYPE html>
      <html xmlns="http://www.w3.org/1999/xhtml">
        <head><title>Ignored title</title><style>p { color: red; }</style></head>
        <body><h2>Chapter</h2><p>Body text.</p></body>
      </html>
    ''');

    expect(blocks.map((block) => block.type), [
      BlockType.heading2,
      BlockType.paragraph,
    ]);
    expect(blocks.map((block) => block.plainText), ['Chapter', 'Body text.']);
  });

  test('Talmud segment headings share the compact bold study style', () {
    final blocks = HtmlBlockParser.parseSync('''
      <section class="segment" id="s-berakhot-2a-1" data-ref="Berakhot 2a:1">
        <div class="segment-heading"><span dir="ltr">Berakhot 2a:1</span></div>
        <p class="hebrew" dir="rtl">מאימתי</p>
        <p class="translation" dir="ltr">From when</p>
        <aside class="commentary-note">
          <p class="note-title">Rashi 2a:1</p>
          <div class="note-he" dir="rtl">
            <div class="comment-segment"><div class="note-paragraph">פירוש</div></div>
          </div>
        </aside>
      </section>
    ''');

    final heading = blocks.firstWhere(
      (block) => block.plainText == 'Berakhot 2a:1',
    );
    expect(heading.fontSizeMultiplier, 1.0);
    expect(heading.forceBold, isTrue);
    final hebrew = blocks.firstWhere((block) => block.plainText == 'מאימתי');
    expect(hebrew.fontSizeMultiplier, 1.1);
    expect(hebrew.lineHeight, 1.7);
    final comment = blocks.firstWhere((block) => block.plainText == 'פירוש');
    expect(comment.fontSizeMultiplier, 1.1);
    expect(comment.spacingAfterEm, 0.6);
  });
}

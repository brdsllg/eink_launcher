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
}

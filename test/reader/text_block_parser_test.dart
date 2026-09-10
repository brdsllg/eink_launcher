import 'dart:convert';
import 'dart:typed_data';

import 'package:eink_launcher/reader/models/content_block.dart';
import 'package:eink_launcher/reader/models/doc_ref.dart';
import 'package:eink_launcher/reader/services/text_block_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const parser = TextBlockParser();

  test('splits plain text on blank lines and detects bidi direction', () async {
    final book = await parser.parseBytes(
      Uint8List.fromList(utf8.encode('First line\ncontinues.\n\nשלום עולם')),
      format: DocFormat.txt,
      title: 'Notes',
    );

    expect(book.title, 'Notes');
    expect(book.spine.single.blocks, hasLength(2));
    expect(book.spine.single.blocks.first.plainText, 'First line\ncontinues.');
    expect(book.spine.single.blocks.last.direction, BlockTextDirection.rtl);
  });

  test(
    'unwraps fixed-width prose, preserving short endings and indented starts',
    () {
      final long = 'word ' * 14;
      final source =
          '$long\n$long\n$long\nA short ending.\n$long\n  Indented paragraph.';
      final book = TextBlockParser.parseBytesSync(
        Uint8List.fromList(utf8.encode(source)),
        format: DocFormat.txt,
        title: 'Prose',
      );
      final blocks = book.spine.single.blocks;
      expect(blocks, hasLength(3));
      expect(
        blocks.first.plainText,
        '${long.trim()} ${long.trim()} ${long.trim()} A short ending.',
      );
      expect(blocks.last.plainText, 'Indented paragraph.');
    },
  );

  test(
    'preserves intentional lines in verse and recognizes tab paragraphs',
    () {
      final book = TextBlockParser.parseBytesSync(
        Uint8List.fromList(
          utf8.encode('Roses are red\nViolets are blue\n\tA new paragraph'),
        ),
        format: DocFormat.txt,
        title: 'Verse',
      );
      expect(book.spine.single.blocks.map((b) => b.plainText), [
        'Roses are red\nViolets are blue',
        'A new paragraph',
      ]);
    },
  );

  test('decodes UTF-16 BOM and Windows-1255 Hebrew', () {
    final utf16 = Uint8List.fromList([
      0xff,
      0xfe,
      ...'Hello'.codeUnits.expand((unit) => [unit & 0xff, unit >> 8]),
    ]);
    expect(TextBlockParser.decodeText(utf16), 'Hello');
    expect(
      TextBlockParser.decodeText(Uint8List.fromList([0xf9, 0xec, 0xe5, 0xed])),
      'שלום',
    );
  });

  test('converts Markdown into semantic blocks and heading TOC', () async {
    final book = await parser.parseBytes(
      Uint8List.fromList(utf8.encode('# Heading\n\nText with **bold**.')),
      format: DocFormat.markdown,
      title: 'Markdown',
    );

    expect(book.spine.single.blocks.first.type, BlockType.heading1);
    expect(book.spine.single.blocks.last.runs.any((run) => run.bold), isTrue);
    expect(book.tableOfContents.single.title, 'Heading');
    expect(book.tableOfContents.single.position, isNotNull);
  });
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:eink_launcher/reader/models/content_block.dart';
import 'package:eink_launcher/reader/models/reading_position.dart';
import 'package:eink_launcher/reader/services/epub_parser_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const parser = EpubParserService();

  test(
    'extracts EPUB 3 metadata, spine, resources, and nested nav TOC',
    () async {
      final book = await parser.parseBytes(_buildEpub3Fixture());

      expect(book.title, 'Bilingual Fixture');
      expect(book.author, 'Test Author');
      expect(book.language, 'en');
      expect(book.spine, hasLength(2));
      expect(book.spine.first.href, 'OEBPS/chapter1.xhtml');
      expect(book.spine.first.blocks.first.type, BlockType.heading1);
      expect(book.spine.first.blocks[1].id, 'middle');
      expect(book.spine.first.blocks[2].direction, BlockTextDirection.rtl);
      expect(book.resources['OEBPS/images/pixel.png'], [0, 1, 2, 3]);
      expect(book.characterCount, greaterThan(0));
      expect(book.cumulativeCharacterCounts, hasLength(2));

      expect(book.tableOfContents, hasLength(1));
      final chapter = book.tableOfContents.single;
      expect(chapter.title, 'Chapter One');
      expect(
        chapter.position,
        const TextReadingPosition(spineIndex: 0, blockIndex: 1, charOffset: 0),
      );
      expect(chapter.children.single.title, 'Chapter Two');
      expect(chapter.children.single.level, 1);
    },
  );

  test('reports a malformed container as a format error', () async {
    final archive = Archive()
      ..add(ArchiveFile.string('META-INF/container.xml', '<container>'));
    final bytes = Uint8List.fromList(ZipEncoder().encode(archive));
    await expectLater(
      parser.parseBytes(bytes),
      throwsA(isA<FormatException>()),
    );
  });
}

Uint8List _buildEpub3Fixture() {
  final archive = Archive()
    ..add(
      ArchiveFile.noCompress(
        'mimetype',
        'application/epub+zip'.length,
        utf8.encode('application/epub+zip'),
      ),
    )
    ..add(
      ArchiveFile.string('META-INF/container.xml', '''
      <?xml version="1.0"?>
      <container xmlns="urn:oasis:names:tc:opendocument:xmlns:container"
                 version="1.0">
        <rootfiles>
          <rootfile full-path="OEBPS/content.opf"
                    media-type="application/oebps-package+xml"/>
        </rootfiles>
      </container>
    '''),
    )
    ..add(
      ArchiveFile.string('OEBPS/content.opf', '''
      <?xml version="1.0" encoding="utf-8"?>
      <package xmlns="http://www.idpf.org/2007/opf" version="3.0">
        <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
          <dc:title>Bilingual Fixture</dc:title>
          <dc:creator>Test Author</dc:creator>
          <dc:language>en</dc:language>
        </metadata>
        <manifest>
          <item id="c1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
          <item id="c2" href="text/chapter2.xhtml" media-type="application/xhtml+xml"/>
          <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
          <item id="pixel" href="images/pixel.png" media-type="image/png"/>
        </manifest>
        <spine><itemref idref="c1"/><itemref idref="c2"/></spine>
      </package>
    '''),
    )
    ..add(
      ArchiveFile.string('OEBPS/chapter1.xhtml', '''
      <html xmlns="http://www.w3.org/1999/xhtml"><body>
        <h1>First Chapter</h1>
        <p id="middle">An English paragraph.</p>
        <p>שלום עולם</p>
        <p><img src="images/pixel.png" alt="Pixel"/></p>
      </body></html>
    '''),
    )
    ..add(
      ArchiveFile.string('OEBPS/text/chapter2.xhtml', '''
      <html xmlns="http://www.w3.org/1999/xhtml"><body>
        <h1 id="start">Second Chapter</h1><p>More text.</p>
      </body></html>
    '''),
    )
    ..add(
      ArchiveFile.string('OEBPS/nav.xhtml', '''
      <html xmlns="http://www.w3.org/1999/xhtml"
            xmlns:epub="http://www.idpf.org/2007/ops"><body>
        <nav epub:type="toc"><ol>
          <li><a href="chapter1.xhtml#middle">Chapter One</a><ol>
            <li><a href="text/chapter2.xhtml#start">Chapter Two</a></li>
          </ol></li>
        </ol></nav>
      </body></html>
    '''),
    )
    ..add(ArchiveFile.bytes('OEBPS/images/pixel.png', [0, 1, 2, 3]));
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

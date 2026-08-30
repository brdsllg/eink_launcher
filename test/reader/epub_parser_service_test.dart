import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:eink_launcher/reader/models/content_block.dart';
import 'package:eink_launcher/reader/models/reader_exception.dart';
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

  // See https://www.w3.org/TR/epub-33/#sec-container-metainf-encryption.xml.
  // A publisher font obfuscated with the idpf/Adobe algorithms is not DRM and
  // must not stop the book from opening; any other encrypted spine resource
  // is genuine DRM this reader cannot decode and must be reported clearly
  // rather than parsed into garbled text.
  group('META-INF/encryption.xml', () {
    test(
      'recognizes Adobe font obfuscation and percent-encoded root paths',
      () async {
        final book = await parser.parseBytes(
          _buildEpubFixtureWithEncryption(
            encryptionXml: _encryptionEntry(
              'OEBPS/fonts/font%201.otf',
              'http://ns.adobe.com/pdf/enc#RC',
            ),
            extraManifestItem: '<item id="font" href="fonts/font%201.otf" media-type="font/otf"/>',
            extraFile: ArchiveFile.bytes('OEBPS/fonts/font 1.otf', [9, 9, 9]),
          ),
        );
        expect(book.spine, isNotEmpty);
        expect(book.resources.containsKey('OEBPS/fonts/font 1.otf'), isFalse);
      },
    );

    test('never treats a spine item or an image as an obfuscated font', () async {
      for (final path in ['OEBPS/chapter1.xhtml', 'OEBPS/image.png']) {
        await expectLater(
          parser.parseBytes(
            _buildEpubFixtureWithEncryption(
              encryptionXml: _encryptionEntry(
                path,
                'http://www.idpf.org/2008/embedding',
              ),
              extraManifestItem:
                  '<item id="image" href="image.png" media-type="image/png"/>',
              extraFile: ArchiveFile.bytes('OEBPS/image.png', [0]),
            ),
          ),
          throwsA(isA<EncryptedEpubException>()),
        );
      }
    });

    test(
      'rejects real encryption of fonts and malformed encryption metadata',
      () async {
        await expectLater(
          parser.parseBytes(
            _buildEpubFixtureWithEncryption(
              encryptionXml: _encryptionEntry(
                'OEBPS/font.otf',
                'unknown-encryption',
              ),
              extraManifestItem:
                  '<item id="font" href="font.otf" media-type="font/otf"/>',
              extraFile: ArchiveFile.bytes('OEBPS/font.otf', [0]),
            ),
          ),
          throwsA(isA<EncryptedEpubException>()),
        );
        for (final xml in [
          '<encryption>',
          '<wrong/>',
          '<encryption><EncryptedData/></encryption>',
        ]) {
          await expectLater(
            parser.parseBytes(
              _buildEpubFixtureWithEncryption(encryptionXml: xml),
            ),
            throwsA(isA<FormatException>()),
          );
        }
      },
    );
    test('parses normally when the file is absent', () async {
      // The base EPUB 3 fixture above already has no encryption.xml, so its
      // successful parse in the first test already covers this case; this
      // test only makes that coverage explicit and self-documenting.
      final book = await parser.parseBytes(_buildEpub3Fixture());
      expect(book.spine, isNotEmpty);
    });

    test('excludes an idpf-obfuscated publisher font from resources without '
        'throwing', () async {
      final book = await parser.parseBytes(
        _buildEpubFixtureWithEncryption(
          encryptionXml: '''
            <?xml version="1.0"?>
            <encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container"
                        xmlns:enc="http://www.w3.org/2001/04/xmlenc#">
              <enc:EncryptedData>
                <enc:EncryptionMethod Algorithm="http://www.idpf.org/2008/embedding"/>
                <enc:CipherData>
                  <enc:CipherReference URI="OEBPS/fonts/font1.otf"/>
                </enc:CipherData>
              </enc:EncryptedData>
            </encryption>
            ''',
          extraManifestItem:
              '<item id="font1" href="fonts/font1.otf" media-type="font/otf"/>',
          extraFile: ArchiveFile.bytes('OEBPS/fonts/font1.otf', [9, 9, 9]),
        ),
      );

      expect(book.spine, hasLength(1));
      expect(book.resources.containsKey('OEBPS/fonts/font1.otf'), isFalse);
    });

    test(
      'throws EncryptedEpubException for an encrypted spine document',
      () async {
        final bytes = _buildEpubFixtureWithEncryption(
          encryptionXml: '''
          <?xml version="1.0"?>
          <encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container"
                      xmlns:enc="http://www.w3.org/2001/04/xmlenc#">
            <enc:EncryptedData>
              <enc:EncryptionMethod Algorithm="http://www.w3.org/2001/04/xmlenc#aes256-cbc"/>
              <enc:CipherData>
                <enc:CipherReference URI="OEBPS/chapter1.xhtml"/>
              </enc:CipherData>
            </enc:EncryptedData>
          </encryption>
          ''',
        );

        await expectLater(
          parser.parseBytes(bytes),
          throwsA(
            isA<EncryptedEpubException>()
                .having(
                  (e) => e.resourcePath,
                  'resourcePath',
                  'OEBPS/chapter1.xhtml',
                )
                .having(
                  (e) => e.algorithm,
                  'algorithm',
                  'http://www.w3.org/2001/04/xmlenc#aes256-cbc',
                )
                .having((e) => e.message, 'message', contains('DRM')),
          ),
        );
      },
    );
  });
}

String _encryptionEntry(String path, String algorithm) =>
    '''
  <encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container"
    xmlns:enc="http://www.w3.org/2001/04/xmlenc#">
    <enc:EncryptedData><enc:EncryptionMethod Algorithm="$algorithm"/>
      <enc:CipherData><enc:CipherReference URI="$path"/></enc:CipherData>
    </enc:EncryptedData>
  </encryption>
''';

/// A minimal single-chapter EPUB with a `META-INF/encryption.xml`, for the
/// encryption/DRM-detection tests above. [extraManifestItem] and [extraFile]
/// let a test add one additional manifest entry (e.g. a font) plus its
/// archive bytes without duplicating the whole fixture.
Uint8List _buildEpubFixtureWithEncryption({
  required String encryptionXml,
  String extraManifestItem = '',
  ArchiveFile? extraFile,
}) {
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
    ..add(ArchiveFile.string('META-INF/encryption.xml', encryptionXml))
    ..add(
      ArchiveFile.string('OEBPS/content.opf', '''
      <?xml version="1.0" encoding="utf-8"?>
      <package xmlns="http://www.idpf.org/2007/opf" version="3.0">
        <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
          <dc:title>Encryption Fixture</dc:title>
        </metadata>
        <manifest>
          <item id="c1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
          $extraManifestItem
        </manifest>
        <spine><itemref idref="c1"/></spine>
      </package>
    '''),
    )
    ..add(
      ArchiveFile.string('OEBPS/chapter1.xhtml', '''
      <html xmlns="http://www.w3.org/1999/xhtml"><body>
        <h1>Chapter</h1>
        <p>Text.</p>
      </body></html>
    '''),
    );
  if (extraFile != null) archive.add(extraFile);
  return Uint8List.fromList(ZipEncoder().encode(archive));
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

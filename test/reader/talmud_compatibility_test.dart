import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:eink_launcher/reader/models/parsed_book.dart';
import 'package:eink_launcher/reader/models/reader_settings.dart';
import 'package:eink_launcher/reader/services/epub_parser_service.dart';
import 'package:eink_launcher/reader/services/tanach_layout_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Talmud EPUB dialect: base text is `section.segment[data-ref]`, the note
/// link has no `noteref` type, the index uses `class="note-index"`, and every
/// commentary aside is `data-category="commentary"` with a `p.translation`
/// English body. These fixtures mirror the generated pilot books so the reader
/// recognizes and projects them like the Tanach product.
Uint8List fixture() {
  final archive = Archive();
  void add(String path, String text) =>
      archive.add(ArchiveFile.string(path, text));
  add(
    'META-INF/container.xml',
    '<container><rootfiles><rootfile full-path="Book/book.opf"/></rootfiles></container>',
  );
  add(
    'Book/book.opf',
    '''<package><metadata><title>Berakhot</title></metadata><manifest>
    <item id="c" href="amud-3a.xhtml" media-type="application/xhtml+xml"/>
    </manifest><spine page-progression-direction="ltr"><itemref idref="c"/></spine></package>''',
  );
  add(
    'Book/amud-3a.xhtml',
    '''<html xmlns:epub="http://www.idpf.org/2007/ops"><body>
    <h1 class="amud-heading" id="amud-3a"><span lang="en">Daf 3a</span> <span lang="he" dir="rtl">דף ג׳ עמוד א׳</span></h1>
    <section class="segment" id="s-one" data-ref="Berakhot 3a:1">
      <div class="segment-heading"><span lang="en">Berakhot 3a:1</span></div>
      <p class="hebrew" dir="rtl" lang="he">מְאֵימָתַי</p>
      <p class="translation" dir="ltr" lang="en">From when</p>
      <p class="note-links"><a href="#idx-one">Notes &amp; commentary</a></p>
    </section>
    <aside epub:type="footnote" id="idx-one" class="note-index"><p class="note-links"><a epub:type="noteref" href="#n-one">Rashi on Berakhot</a></p></aside>
    <section class="segment" id="s-two" data-ref="Berakhot 3a:2">
      <div class="segment-heading"><span lang="en">Berakhot 3a:2</span></div>
      <p class="hebrew" dir="rtl" lang="he">וַחֲכָמִים</p>
      <p class="translation" dir="ltr" lang="en">The Rabbis say</p>
      <p class="note-links"><a href="#idx-two">Notes &amp; commentary</a></p>
    </section>
    <aside epub:type="footnote" id="idx-two" class="note-index"><p class="note-links"><a epub:type="noteref" href="#n-two">Steinsaltz on Berakhot</a></p></aside>
    <aside epub:type="footnote" id="n-one" class="commentary-note" data-source="Rashi on Berakhot" data-category="commentary" data-ref="Rashi on Berakhot 3a:1:1">
      <p class="note-title">Rashi on Berakhot 3a:1</p>
      <div class="note-he" dir="rtl" lang="he"><div>רש״י</div></div>
      <div class="note-en" dir="ltr" lang="en"><div>Rashi note</div></div>
      <p class="backlinks"><a href="#s-one">Back</a></p>
    </aside>
    <aside epub:type="footnote" id="n-two" class="commentary-note" data-source="Steinsaltz on Berakhot" data-category="commentary" data-ref="Steinsaltz on Berakhot 3a:2:1">
      <p class="note-title">Steinsaltz on Berakhot 3a:2</p>
      <div class="note-he" dir="rtl" lang="he"><div>שטיינזלץ</div></div>
      <div class="note-en" dir="ltr" lang="en"><div>Steinsaltz note</div></div>
    </aside>
    </body></html>''',
  );
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

String text(ParsedBook book) =>
    book.spine.first.blocks.map((b) => b.plainText).join('\n');

void main() {
  test('recognizer accepts the segment dialect', () {
    expect(
      TanachLayoutService.recognizes(
        '<html><body><section class="segment" data-ref="x">t</section></body></html>',
      ),
      isTrue,
    );
    expect(
      TanachLayoutService.recognizes('<html><body><p>plain</p></body></html>'),
      isFalse,
    );
  });

  test('parser treats the Talmud book as structured study text', () {
    final book = EpubParserService.parseBytesSync(fixture());
    expect(book.studyDocuments, isNotEmpty);
    expect(book.studySources, contains('Rashi on Berakhot'));
    expect(book.studySources, contains('Steinsaltz on Berakhot'));
    // No edition metadata on the primary translation, so there is no selector.
    expect(book.studyTranslations, isEmpty);

    final body = text(book);
    expect(body, isNot(contains('Notes & commentary')));
    expect(body, contains('מְאֵימָתַי'));
    expect(body, contains('From when'));
    // Commentary stays out of the reading flow until a source is selected.
    expect(body, isNot(contains('Rashi note')));
  });

  test('selecting a commentary source projects only that source', () {
    final book = EpubParserService.parseBytesSync(fixture());
    final filtered = TanachLayoutService.layout(
      book,
      const ReaderSettings(commentarySources: ['Rashi on Berakhot']),
    );
    final body = text(filtered);
    expect(body, contains('Rashi note'));
    expect(body, isNot(contains('Steinsaltz note')));
  });

  test('verse language drops the other side of each segment', () {
    final book = EpubParserService.parseBytesSync(fixture());

    final englishOnly = text(
      TanachLayoutService.layout(
        book,
        const ReaderSettings(verseLanguage: 'en'),
      ),
    );
    expect(englishOnly, contains('From when'));
    expect(englishOnly, isNot(contains('מְאֵימָתַי')));

    final hebrewOnly = text(
      TanachLayoutService.layout(
        book,
        const ReaderSettings(verseLanguage: 'he'),
      ),
    );
    expect(hebrewOnly, contains('מְאֵימָתַי'));
    expect(hebrewOnly, isNot(contains('From when')));
  });
}

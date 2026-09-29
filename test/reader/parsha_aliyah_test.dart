import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:eink_launcher/reader/models/doc_ref.dart';
import 'package:eink_launcher/reader/models/parsed_book.dart';
import 'package:eink_launcher/reader/models/reader_settings.dart';
import 'package:eink_launcher/reader/models/reading_position.dart';
import 'package:eink_launcher/reader/screens/reader_settings_screen.dart';
import 'package:eink_launcher/reader/services/epub_parser_service.dart';
import 'package:eink_launcher/reader/services/tanach_layout_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _aliyah = [
  'ראשון',
  'שני',
  'שלישי',
  'רביעי',
  'חמישי',
  'שישי',
  'שביעי',
];

/// The dual navigation the Torah builders emit: one chapter list carrying the
/// toc semantic, one Parshah/Aliyah list typed "other".
String _navigation({required bool parshaList}) {
  final children = [
    for (var i = 0; i < _aliyah.length; i++)
      '<li><a href="chapter-1.xhtml#aliyah-bereshit-${i + 1}">${_aliyah[i]}</a></li>',
  ].join();
  final chapterList =
      '<nav epub:type="toc" id="toc"><h1>Contents</h1><ol>'
      '<li><a href="chapter-1.xhtml">Genesis 1</a></li></ol></nav>';
  final parshaListMarkup =
      '<nav epub:type="other" id="parsha-toc"><h1>Parashiyot</h1><ol>'
      '<li><a href="chapter-1.xhtml#parsha-bereshit">בְּרֵאשִׁית</a>'
      '<ol>$children</ol></li></ol></nav>';
  return '$chapterList${parshaList ? parshaListMarkup : ''}';
}

/// A Torah-style chapter carrying the chapter heading next to the Parshah and
/// Aliyah headings, plus two verses so the projection has content.
const _dualChapter = '''
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><body>
<h1>Genesis 1</h1>
<h1 class="parsha-heading" id="parsha-bereshit" dir="ltr" style="display:flex; justify-content:space-between;"><span lang="en" xml:lang="en" dir="ltr">Bereshit</span> <span lang="he" xml:lang="he" dir="rtl">בְּרֵאשִׁית</span></h1>
<h2 class="aliyah-heading" id="aliyah-bereshit-1" dir="ltr" style="display:flex; justify-content:space-between; font-size:1.15em;"><span lang="en" xml:lang="en" dir="ltr">First Portion</span> <span lang="he" xml:lang="he" dir="rtl">ראשון</span></h2>
<section class="verse" id="v-1" data-ref="Genesis 1:1"><h2 class="verse-heading" dir="ltr"><span dir="ltr">Verse 1</span> <span dir="rtl">פסוק א׳</span></h2><p class="hebrew" dir="rtl" lang="he">בְּרֵאשִׁית</p></section>
<section class="verse" id="v-2" data-ref="Genesis 1:2"><h2 class="verse-heading" dir="ltr"><span dir="ltr">Verse 2</span> <span dir="rtl">פסוק ב׳</span></h2><p dir="rtl">שֵׁנִי</p></section>
</body></html>''';

/// A chapter without any Parshah heading, as every non-Torah book has.
const _plainChapter = '''
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><body>
<h1>Psalms 1</h1>
<section class="verse" id="v-1" data-ref="Psalms 1:1"><h2 class="verse-heading" dir="ltr"><span dir="ltr">Verse 1</span> <span dir="rtl">פסוק א׳</span></h2><p class="hebrew" dir="rtl" lang="he">אַשְׁרֵי</p></section>
</body></html>''';

Uint8List _fixture({required bool parshaList, String? chapter}) {
  final source = chapter ?? _plainChapter;
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
      <container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0">
        <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
      </container>'''),
    )
    ..add(
      ArchiveFile.string('OEBPS/content.opf', '''
      <?xml version="1.0" encoding="utf-8"?>
      <package xmlns="http://www.idpf.org/2007/opf" version="3.0">
        <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>Genesis</dc:title><dc:language>he</dc:language></metadata>
        <manifest>
          <item id="c1" href="chapter-1.xhtml" media-type="application/xhtml+xml"/>
          <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
        </manifest>
        <spine><itemref idref="c1"/></spine>
      </package>'''),
    )
    ..add(ArchiveFile.string('OEBPS/chapter-1.xhtml', source))
    ..add(
      ArchiveFile.string(
        'OEBPS/nav.xhtml',
        '''<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><body>${_navigation(parshaList: parshaList)}</body></html>''',
      ),
    );
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

String _text(ParsedBook book) =>
    book.spine.first.blocks.map((block) => block.plainText).join('\n');

void main() {
  const parser = EpubParserService();

  group('Parshah and Aliyah navigation document', () {
    test('is parsed beside the chapter table of contents', () async {
      final book = await parser.parseBytes(_fixture(parshaList: true));

      expect(book.hasParshaToc, isTrue);
      expect(book.tableOfContents, hasLength(1));
      expect(book.tableOfContents.single.title, 'Genesis 1');
      expect(book.tableOfContents.single.targetHref, 'OEBPS/chapter-1.xhtml');

      final parsha = book.parshaTableOfContents.single;
      expect(parsha.title, 'בְּרֵאשִׁית');
      expect(parsha.level, 0);
      expect(parsha.targetHref, 'OEBPS/chapter-1.xhtml#parsha-bereshit');
      expect(
        (parsha.position! as TextReadingPosition).blockId,
        'parsha-bereshit',
      );
      expect(parsha.children, hasLength(7));
      expect(parsha.children.first.title, 'ראשון');
      expect(parsha.children.first.level, 1);
      expect(
        parsha.children.last.targetHref,
        'OEBPS/chapter-1.xhtml#aliyah-bereshit-7',
      );
      expect(
        (parsha.children.last.position! as TextReadingPosition).blockId,
        'aliyah-bereshit-7',
      );
    });

    test('is absent when the publication carries only the chapter list', () async {
      final book = await parser.parseBytes(_fixture(parshaList: false));

      expect(book.hasParshaToc, isFalse);
      expect(book.parshaTableOfContents, isEmpty);
      expect(book.tableOfContents, hasLength(1));
    });
  });

  group('heading mode', () {
    test('drops the Parshah headings and keeps the chapter heading by default', () {
      final book = EpubParserService.parseBytesSync(
        _fixture(parshaList: true, chapter: _dualChapter),
      );
      final text = _text(book);

      expect(text, contains('Genesis 1'));
      expect(text, isNot(contains('Bereshit')));
      expect(text, isNot(contains('First Portion')));
      expect(text, contains('Verse 1'));
      expect(text, contains('Verse 2'));
    });

    test('shows the Parshah and Aliyah headings and drops the chapter heading', () {
      final parsed = EpubParserService.parseBytesSync(
        _fixture(parshaList: true, chapter: _dualChapter),
      );
      final book = TanachLayoutService.layout(
        parsed,
        const ReaderSettings(showParshaAliyot: true),
      );
      final text = _text(book);

      expect(text, isNot(contains('Genesis 1')));
      expect(text, contains('Bereshit'));
      expect(text, contains('First Portion'));
      expect(text, contains('Verse 1'));

      final parsha = book.parshaTableOfContents.single;
      expect(
        (parsha.position! as TextReadingPosition).blockIndex,
        greaterThanOrEqualTo(0),
      );
      expect(
        book.spine.first.anchors.keys,
        containsAll(['parsha-bereshit', 'aliyah-bereshit-1']),
      );

      final backToChapters = TanachLayoutService.layout(
        parsed,
        const ReaderSettings(showParshaAliyot: false),
      );
      expect(_text(backToChapters), contains('Genesis 1'));
      expect(_text(backToChapters), isNot(contains('Bereshit')));
    });

    test('leaves books without a Parshah heading untouched', () {
      final parsed = EpubParserService.parseBytesSync(
        _fixture(parshaList: false),
      );
      final book = TanachLayoutService.layout(
        parsed,
        const ReaderSettings(showParshaAliyot: true),
      );

      expect(_text(book), contains('Psalms 1'));
    });
  });

  test('showParshaAliyot survives the persisted settings round trip', () {
    const on = ReaderSettings(showParshaAliyot: true);

    expect(const ReaderSettings().showParshaAliyot, isFalse);
    expect(ReaderSettings.fromJson(on.toJson()).showParshaAliyot, isTrue);
    expect(on.copyWith(showParshaAliyot: false).showParshaAliyot, isFalse);
    expect(
      ReaderSettings.fromJson(
        on.copyWith(showParshaAliyot: false).toJson(),
      ).showParshaAliyot,
      isFalse,
    );
  });

  group('settings screen', () {
    testWidgets('offers the switch only when the book carries a list', (
      tester,
    ) async {
      ReaderSettings? saved;
      await openSettings(
        tester,
        hasParshaToc: false,
        onSaved: (value) => saved = value,
      );

      expect(
        find.byKey(const Key('reader-settings-parsha-headings')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('reader-settings-chapter-headings')),
        findsNothing,
      );
      expect(saved, isNull);
    });

    testWidgets('switching the headings and table of contents is saved', (
      tester,
    ) async {
      ReaderSettings? saved;
      await openSettings(
        tester,
        hasParshaToc: true,
        onSaved: (value) => saved = value,
      );

      expect(find.text('Headings and table of contents'), findsOneWidget);
      final parsha = find.byKey(const Key('reader-settings-parsha-headings'));
      expect(parsha, findsOneWidget);
      expect(find.text('Chapters'), findsOneWidget);

      await tester.tap(parsha);
      await tester.pump();
      await tester.tap(find.byKey(const Key('reader-settings-save')));
      await tester.pumpAndSettle();

      expect(saved, isNotNull);
      final settings = saved!;
      expect(settings.showParshaAliyot, isTrue);
      expect(settings.copyWith(showParshaAliyot: false).showParshaAliyot, isFalse);
    });
  });
}

/// Opens [ReaderSettingsScreen] on a route tall enough to show every group,
/// then reports what the screen saved.
Future<void> openSettings(
  WidgetTester tester, {
  required bool hasParshaToc,
  required void Function(ReaderSettings settings) onSaved,
}) async {
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => OutlinedButton(
          onPressed: () async {
            final settings = await Navigator.of(
              context,
            ).push<ReaderSettings>(
              MaterialPageRoute(
                builder: (_) => ReaderSettingsScreen(
                  initialSettings: const ReaderSettings(),
                  format: DocFormat.epub,
                  hasParshaToc: hasParshaToc,
                ),
              ),
            );
            if (settings != null) onSaved(settings);
          },
          child: const Text('Open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}


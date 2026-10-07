import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:eink_launcher/reader/models/doc_ref.dart';
import 'package:eink_launcher/reader/models/parsed_book.dart';
import 'package:eink_launcher/reader/models/reader_settings.dart';
import 'package:eink_launcher/reader/models/reading_position.dart';
import 'package:eink_launcher/reader/models/tehillim_daily.dart';
import 'package:eink_launcher/reader/models/toc_entry.dart';
import 'package:eink_launcher/reader/screens/reader_settings_screen.dart';
import 'package:eink_launcher/reader/screens/reader_toc_screen.dart';
import 'package:eink_launcher/reader/services/epub_parser_service.dart';
import 'package:eink_launcher/reader/services/tanach_layout_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

String _chapterSource(int chapter, {bool withDayHeading = false}) {
  final dayForChapter = _dayForChapter(chapter);
  final heading = withDayHeading && dayForChapter != null
      ? '<h1 class="tehillim-day-heading" id="tehillim-day-$dayForChapter" dir="ltr" style="display:flex; justify-content:space-between;"><span lang="en" xml:lang="en" dir="ltr">Day $dayForChapter</span> <span lang="he" xml:lang="he" dir="rtl">${TehillimDaily.dayNamesHe[dayForChapter - 1]}</span></h1>'
      : '';
  final verses = StringBuffer();
  final verseCount = chapter == 119 ? 176 : 5;
  final startVerse = 1;
  final endVerse = chapter == 119 ? verseCount : 3;
  for (var v = startVerse; v <= endVerse; v++) {
    // Day 26 starts at 119:97; include surrounding verses so the split is
    // addressable in the fallback test.
    if (chapter == 119 && v > 3 && v < 96) continue;
    if (chapter == 119 && v > 98 && v < 176 && v != 176) continue;
    verses.write(
      '<section class="verse" id="v-psalms-$chapter-$v" data-ref="Psalms $chapter:$v"><h2 class="verse-heading" dir="ltr"><span dir="ltr">Verse $v</span> <span dir="rtl">פסוק</span></h2><p class="hebrew" dir="rtl" lang="he">תהלים</p></section>',
    );
    if (chapter != 119 && v >= 3) break;
  }
  return '<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><body>'
      '<h1>Psalms $chapter</h1>$heading${verses.toString()}</body></html>';
}

int? _dayForChapter(int chapter) {
  for (var day = 1; day <= 30; day++) {
    if (TehillimDaily.dayChapters[day - 1].contains(chapter)) {
      // Day 25 owns 119:1-96; report 25 for the chapter start.
      if (chapter == 119) return day == 26 ? 26 : 25;
      return day;
    }
  }
  return null;
}

String _chapterNavList() {
  final items = [
    for (var ch = 1; ch <= 150; ch++)
      '<li><a href="chapter-$ch.xhtml">Psalms $ch</a></li>',
  ].join();
  return '<nav epub:type="toc" id="toc"><h1>Contents</h1><ol>$items</ol></nav>';
}

String _tehillimNav() {
  final items = <String>[];
  for (var day = 1; day <= 30; day++) {
    final chapters = TehillimDaily.dayChapters[day - 1];
    final first = day == 26 ? 119 : chapters.first;
    final children = <String>[];
    for (final ch in chapters) {
      if (ch == 119 && (day == 25 || day == 26)) {
        final v = day == 25 ? 1 : 97;
        children.add(
          '<li><a href="chapter-$ch.xhtml#v-psalms-$ch-$v">Psalms $ch</a></li>',
        );
      } else {
        children.add('<li><a href="chapter-$ch.xhtml">Psalms $ch</a></li>');
      }
    }
    items.add(
      '<li><a href="chapter-$first.xhtml#tehillim-day-$day">Day $day</a>'
      '<ol>${children.join()}</ol></li>',
    );
  }
  return '<nav epub:type="other" id="tehillim-toc"><h1>Daily Tehillim</h1><ol>${items.join()}</ol></nav>';
}

Uint8List _fixture({required bool dailyNav, bool dayHeadings = false}) {
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
    );
  final manifestItems = StringBuffer();
  final spineRefs = StringBuffer();
  for (var ch = 1; ch <= 150; ch++) {
    manifestItems.write(
      '<item id="c$ch" href="chapter-$ch.xhtml" media-type="application/xhtml+xml"/>',
    );
    spineRefs.write('<itemref idref="c$ch"/>');
  }
  archive
    ..add(
      ArchiveFile.string('OEBPS/content.opf', '''
      <?xml version="1.0" encoding="utf-8"?>
      <package xmlns="http://www.idpf.org/2007/opf" version="3.0">
        <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>Psalms</dc:title><dc:language>he</dc:language></metadata>
        <manifest>
          $manifestItems
          <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
        </manifest>
        <spine>$spineRefs</spine>
      </package>'''),
    )
    ..add(
      ArchiveFile.string(
        'OEBPS/nav.xhtml',
        '<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><body>${_chapterNavList()}${dailyNav ? _tehillimNav() : ''}</body></html>',
      ),
    );
  for (var ch = 1; ch <= 150; ch++) {
    archive.add(
      ArchiveFile.string(
        'OEBPS/chapter-$ch.xhtml',
        _chapterSource(ch, withDayHeading: dayHeadings && (ch == 1 || ch == 119)),
      ),
    );
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

String _text(ParsedBook book) =>
    book.spine.first.blocks.map((block) => block.plainText).join('\n');

void main() {
  const parser = EpubParserService();

  group('Tehillim navigation document', () {
    test('is parsed beside the chapter table of contents', () async {
      final book = await parser.parseBytes(
        _fixture(dailyNav: true, dayHeadings: true),
      );

      expect(book.hasTehillimToc, isTrue);
      expect(book.tableOfContents, hasLength(150));
      expect(book.tehillimDailyTableOfContents, hasLength(30));

      final day1 = book.tehillimDailyTableOfContents.first;
      expect(day1.title, 'Day 1');
      expect(day1.level, 0);
      expect(day1.targetHref, contains('#tehillim-day-1'));
      expect(day1.children, hasLength(9));
      expect(day1.children.first.level, 1);

      final day25 = book.tehillimDailyTableOfContents[24];
      final day26 = book.tehillimDailyTableOfContents[25];
      expect(day25.children, hasLength(1));
      expect(day26.children, hasLength(1));
      // Psalm 119 split: children point to verse anchors in the shared file.
      expect(day25.children.single.targetHref, contains('chapter-119.xhtml#'));
      expect(day26.children.single.targetHref, contains('chapter-119.xhtml#'));
      expect(
        day25.children.single.targetHref,
        isNot(day26.children.single.targetHref),
      );
      expect(
        (day26.children.single.position! as TextReadingPosition).blockId,
        isNotNull,
      );
    });

    test('is synthesized when the nav list is missing', () async {
      final book = await parser.parseBytes(_fixture(dailyNav: false));

      expect(book.hasTehillimToc, isTrue);
      expect(book.tehillimDailyTableOfContents, hasLength(30));
      expect(
        book.tehillimDailyTableOfContents.first.children,
        hasLength(9),
      );
      final day26 = book.tehillimDailyTableOfContents[25];
      expect(day26.title, 'Day 26');
      expect(day26.targetHref, contains('#tehillim-day-26'));
      expect(day26.children.single.targetHref, contains('chapter-119.xhtml#'));
    });

    test('is absent for non-Psalms books', () async {
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
            <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>Genesis</dc:title></metadata>
            <manifest>
              <item id="c1" href="chapter-1.xhtml" media-type="application/xhtml+xml"/>
              <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
            </manifest>
            <spine><itemref idref="c1"/></spine>
          </package>'''),
        )
        ..add(
          ArchiveFile.string(
            'OEBPS/chapter-1.xhtml',
            '<html xmlns="http://www.w3.org/1999/xhtml"><body><h1>Genesis 1</h1><section class="verse" id="v-1" data-ref="Genesis 1:1"><p>text</p></section></body></html>',
          ),
        )
        ..add(
          ArchiveFile.string(
            'OEBPS/nav.xhtml',
            '<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><body><nav epub:type="toc"><ol><li><a href="chapter-1.xhtml">Genesis 1</a></li></ol></nav></body></html>',
          ),
        );
      final book = await parser.parseBytes(
        Uint8List.fromList(ZipEncoder().encode(archive)),
      );
      expect(book.hasTehillimToc, isFalse);
      expect(book.tehillimDailyTableOfContents, isEmpty);
    });
  });

  group('heading mode', () {
    test('drops daily headings by default, shows them in daily mode', () {
      final parsed = EpubParserService.parseBytesSync(
        _fixture(dailyNav: true, dayHeadings: true),
      );
      final chapters = _text(parsed);
      expect(chapters, contains('Psalms 1'));
      expect(chapters, isNot(contains('Day 1')));

      final daily = TanachLayoutService.layout(
        parsed,
        const ReaderSettings(showDailyTehillim: true),
      );
      final dailyText = _text(daily);
      expect(dailyText, isNot(contains('Psalms 1')));
      expect(dailyText, contains('Day 1'));
      expect(daily.spine.first.anchors.keys, contains('tehillim-day-1'));

      final back = TanachLayoutService.layout(
        parsed,
        const ReaderSettings(showDailyTehillim: false),
      );
      expect(_text(back), contains('Psalms 1'));
    });

    test('injects fallback day headings for legacy EPUBs', () {
      final parsed = EpubParserService.parseBytesSync(
        _fixture(dailyNav: false),
      );
      // Legacy file carries no day headings in its source.
      expect(
        parsed.studyDocuments.values.any(
          (source) => source.contains('tehillim-day-heading'),
        ),
        isFalse,
      );
      final daily = TanachLayoutService.layout(
        parsed,
        const ReaderSettings(showDailyTehillim: true),
      );
      expect(_text(daily), contains('Day 1'));
      expect(daily.spine.first.anchors.keys, contains('tehillim-day-1'));
    });

    test('renders day labels as bilingual split headings', () {
      final parsed = EpubParserService.parseBytesSync(
        _fixture(dailyNav: true, dayHeadings: true),
      );
      final daily = TanachLayoutService.layout(
        parsed,
        const ReaderSettings(showDailyTehillim: true),
      );
      final headings = daily.spine.first.blocks
          .where((block) => block.id == 'tehillim-day-1')
          .toList();
      expect(headings, hasLength(1));
      expect(headings.single.hasSplitLayout, isTrue);
      expect(headings.single.runs.single.text, 'Day 1');
      expect(
        headings.single.trailingRuns.single.text,
        TehillimDaily.dayNamesHe.first,
      );
    });
  });

  test('showDailyTehillim survives the persisted settings round trip', () {
    const on = ReaderSettings(showDailyTehillim: true);

    expect(const ReaderSettings().showDailyTehillim, isFalse);
    expect(ReaderSettings.fromJson(on.toJson()).showDailyTehillim, isTrue);
    expect(on.copyWith(showDailyTehillim: false).showDailyTehillim, isFalse);
  });

  group('settings screen', () {
    testWidgets('offers the daily switch only when Psalms carries it', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      ReaderSettings? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => OutlinedButton(
              onPressed: () async {
                final settings = await Navigator.of(context)
                    .push<ReaderSettings>(
                      MaterialPageRoute(
                        builder: (_) => const ReaderSettingsScreen(
                          initialSettings: ReaderSettings(),
                          format: DocFormat.epub,
                          hasTehillimToc: true,
                        ),
                      ),
                    );
                if (settings != null) saved = settings;
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Daily Tehillim'), findsOneWidget);
      await tester.tap(find.byKey(const Key('reader-settings-tehillim-days')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('reader-settings-save')));
      await tester.pumpAndSettle();

      expect(saved?.showDailyTehillim, isTrue);
    });
  });

  group('expandable table of contents', () {
    testWidgets('day parents collapse and expand, chapters navigate', (
      tester,
    ) async {
      const dayEntries = [
        TocEntry(
          title: 'Day 1',
          position: TextReadingPosition(
            spineIndex: 0,
            blockIndex: 0,
            charOffset: 0,
          ),
          children: [
            TocEntry(
              title: 'Psalms 1',
              level: 1,
              position: TextReadingPosition(
                spineIndex: 0,
                blockIndex: 0,
                charOffset: 0,
              ),
            ),
            TocEntry(
              title: 'Psalms 2',
              level: 1,
              position: TextReadingPosition(
                spineIndex: 1,
                blockIndex: 0,
                charOffset: 0,
              ),
            ),
          ],
        ),
        TocEntry(
          title: 'Day 2',
          position: TextReadingPosition(
            spineIndex: 2,
            blockIndex: 0,
            charOffset: 0,
          ),
          children: [
            TocEntry(
              title: 'Psalms 10',
              level: 1,
              position: TextReadingPosition(
                spineIndex: 2,
                blockIndex: 0,
                charOffset: 0,
              ),
            ),
          ],
        ),
      ];
      TocEntry? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                selected = await Navigator.of(context).push<TocEntry>(
                  MaterialPageRoute(
                    builder: (_) =>
                        const ReaderTocScreen(entries: dayEntries),
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Day 1'), findsOneWidget);
      expect(find.text('Psalms 1'), findsNothing);

      await tester.tap(find.textContaining('Day 1'));
      await tester.pumpAndSettle();
      expect(find.text('Psalms 1'), findsOneWidget);
      expect(selected, isNull);

      await tester.tap(find.text('Psalms 1'));
      await tester.pumpAndSettle();
      expect(selected, isNotNull);
    });
  });
}

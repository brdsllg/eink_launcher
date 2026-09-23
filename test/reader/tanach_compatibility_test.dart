import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:eink_launcher/reader/models/content_block.dart';
import 'package:eink_launcher/reader/models/reader_settings.dart';
import 'package:eink_launcher/reader/services/epub_parser_service.dart';
import 'package:eink_launcher/reader/services/tanach_layout_service.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List fixture({bool broken = false}) {
  final archive = Archive();
  void add(String path, String text) =>
      archive.add(ArchiveFile.string(path, text));
  add(
    'META-INF/container.xml',
    '<container><rootfiles><rootfile full-path="Book/book.opf"/></rootfiles></container>',
  );
  add(
    'Book/book.opf',
    '''<package><metadata><title>Study</title></metadata><manifest>
    <item id="c" href="chapter.xhtml" media-type="application/xhtml+xml"/>
    <item id="n" href="notes.xhtml" media-type="application/xhtml+xml"/>
    </manifest><spine page-progression-direction="ltr"><itemref idref="c"/><itemref idref="n"/></spine></package>''',
  );
  add(
    'Book/chapter.xhtml',
    '''<html xmlns:ops="http://www.idpf.org/2007/ops"><body><h1>Genesis</h1>
    <section class="verse" id="v-one" data-ref="Genesis 1:1">
      <h2 class="verse-heading" dir="ltr"><span dir="ltr">Verse 1</span> <span dir="rtl">פסוק א׳</span></h2>
      <p class="hebrew" dir="rtl" lang="he">בְּרֵאשִׁית [כתיב]</p>
      <div class="translation" dir="ltr" data-edition="metsudah-ed" data-primary="true" data-translation-label="Metsudah">First verse</div>
      <p><a ops:type="noteref" href="notes.xhtml#index">Notes</a></p>
    </section>
    <section class="verse" id="v-two" data-ref="Genesis 1:2">
      <h2 class="verse-heading" dir="ltr"><span dir="ltr">Verse 2</span> <span dir="rtl">פסוק ב׳</span></h2>
      <p dir="rtl">שֵׁנִי</p><div class="translation" data-edition="koren-ed" data-primary="true" data-translation-label="Koren">Second verse</div>
      <p><a ops:type="noteref" href="notes.xhtml#index-two">Notes</a></p>
    </section><aside id="ordinary">Unrelated aside remains</aside></body></html>''',
  );
  add(
    'Book/notes.xhtml',
    '''<html xmlns:ops="http://www.idpf.org/2007/ops"><body><section>
    <h2>Translations and commentary</h2>
    <aside ops:type="footnote" data-category="index" id="index">
      <a ops:type="noteref" href="#${broken ? 'missing' : 'rashi'}">Rashi</a>
      <a ops:type="noteref" href="#rashi">Duplicate</a>
      <a ops:type="noteref" href="#other">Other</a>
      <a ops:type="noteref" href="#alternate">Alternate</a>
    </aside>
    <aside ops:type="footnote" data-category="index" id="index-two">
      <a ops:type="noteref" href="#rashi">Shared Rashi</a>
    </aside>
    <aside ops:type="footnote" data-category="rishon" data-source="Rashi on Genesis" id="rashi">
      <p class="note-title">Rashi 1:1</p><div class="note-he" dir="rtl" lang="he" data-editions="he-one he-two"><div class="comment-segment"><div class="note-paragraph">רַשִׁי<br/>שורה</div></div></div>
      <div class="note-en" dir="ltr" lang="en" data-editions="en-one"><div class="comment-segment"><div class="note-paragraph">Full <b>English</b> note</div></div></div>
      <p class="label">Edition attribution</p><p class="backlinks"><a href="chapter.xhtml#v-one">Back</a></p>
    </aside>
    <aside ops:type="footnote" data-category="modern" data-source="Other" id="other">
      <h3>Other heading</h3><div class="note-he" dir="rtl">עברית בלבד</div>
    </aside>
    <aside ops:type="footnote" data-category="translation" data-source="Alternate" data-edition="alternate-ed" id="alternate">
      <div dir="ltr" lang="en">Alternate verse</div><p class="backlinks">Back</p>
    </aside></section></body></html>''',
  );
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

void main() {
  test('inline notes follow their invoking verse, with deduplication and shared notes', () {
    final original = EpubParserService.parseBytesSync(fixture());
    // A fresh reader session starts with every source unselected; select
    // everything the fixture offers to exercise the full inline-notes path.
    final book = TanachLayoutService.layout(
      original,
      const ReaderSettings(commentarySources: ['Other', 'Rashi on Genesis']),
    );
    final text = book.spine.first.blocks.map((b) => b.plainText).join('\n');
    expect(text.indexOf('Rashi 1:1'), lessThan(text.indexOf('Second verse')));
    expect('Rashi 1:1'.allMatches(text).length, 2);
    expect(text, contains('Full English note'));
    expect(text, contains('Edition attribution'));
    expect(text, contains('Unrelated aside remains'));
    expect(text, isNot(contains('Alternate verse')));
    expect(book.spine[1].blocks, isEmpty);
    expect(book.spine.first.anchors.keys, containsAll(['v-one', 'v-two']));
    expect(
      book.spine.first.blocks
          .where((b) => b.plainText.contains('רַשִׁי'))
          .first
          .direction,
      BlockTextDirection.rtl,
    );
    expect(book.studySources, ['Other', 'Rashi on Genesis']);
    expect(book.studyTranslations.map((option) => option.label), [
      'Metsudah',
      'Koren',
      'Alternate',
    ]);
    expect(book.primaryStudyTranslationId, 'metsudah-ed');
    expect(book.rightToLeft, isFalse);
    final heading = book.spine.first.blocks.firstWhere(
      (block) => block.plainText == 'Verse 1 פסוק א׳',
    );
    expect(heading.hasSplitLayout, isTrue);
    expect(heading.fontSizeMultiplier, 1.15);
  });

  test(
    'source and language selection preserve originals and stable block ids',
    () {
      final original = EpubParserService.parseBytesSync(fixture());
      final base = TanachLayoutService.layout(
        original,
        const ReaderSettings(commentarySources: ['Rashi on Genesis']),
      );
      final selected = TanachLayoutService.layout(
        original,
        const ReaderSettings(
          commentarySources: ['Rashi on Genesis'],
          commentaryLanguage: 'en',
        ),
      );
      final text = selected.spine.first.blocks
          .map((b) => b.plainText)
          .join('\n');
      expect(text, contains('Full English note'));
      expect(text, isNot(contains('רַשִׁי')));
      expect(text, isNot(contains('Other heading')));
      final originalNote = base.spine.first.blocks.firstWhere(
        (b) => b.plainText == 'Full English note',
      );
      final selectedNote = selected.spine.first.blocks.firstWhere(
        (b) => b.plainText == 'Full English note',
      );
      expect(selectedNote.id, originalNote.id);
      expect(selected.studyDocuments, original.studyDocuments);
      final restored = TanachLayoutService.layout(
        selected,
        const ReaderSettings(),
      );
      expect(
        restored.spine.first.blocks.length,
        original.spine.first.blocks.length,
      );
      final fallback = TanachLayoutService.layout(
        original,
        const ReaderSettings(
          commentarySources: ['Other'],
          commentaryLanguage: 'en',
        ),
      );
      expect(
        fallback.spine.first.blocks.map((b) => b.plainText).join(),
        contains('עברית בלבד'),
      );
    },
  );

  test('translation changes keep honest fallback labels and base Hebrew', () {
    final original = EpubParserService.parseBytesSync(fixture());
    final selected = TanachLayoutService.layout(
      original,
      const ReaderSettings(studyTranslation: 'alternate-ed'),
    );
    final text = selected.spine.first.blocks.map((b) => b.plainText).join('\n');
    expect(text, contains('Alternate verse'));
    expect(text, isNot(contains('First verse')));
    expect(text, contains('Second verse'));
    expect(text, isNot(contains('Metsudah')));
    expect(text, isNot(contains('Koren')));
    expect(text, isNot(contains('Alternate edition')));
    expect(text, contains('בְּרֵאשִׁית [כתיב]'));
    expect(text, isNot(contains('Rashi 1:1')));
  });

  test('unresolved index remains accessible', () {
    final book = EpubParserService.parseBytesSync(fixture(broken: true));
    expect(
      book.spine.first.blocks.map((b) => b.plainText).join(),
      contains('Notes'),
    );
    expect(
      book.spine[1].blocks.map((b) => b.plainText).join(),
      contains('Duplicate'),
    );
  });

  final samples = Platform.environment['TANACH_SAMPLES_DIR'];
  if (samples != null) {
    test(
      'all nine real EPUB samples retain verses and full inline notes',
      () async {
        final files = Directory(samples)
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.epub'))
            .toList();
        expect(files.length, 9);
        for (final file in files) {
          final watch = Stopwatch()..start();
          final book = await const EpubParserService().parseFile(file.path);
          expect(book.studySources, isNotEmpty, reason: file.path);
          expect(book.rightToLeft, isFalse, reason: file.path);
          expect(book.studyTranslations, isNotEmpty, reason: file.path);
          expect(
            book.studyTranslations.map((option) => option.label),
            isNot(contains('Book default')),
            reason: file.path,
          );
          final chapter = book.spine.firstWhere(
            (item) => item.href.contains('chapter-'),
          );
          final text = chapter.blocks.map((b) => b.plainText).join('\n');
          expect(
            text,
            isNot(contains('Translations and commentary')),
            reason: file.path,
          );
          final headings = chapter.blocks
              .where(
                (block) =>
                    block.type == BlockType.heading2 &&
                    block.id?.startsWith('v-') == true,
              )
              .toList();
          expect(headings, isNotEmpty, reason: file.path);
          expect(
            headings.every(
              (block) =>
                  block.hasSplitLayout && block.fontSizeMultiplier == 1.15,
            ),
            isTrue,
            reason: file.path,
          );
          final filtered = TanachLayoutService.layout(
            book,
            const ReaderSettings(
              commentarySources: ['Rashi on Genesis'],
              commentaryLanguage: 'both',
            ),
          );
          expect(filtered.studyDocuments, isNotEmpty);
          // Record measurements from the host; these are not device timings.
          // ignore: avoid_print
          print(
            jsonEncode({
              'sample': file.uri.pathSegments.last,
              'hostMilliseconds': watch.elapsedMilliseconds,
              'blocks': book.spine.fold<int>(0, (n, s) => n + s.blocks.length),
              'sources': book.studySources.length,
            }),
          );
        }
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  }
}

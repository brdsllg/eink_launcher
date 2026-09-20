import 'dart:io';

import 'package:eink_launcher/reader/controllers/text_reader_session.dart';
import 'package:eink_launcher/reader/models/doc_ref.dart';
import 'package:eink_launcher/reader/models/parsed_book.dart';
import 'package:eink_launcher/reader/models/reader_settings.dart';
import 'package:eink_launcher/reader/models/reading_position.dart';
import 'package:eink_launcher/reader/models/toc_entry.dart';
import 'package:eink_launcher/reader/services/book_store_service.dart';
import 'package:eink_launcher/reader/services/pagination_cache_service.dart';
import 'package:eink_launcher/reader/services/tanach_sqlite_cache_service.dart';
import 'package:eink_launcher/reader/services/tanach_sqlite_search_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late File epub;
  late DocRef doc;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('tanach-sqlite-test-');
    epub = File('${directory.path}/genesis.epub');
    await epub.writeAsString('fingerprinted source');
    doc = DocRef(
      id: 'genesis-test',
      path: epub.path,
      format: DocFormat.epub,
      title: 'Genesis',
      fileSize: await epub.length(),
    );
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test(
    'imports all chapters, reopens by fingerprint, and loads lazily',
    () async {
      final service = TanachSqliteCacheService(
        cacheDirectory: Directory('${directory.path}/cache'),
      );
      final imported = await service.import(
        doc,
        _book(),
        fingerprint: 'fingerprint-a',
      );

      expect(imported.hasLazyTanachContent, isTrue);
      expect(imported.spine, hasLength(2));
      expect(imported.spine.every((item) => item.isLazy), isTrue);
      expect(imported.spine.every((item) => !item.isLoaded), isTrue);
      expect(imported.studySources, contains('Rashi on Genesis'));
      expect(
        imported.studyTranslations.map((option) => option.label),
        containsAll(['Metsudah', 'Koren']),
      );

      final chapter = await service.loadChapter(
        imported,
        0,
        const ReaderSettings(),
      );
      expect(chapter.isLoaded, isTrue);
      expect(chapter.isLazy, isTrue);
      expect(
        chapter.blocks.map((block) => block.plainText).join('\n'),
        contains('Commentary text'),
      );

      final reopened = await service.loadIfCurrent(
        doc,
        fingerprint: 'fingerprint-a',
      );
      expect(reopened, isNotNull);
      expect(reopened!.spine.every((item) => !item.isLoaded), isTrue);
      expect(await service.loadIfCurrent(doc, fingerprint: 'changed'), isNull);
    },
  );

  test(
    'SQLite searches normalized Hebrew and respects commentary filters',
    () async {
      final service = TanachSqliteCacheService(
        cacheDirectory: Directory('${directory.path}/cache'),
      );
      final imported = await service.import(
        doc,
        _book(),
        fingerprint: 'fingerprint-a',
      );
      final path = imported.tanachDatabasePath!;

      final hebrew = await TanachSqliteSearchService(
        databasePath: path,
        settings: const ReaderSettings(),
      ).search(imported.spine, 'בראשית');
      expect(hebrew.matches, isNotEmpty);
      expect(hebrew.matches.first.position.blockId, 'v-genesis-1-1--block-1');
      final chapter = await service.loadChapter(
        imported,
        0,
        const ReaderSettings(),
      );
      final match = hebrew.matches.first;
      expect(
        chapter.blocks[match.position.blockIndex].plainText.substring(
          match.position.charOffset,
          match.endCharOffset,
        ),
        'בְּרֵאשִׁית',
      );

      final commentary = await TanachSqliteSearchService(
        databasePath: path,
        settings: const ReaderSettings(),
      ).search(imported.spine, 'Commentary text');
      expect(commentary.matches, isNotEmpty);
      expect(
        commentary.matches.first.position.documentPath,
        'text/chapter-1.xhtml',
      );

      final infix = await TanachSqliteSearchService(
        databasePath: path,
        settings: const ReaderSettings(),
      ).search(imported.spine, 'mentar');
      expect(infix.matches, isNotEmpty);

      final hidden = await TanachSqliteSearchService(
        databasePath: path,
        settings: const ReaderSettings(inlineCommentary: false),
      ).search(imported.spine, 'Commentary text');
      expect(hidden.matches, isEmpty);

      final selectedTranslation = TanachSqliteSearchService(
        databasePath: path,
        settings: const ReaderSettings(studyTranslation: 'koren'),
      );
      expect(
        (await selectedTranslation.search(
          imported.spine,
          'Alternate translation',
        )).matches,
        isNotEmpty,
      );
      expect(
        (await selectedTranslation.search(
          imported.spine,
          'Primary translation',
        )).matches,
        isEmpty,
      );
    },
  );

  test('reader loads and reprojects only the requested lazy chapter', () async {
    final service = TanachSqliteCacheService(
      cacheDirectory: Directory('${directory.path}/cache'),
    );
    final imported = await service.import(
      doc,
      _book(),
      fingerprint: 'fingerprint-a',
    );
    final store = BookStoreService.instance;
    await store.init(customFile: File('${directory.path}/library.json'));
    final session = TextReaderSession(
      doc: doc,
      bookStore: store,
      paginationCache: PaginationCacheService(
        cacheDirectory: Directory('${directory.path}/pages'),
      ),
      tanachCache: service,
      bookLoader: (_, _) async => imported,
    );
    try {
      await session.open();
      expect(session.error, isNull);
      expect(session.book!.spine[0].isLoaded, isTrue);
      expect(session.book!.spine[1].isLoaded, isFalse);

      await session.goToToc(
        const TocEntry(
          title: 'Genesis 2',
          position: TextReadingPosition(
            documentPath: 'text/chapter-2.xhtml',
            blockId: 'v-genesis-2-1',
            verseId: 'v-genesis-2-1',
            spineIndex: 1,
            blockIndex: 0,
            charOffset: 0,
          ),
        ),
      );
      expect((session.position as TextReadingPosition).spineIndex, 1);
      expect(session.book!.spine[1].isLoaded, isTrue);

      await session.applySettings(
        session.settings.copyWith(inlineCommentary: false),
      );
      final text = session.book!.spine[1].blocks
          .map((block) => block.plainText)
          .join('\n');
      expect(text, isNot(contains('Commentary text')));
      expect(
        (session.position as TextReadingPosition).blockId,
        'v-genesis-2-1',
      );
    } finally {
      session.dispose();
      store.dispose();
    }
  });
  test(
    'live suspended sessions survive pruning and missing databases recover',
    () async {
      final service = TanachSqliteCacheService(
        cacheDirectory: Directory('${directory.path}/cache'),
        cacheByteLimit: 1,
      );
      var imports = 0;
      Future<ParsedBook> load(DocRef _, bool css) async {
        return await service.loadIfCurrent(doc, fingerprint: 'a') ??
            await (() async {
              imports++;
              return service.import(doc, _book(), fingerprint: 'a');
            })();
      }

      final store = BookStoreService.instance;
      await store.init(customFile: File('${directory.path}/library.json'));
      final session = TextReaderSession(
        doc: doc,
        bookStore: store,
        tanachCache: service,
        bookLoader: load,
      );
      try {
        await session.open();
        final path = session.book!.tanachDatabasePath!;
        session.suspend();
        const other = DocRef(
          id: 'other',
          path: 'other.epub',
          title: 'Other',
          format: DocFormat.epub,
          fileSize: 1,
        );
        await service.import(other, _book(), fingerprint: 'other');
        expect(await File(path).exists(), isTrue);
        await session.resume();
        await File(path).delete();
        final results = await session.searchService.search(
          session.book!.spine,
          'Commentary',
        );
        expect(results.matches, hasLength(2));
        expect(imports, 2);
        await File(path).delete();
        await session.goToToc(
          const TocEntry(
            title: 'Second',
            position: TextReadingPosition(
              spineIndex: 1,
              blockIndex: 0,
              charOffset: 0,
            ),
          ),
        );
        expect(session.book!.spine[1].isLoaded, isTrue);
        expect(imports, 3);
        session.dispose();
        await service.import(other, _book(), fingerprint: 'other');
        expect(await File(path).exists(), isFalse);
      } finally {
        if (session.book != null) session.dispose();
        store.dispose();
      }
    },
  );

  test(
    'percent uses identical coordinates before and after lazy loads',
    () async {
      final service = TanachSqliteCacheService(
        cacheDirectory: Directory('${directory.path}/cache'),
      );
      final imported = await service.import(doc, _book(), fingerprint: 'a');
      final store = BookStoreService.instance;
      await store.init(customFile: File('${directory.path}/library.json'));
      final session = TextReaderSession(
        doc: doc,
        bookStore: store,
        tanachCache: service,
        bookLoader: (_, _) async => imported,
      );
      try {
        await session.open();
        await session.applySettings(
          session.settings.copyWith(inlineCommentary: false),
        );
        await session.goToPercent(.75);
        final cold = session.position.toJson();
        expect(session.percent, closeTo(.75, .015));
        await session.goToPercent(.2);
        await session.goToPercent(.75);
        expect(session.position.toJson(), cold);
        expect(session.book!.characterCount, imported.characterCount);
        await session.goToPercent(1);
        expect(session.percent, 1);
        await session.goToPercent(0);
        expect(session.percent, 0);
      } finally {
        session.dispose();
        store.dispose();
      }
    },
  );
}

ParsedBook _book() => ParsedBook(
  title: 'Genesis',
  contentFingerprint: 'content-fingerprint',
  spine: [
    ParsedSpineItem(
      id: 'chapter-1',
      href: 'text/chapter-1.xhtml',
      title: 'Genesis 1',
      blocks: const [],
    ),
    ParsedSpineItem(
      id: 'chapter-2',
      href: 'text/chapter-2.xhtml',
      title: 'Genesis 2',
      blocks: const [],
    ),
  ],
  studyDocuments: {
    'text/chapter-1.xhtml': _chapter(1, 'בְּרֵאשִׁית'),
    'text/chapter-2.xhtml': _chapter(2, 'וַיְכֻלּוּ'),
  },
);

String _chapter(int chapter, String hebrew) =>
    '''
<html xmlns="http://www.w3.org/1999/xhtml"
      xmlns:epub="http://www.idpf.org/2007/ops">
<body>
  <section class="verse" id="v-genesis-$chapter-1" data-ref="Genesis $chapter:1">
    <h2>Verse 1</h2>
    <div class="hebrew" lang="he" dir="rtl">$hebrew</div>
    <div class="translation" lang="en" dir="ltr"
         data-edition="metsudah" data-primary="true"
         data-translation-label="Metsudah">Primary translation</div>
    <p><a epub:type="noteref" href="#index-$chapter">Notes</a></p>
  </section>
  <aside epub:type="footnote" data-category="index" id="index-$chapter">
    <a epub:type="noteref" href="#translation-$chapter">Koren</a>
    <a epub:type="noteref" href="#rashi-$chapter">Rashi</a>
  </aside>
  <aside epub:type="footnote" data-category="translation" id="translation-$chapter"
         data-source="Koren" data-edition="koren">
    <div lang="en" dir="ltr">Alternate translation</div>
  </aside>
  <aside epub:type="footnote" class="commentary-note" id="rashi-$chapter"
         data-category="rishon" data-source="Rashi on Genesis"
         data-ref="Rashi on Genesis $chapter:1">
    <p class="note-title">Rashi</p>
    <div class="note-en" lang="en"><p>Commentary text chapter $chapter</p></div>
  </aside>
</body>
</html>
''';

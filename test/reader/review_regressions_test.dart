import 'dart:io';

import 'package:eink_launcher/reader/models/annotation.dart';

import 'dart:ui';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eink_launcher/reader/models/doc_ref.dart';
import 'package:eink_launcher/reader/models/parsed_book.dart';
import 'package:eink_launcher/reader/models/reader_settings.dart';
import 'package:eink_launcher/reader/models/reading_position.dart';
import 'package:eink_launcher/reader/services/epub_parser_service.dart';
import 'package:eink_launcher/reader/services/tanach_sqlite_cache_service.dart';
import 'package:eink_launcher/reader/services/tanach_sqlite_search_service.dart';
import 'package:eink_launcher/reader/controllers/text_reader_session.dart';
import 'package:eink_launcher/reader/services/book_store_service.dart';
import 'package:eink_launcher/reader/services/tanach_layout_service.dart';
import 'package:eink_launcher/reader/services/text_block_parser.dart';
import 'package:eink_launcher/reader/services/doc_identity_service.dart';
import 'package:eink_launcher/reader/services/pagination_cache_service.dart';
import 'package:eink_launcher/services/file_operations_service.dart';
import 'package:eink_launcher/reader/controllers/pdf_reader_session.dart';
import 'package:eink_launcher/reader/services/pdf_document_service.dart';
import 'package:eink_launcher/reader/services/pdf_crop_service.dart';
import 'package:eink_launcher/reader/services/pdf_render_scheduler.dart';
import 'package:eink_launcher/reader/models/toc_entry.dart';
import 'package:pdfrx/pdfrx.dart';

import 'tanach_compatibility_test.dart' as compatibility;

Uint8List epub(String chapter, {String? nav}) {
  final zip = Archive();
  void add(String name, String text) => zip.add(ArchiveFile.string(name, text));
  add(
    'META-INF/container.xml',
    '<container><rootfiles><rootfile full-path="book.opf"/></rootfiles></container>',
  );
  add(
    'book.opf',
    '<package><metadata><title>Probe</title></metadata><manifest><item id="c" href="chapter.xhtml" media-type="application/xhtml+xml"/>${nav == null ? '' : '<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>'}</manifest><spine><itemref idref="c"/></spine></package>',
  );
  add('chapter.xhtml', chapter);
  if (nav != null) add('nav.xhtml', nav);
  return Uint8List.fromList(ZipEncoder().encode(zip));
}

String verse(int n, String text) =>
    '''
<section class="verse" id="v-$n" data-ref="Genesis 1:$n">
<h2>Verse $n</h2><div class="translation" data-edition="primary">$text</div>
<p><a epub:type="noteref" href="#i-$n">Notes</a></p></section>
<aside epub:type="footnote" data-category="index" id="i-$n"><a epub:type="noteref" href="#n-$n">Note</a></aside>
<aside epub:type="footnote" data-category="rishon" id="n-$n" data-source="Rashi"><div class="note-en">Some note</div></aside>''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late TanachSqliteCacheService cache;
  const doc = DocRef(
    id: 'probe',
    path: 'probe.epub',
    title: 'Probe',
    format: DocFormat.epub,
    fileSize: 1,
  );
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('review-probe-');
    cache = TanachSqliteCacheService(cacheDirectory: temp);
  });
  tearDown(() async {
    await temp.delete(recursive: true);
  });

  test('recognized verses without an index retain their text', () {
    final book = EpubParserService.parseBytesSync(
      epub(
        '<html><body><section class="verse" id="v-1" data-ref="Genesis 1:1"><p>Original verse text</p></section></body></html>',
      ),
    );
    expect(
      book.spine.single.blocks.map((b) => b.plainText).join(),
      contains('Original verse text'),
    );
  });

  test('SQLite route retains cross-document verses and notes', () async {
    final source = EpubParserService.parseBytesSync(
      compatibility.fixture(),
      projectStudy: false,
    );
    final book = await cache.import(doc, source, fingerprint: 'a');
    final chapter = await cache.loadChapter(book, 0, const ReaderSettings());
    expect(
      chapter.blocks.map((b) => b.plainText).join(),
      contains('First verse'),
    );
    expect(
      chapter.blocks.map((b) => b.plainText).join(),
      contains('Full English note'),
    );
  });

  test('SQLite TOC retains the target verse', () async {
    final source = EpubParserService.parseBytesSync(
      epub(
        '<html><body>${verse(1, 'First')}${verse(2, 'Second')}</body></html>',
        nav: '<html><body><nav epub:type="toc"><ol><li><a href="chapter.xhtml#v-2">Verse two</a></li></ol></nav></body></html>',
      ),
      projectStudy: false,
    );
    final book = await cache.import(doc, source, fingerprint: 'a');
    final store = BookStoreService.instance;
    await store.init(customFile: File('${temp.path}/library.json'));
    final session = TextReaderSession(
      doc: doc,
      bookStore: store,
      tanachCache: cache,
      bookLoader: (_, _) async => book,
    );
    try {
      await session.open();
      await session.goToToc(session.toc.single);
      expect((session.position as TextReadingPosition).blockId, 'v-2');
    } finally {
      session.dispose();
      store.dispose();
    }
  });

  test(
    'substring search includes infix matches when a prefix also matches',
    () async {
      final source = EpubParserService.parseBytesSync(
        epub(
          '<html><body>${verse(1, 'earth')}${verse(2, 'hearth')}</body></html>',
        ),
        projectStudy: false,
      );
      final book = await cache.import(doc, source, fingerprint: 'a');
      final results = await TanachSqliteSearchService(
        databasePath: book.tanachDatabasePath!,
        settings: const ReaderSettings(),
      ).search(book.spine, 'earth');
      expect(results.matches.length, 2);
    },
  );

  test(
    'chapter loading does not change whole-book character coordinates',
    () async {
      final source = EpubParserService.parseBytesSync(
        epub(
          '<html><body>${verse(1, 'First')}${verse(2, 'Second')}</body></html>',
        ),
        projectStudy: false,
      );
      final book = await cache.import(doc, source, fingerprint: 'a');
      final loaded = await cache.loadChapter(
        book,
        0,
        const ReaderSettings(inlineCommentary: false),
      );
      expect(loaded.characterCount, book.spine[0].characterCount);
    },
  );

  test('partial cut retry clears successful source paths', () async {
    final a = File('${temp.path}/a.txt')..writeAsStringSync('a');
    final b = File('${temp.path}/b.txt');
    final destination = Directory('${temp.path}/dest')..createSync();
    final ops = FileOperationsService()..cut([a.path, b.path]);
    expect(await ops.paste(destination.path), hasLength(1));
    b.writeAsStringSync('b');
    expect(await ops.paste(destination.path), isEmpty);
    expect(ops.hasClipboard, isFalse);
  });

  test(
    'stable annotation anchor follows the annotated text after filtering',
    () {
      final original = EpubParserService.parseBytesSync(
        compatibility.fixture(),
      );
      final index = original.spine[0].blocks.indexWhere(
        (b) => b.plainText == 'Full English note',
      );
      expect(index, greaterThanOrEqualTo(0));
      final filtered = TanachLayoutService.layout(
        original,
        const ReaderSettings(
          commentarySources: ['Rashi on Genesis'],
          commentaryLanguage: 'en',
        ),
      );
      final annotation = Annotation(
        id: 'a',
        docId: doc.id,
        createdAt: DateTime(2026),
        spineIndex: 0,
        blockIndex: index,
        documentPath: original.spine[0].href,
        blockId: original.spine[0].blocks[index].id,
        startOffset: 0,
        endOffset: 'Full English note'.length,
        text: 'Full English note',
      );
      final restored = Annotation.fromJson(
        annotation.withNote('saved').toJson(),
      );
      final matches = [
        for (var i = 0; i < filtered.spine[0].blocks.length; i++)
          if (restored.matchesBlock(filtered.spine[0], 0, i))
            filtered.spine[0].blocks[i].plainText,
      ];
      expect(matches, ['Full English note']);
      final hidden = TanachLayoutService.layout(
        original,
        const ReaderSettings(inlineCommentary: false),
      );
      expect([
        for (var i = 0; i < hidden.spine[0].blocks.length; i++)
          if (restored.matchesBlock(hidden.spine[0], 0, i)) i,
      ], isEmpty);
    },
  );

  test(
    'a commentary search result opens the block containing its match',
    () async {
      final source = EpubParserService.parseBytesSync(
        epub('<html><body>${verse(1, 'First')}</body></html>'),
        projectStudy: false,
      );
      final book = await cache.import(doc, source, fingerprint: 'a');
      final result = await TanachSqliteSearchService(
        databasePath: book.tanachDatabasePath!,
        settings: const ReaderSettings(),
      ).search(book.spine, 'Some note');
      final store = BookStoreService.instance;
      await store.init(customFile: File('${temp.path}/library.json'));
      final session = TextReaderSession(
        doc: doc,
        bookStore: store,
        tanachCache: cache,
        bookLoader: (_, _) async => book,
      );
      try {
        await session.open();
        await session.goToToc(
          TocEntry(title: 'Match', position: result.matches.single.position),
        );
        final position = session.position as TextReadingPosition;
        expect(
          session.blockAt(position.spineIndex, position.blockIndex).plainText,
          contains('Some note'),
        );
      } finally {
        session.dispose();
        store.dispose();
      }
    },
  );

  test('Fit Width preserves the aspect ratio of short pages', () async {
    final store = BookStoreService.instance;
    await store.init(customFile: File('${temp.path}/library.json'));
    final service = CapturePdfService();
    final session = PdfReaderSession(
      doc: doc,
      bookStore: store,
      documentServiceFactory: (_) => service,
    );
    try {
      await session.open();
      await session.applySettings(
        session.settings.copyWith(
          autoCrop: false,
          fitMode: PdfFitMode.fitWidth,
        ),
      );
      await expectLater(
        session.renderCurrentView(const Size(400, 800)),
        throwsStateError,
      );
      expect(service.dimensions, const Size(400, 200));
    } finally {
      session.dispose();
      store.dispose();
    }
  });

  test(
    'same-size TXT edits after the identity sample invalidate pagination',
    () async {
      final prefix = 'x' * (64 * 1024);
      final file = File('${temp.path}/book.txt');
      await file.writeAsString('$prefix\n\nalpha\n\nbeta');
      final beforeId = await DocIdentityService.computeDocId(file.path);
      final before = await const TextBlockParser().parseFile(
        file.path,
        format: DocFormat.txt,
        title: 'Book',
      );
      await file.writeAsString('$prefix\n\nalpha  beta');
      final afterId = await DocIdentityService.computeDocId(file.path);
      final after = await const TextBlockParser().parseFile(
        file.path,
        format: DocFormat.txt,
        title: 'Book',
      );
      final pages = const PaginationCacheService();
      String key(String id, ParsedBook book) => pages.keyFor(
        docId: '$id:${book.contentFingerprint}',
        spineIndex: 0,
        width: 400,
        height: 800,
        settings: const ReaderSettings(),
      );
      expect(
        before.spine.single.blocks.length,
        isNot(after.spine.single.blocks.length),
      );
      expect(key(beforeId, before), isNot(key(afterId, after)));
    },
  );
}

class CapturePdfService extends PdfDocumentService {
  CapturePdfService() : super('fake.pdf');
  Size? dimensions;
  @override
  Future<void> open({PdfPasswordProvider? passwordProvider}) async {}
  @override
  int get pageCount => 1;
  @override
  Future<void> close() async {}
  @override
  Future<List<TocEntry>> loadOutline() async => [];
  @override
  PdfPageInfo pageInfo(int pageIndex) => const PdfPageInfo(
    pageIndex: 0,
    width: 1000,
    height: 500,
    rotation: PdfPageRotation.none,
  );
  @override
  Future<Image> renderPage({
    required int pageIndex,
    required int pixelWidth,
    required int pixelHeight,
    PdfCropRect crop = PdfCropRect.fullPage,
    PdfPageRotation? rotationOverride,
    double maxDimension = 4096,
    PdfRenderRequest? request,
  }) async {
    dimensions = Size(pixelWidth.toDouble(), pixelHeight.toDouble());
    throw StateError('Captured render dimensions');
  }
}

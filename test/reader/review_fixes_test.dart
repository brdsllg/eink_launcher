import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:eink_launcher/reader/controllers/text_reader_session.dart';
import 'package:eink_launcher/reader/models/book_state.dart';
import 'package:eink_launcher/reader/models/content_block.dart';
import 'package:eink_launcher/reader/models/doc_ref.dart';
import 'package:eink_launcher/reader/models/laid_out_page.dart';
import 'package:eink_launcher/reader/models/parsed_book.dart';
import 'package:eink_launcher/reader/models/reader_settings.dart';
import 'package:eink_launcher/reader/models/reading_position.dart';
import 'package:eink_launcher/reader/models/toc_entry.dart';
import 'package:eink_launcher/reader/services/book_store_service.dart';
import 'package:eink_launcher/reader/services/epub_paginator_service.dart';
import 'package:eink_launcher/reader/services/html_block_parser.dart';
import 'package:eink_launcher/reader/services/pagination_cache_service.dart';
import 'package:eink_launcher/reader/services/tanach_sqlite_cache_service.dart';
import 'package:eink_launcher/reader/services/text_block_parser.dart';
import 'package:eink_launcher/services/file_operations_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const doc = DocRef(
  id: 'review',
  path: '/review.epub',
  format: DocFormat.epub,
  title: 'Review',
  fileSize: 10,
);
const block = ContentBlock(
  type: BlockType.paragraph,
  runs: [InlineRun(text: 'chapter text')],
);
TextReadingPosition pos(int chapter) =>
    TextReadingPosition(spineIndex: chapter, blockIndex: 0, charOffset: 0);
LaidOutPage page(int chapter) => LaidOutPage(
  pageIndex: chapter,
  start: pos(chapter),
  end: TextReadingPosition(spineIndex: chapter, blockIndex: 0, charOffset: 12),
  slices: const [
    BlockSlice(
      blockIndex: 0,
      startCharOffset: 0,
      endCharOffset: 12,
      sourceTop: 0,
      height: 30,
    ),
  ],
);
ParsedBook book({bool lazy = false, String? db}) => ParsedBook(
  title: 'Review',
  tanachDatabasePath: db,
  spine: [
    for (var i = 0; i < 4; i++)
      ParsedSpineItem(
        id: '$i',
        href: '$i.xhtml',
        blocks: lazy && i != 0 ? [] : [block],
        isLazy: lazy,
        isLoaded: !lazy || i == 0,
        characterCount: 12,
      ),
  ],
);

class GateCache extends PaginationCacheService {
  GateCache({this.blockThird = false});
  final bool blockThird;
  final entered = Completer<void>();
  final release = Completer<void>();
  int calls = 0;
  @override
  String keyFor({
    required String docId,
    required int spineIndex,
    required double width,
    required double height,
    required ReaderSettings settings,
  }) => '$spineIndex';
  @override
  Future<List<LaidOutPage>?> load(String key) async {
    if (++calls == 3 && blockThird) {
      entered.complete();
      await release.future;
    }
    return [page(int.parse(key))];
  }

  @override
  Future<void> save(String key, List<LaidOutPage> pages) async {}
}

class GateChapter extends TanachSqliteCacheService {
  final entered = Completer<void>();
  final release = Completer<void>();
  @override
  Future<ParsedSpineItem> loadChapter(
    ParsedBook book,
    int index,
    ReaderSettings settings,
  ) async {
    if (!entered.isCompleted) entered.complete();
    await release.future;
    return ParsedSpineItem(
      id: '$index',
      href: '$index.xhtml',
      blocks: [block],
      isLazy: true,
      characterCount: 12,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'ordered lists honor starts, explicit values, reversed and nested lists',
    () {
      final blocks = HtmlBlockParser.parseSync(
        '<ol start="3"><li>A<ol reversed><li>B</li><li>C</li></ol></li><li value="9">D</li><li>E</li></ol>',
      );
      expect(blocks.map((b) => b.listOrdinal), [3, 2, 1, 9, 10]);
      expect(blocks.map((b) => b.nestingLevel), [0, 1, 1, 0, 0]);
    },
  );

  test(
    'successful renames support files, folders and an unchanged name',
    () async {
      final dir = await Directory.systemTemp.createTemp('rename-native-');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/old.txt')..writeAsStringSync('keep');
      final service = FileOperationsService();
      await service.renameEntry(file.path, 'new.txt');
      expect(File('${dir.path}/new.txt').readAsStringSync(), 'keep');
      await service.renameEntry('${dir.path}/new.txt', 'new.txt');
      await Directory('${dir.path}/folder').create();
      await service.renameEntry('${dir.path}/folder', 'renamed');
      expect(await Directory('${dir.path}/renamed').exists(), isTrue);
      await Directory('${dir.path}/other').create();
      await expectLater(
        service.renameEntry('${dir.path}/renamed', 'other'),
        throwsA(isA<FileSystemException>()),
      );
      expect(await Directory('${dir.path}/renamed').exists(), isTrue);
    },
  );
  late Directory temp;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('repo-review-');
    await BookStoreService.instance.init(
      customFile: File('${temp.path}/library.json'),
    );
  });
  tearDown(() async {
    await BookStoreService.instance.flush();
    BookStoreService.instance.dispose();
    await temp.delete(recursive: true);
  });

  for (final kind in ['next', 'toc', 'percent']) {
    test(
      'memory pressure cancels a pending $kind navigation without revival',
      () async {
        final db = File('${temp.path}/fake.sqlite')
          ..writeAsStringSync('exists');
        final chapters = GateChapter();
        final session = TextReaderSession(
          doc: doc,
          paginationCache: GateCache(),
          tanachCache: chapters,
          bookLoader: (_, _) async => book(lazy: true, db: db.path),
        );
        await session.open();
        await session.prepareViewport(const Size(400, 800));
        final operation = switch (kind) {
          'next' => session.nextPage(),
          'toc' => session.goToToc(TocEntry(title: 'Second', position: pos(1))),
          _ => session.goToPercent(0.5),
        };
        await chapters.entered.future;
        session.handleMemoryPressure();
        chapters.release.complete();
        await operation;
        expect(session.book, isNull);
        expect(session.position, pos(0));
        expect(session.isReady, isFalse);
        session.dispose();
      },
    );
  }

  test('Previous must visit the immediately preceding chapter while pagination is incomplete', () async {
    BookStoreService.instance.saveBookState(
      BookState(
        docId: doc.id,
        lastPath: doc.path,
        format: doc.format,
        lastRead: DateTime.now(),
        position: pos(3),
      ),
    );
    final cache = GateCache(blockThird: true);
    final session = TextReaderSession(
      doc: doc,
      paginationCache: cache,
      bookLoader: (_, _) async => book(),
    );
    await session.open();
    final layingOut = session.prepareViewport(const Size(400, 800));
    await cache
        .entered
        .future; // Pages for chapter 3 and chapter 0 are available.
    await session.prevPage();
    final actual = (session.position as TextReadingPosition).spineIndex;
    cache.release.complete();
    await layingOut;
    session.dispose();
    expect(actual, 2, reason: 'chapter 2 must not be skipped');
  });

  test(
    'Memory pressure during a lazy chapter jump must safely cancel navigation',
    () async {
      final db = File('${temp.path}/fake.sqlite')..writeAsStringSync('exists');
      final chapters = GateChapter();
      final session = TextReaderSession(
        doc: doc,
        paginationCache: GateCache(),
        tanachCache: chapters,
        bookLoader: (_, _) async => book(lazy: true, db: db.path),
      );
      await session.open();
      await session.prepareViewport(const Size(400, 800));
      final jumping = session.goToPage(1);
      await chapters.entered.future;
      session.handleMemoryPressure();
      chapters.release.complete();
      Object? failure;
      try {
        await jumping;
      } catch (error) {
        failure = error;
      }
      final position = session.position;
      session.dispose();
      expect(failure, isNull);
      expect(position, pos(0));
    },
  );

  test('Markdown local image must be available to TextPageView', () async {
    final image = File('${temp.path}/image.png')
      ..writeAsBytesSync([137, 80, 78, 71]);
    final source = File('${temp.path}/book.md')
      ..writeAsStringSync('![diagram](image.png)');
    final parsed = await const TextBlockParser().parseFile(
      source.path,
      format: DocFormat.markdown,
      title: 'Book',
    );
    expect(image.existsSync(), isTrue);
    final resource = parsed.spine.single.blocks.single.resourcePath;
    expect(parsed.resources.containsKey(resource), isTrue);
  });

  test('Numbered list preserves the second item number', () {
    final blocks = HtmlBlockParser.parseSync(
      '<ol><li>First</li><li>Second</li></ol>',
    );
    expect(TextBlockLayout.prefixFor(blocks[1], const ReaderSettings()), '2. ');
  });

  test('Rename must not destroy an existing destination file', () async {
    final original = File('${temp.path}/original.txt')
      ..writeAsStringSync('original');
    final target = File('${temp.path}/target.txt')
      ..writeAsStringSync('irreplaceable');
    Object? failure;
    try {
      await FileOperationsService().renameEntry(original.path, 'target.txt');
    } catch (e) {
      failure = e;
    }
    expect(target.readAsStringSync(), 'irreplaceable');
    expect(failure, isNotNull);
  });

  test('Windows-1255 Hebrew vowel marks decode to Hebrew marks', () {
    expect(
      TextBlockParser.decodeText(Uint8List.fromList([0xe0, 0xc0])),
      '\u05d0\u05b0',
    );
  });
}

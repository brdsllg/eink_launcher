import 'dart:async';
import 'dart:io';

import 'package:eink_launcher/reader/controllers/text_reader_session.dart';
import 'package:eink_launcher/reader/models/content_block.dart';
import 'package:eink_launcher/reader/models/doc_ref.dart';
import 'package:eink_launcher/reader/models/laid_out_page.dart';
import 'package:eink_launcher/reader/models/parsed_book.dart';
import 'package:eink_launcher/reader/models/reading_position.dart';
import 'package:eink_launcher/reader/models/toc_entry.dart';
import 'package:eink_launcher/reader/services/book_store_service.dart';
import 'package:eink_launcher/reader/services/pagination_cache_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late TextReaderSession session;

  const doc = DocRef(
    id: 'epub-session-test',
    path: '/books/test.epub',
    format: DocFormat.epub,
    title: 'Test book',
    fileSize: 100,
  );

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('text-session-');
    await BookStoreService.instance.init(
      customFile: File('${directory.path}/library.json'),
    );
    session = TextReaderSession(
      doc: doc,
      bookStore: BookStoreService.instance,
      paginationCache: PaginationCacheService(
        cacheDirectory: Directory('${directory.path}/pages'),
      ),
      bookLoader: (_, _) async => _book,
    );
  });

  tearDown(() async {
    session.dispose();
    BookStoreService.instance.dispose();
    await directory.delete(recursive: true);
  });

  test('opens, paginates, navigates, and persists logical positions', () async {
    await session.open();
    expect(session.isReady, isTrue);
    expect(session.pageCount, 0);

    await session.prepareViewport(const Size(220, 180));
    expect(session.pageCount, greaterThan(1));
    final first = session.position;
    await session.nextPage();

    expect(session.currentPage, 1);
    expect(session.position, isNot(first));
    expect(
      BookStoreService.instance.getBookState(doc.id)?.position,
      session.position,
    );
  });

  test('TOC and percent jumps resolve back to laid-out pages', () async {
    await session.open();
    await session.prepareViewport(const Size(220, 180));

    await session.goToToc(_book.tableOfContents.last);
    expect((session.position as TextReadingPosition).spineIndex, 1);

    await session.goToPercent(0);
    expect(session.currentPage, 0);
    expect(session.percent, closeTo(0, 0.01));
  });

  test('typography changes repaginate without losing the chapter', () async {
    await session.open();
    await session.prepareViewport(const Size(220, 180));
    await session.goToToc(_book.tableOfContents.last);

    await session.applySettings(
      session.settings.copyWith(fontSizeStep: 6, marginStep: 2),
    );

    expect(session.settings.fontSizeStep, 6);
    expect((session.position as TextReadingPosition).spineIndex, 1);
    expect(
      BookStoreService.instance
          .getBookState(doc.id)
          ?.settingsOverride
          ?.marginStep,
      2,
    );
  });

  test('suspend and resume retain parsed content and pages', () async {
    await session.open();
    await session.prepareViewport(const Size(220, 180));
    final pageCount = session.pageCount;

    session.suspend();
    expect(session.isSuspended, isTrue);
    await session.resume();

    expect(session.isReady, isTrue);
    expect(session.pageCount, pageCount);
  });

  test(
    'retains a TOC target requested during progressive pagination',
    () async {
      session.dispose();
      final cache = _BlockingPaginationCache(
        cacheDirectory: Directory('${directory.path}/blocked-pages'),
      );
      session = TextReaderSession(
        doc: doc,
        bookStore: BookStoreService.instance,
        paginationCache: cache,
        bookLoader: (_, _) async => _book,
      );
      await session.open();

      final initialPagination = session.prepareViewport(const Size(220, 180));
      await cache.secondLoadStarted.future;
      expect(
        (session.currentLaidOutPage!.start).spineIndex,
        0,
        reason: 'the restored chapter is paginated first',
      );

      await session.goToToc(_book.tableOfContents.last);
      await _waitUntil(() {
        return !session.isPaginating &&
            (session.position as TextReadingPosition).spineIndex == 1;
      });
      cache.releaseSecondLoad.complete();
      await initialPagination;

      expect((session.position as TextReadingPosition).spineIndex, 1);
      expect(session.currentLaidOutPage!.start.spineIndex, 1);
    },
  );

  test('published pages remain in logical spine order', () async {
    await session.open();
    await session.prepareViewport(const Size(220, 180));

    var previousSpine = -1;
    for (var page = 0; page < session.pageCount; page++) {
      await session.goToPage(page);
      final spine = session.currentLaidOutPage!.start.spineIndex;
      expect(spine, greaterThanOrEqualTo(previousSpine));
      previousSpine = spine;
    }
  });

  test('viewport resize keeps the previous logical anchor visible', () async {
    await session.open();
    await session.prepareViewport(const Size(220, 180));
    await session.goToPage(
      (session.pageCount ~/ 3).clamp(1, session.pageCount - 1),
    );
    final anchor = session.position as TextReadingPosition;

    final stopwatch = Stopwatch()..start();
    await session.prepareViewport(const Size(360, 220));
    stopwatch.stop();

    final resizedPage = session.currentLaidOutPage!;
    expect(_compare(resizedPage.start, anchor), lessThanOrEqualTo(0));
    expect(_compare(anchor, resizedPage.end), lessThanOrEqualTo(0));
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));
  });
}

int _compare(TextReadingPosition a, TextReadingPosition b) {
  final spine = a.spineIndex.compareTo(b.spineIndex);
  if (spine != 0) return spine;
  final block = a.blockIndex.compareTo(b.blockIndex);
  if (block != 0) return block;
  return a.charOffset.compareTo(b.charOffset);
}

Future<void> _waitUntil(bool Function() condition) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  fail('Timed out waiting for asynchronous pagination.');
}

class _BlockingPaginationCache extends PaginationCacheService {
  final Completer<void> secondLoadStarted = Completer<void>();
  final Completer<void> releaseSecondLoad = Completer<void>();
  int _loadCount = 0;

  _BlockingPaginationCache({required super.cacheDirectory});

  @override
  Future<List<LaidOutPage>?> load(String key) async {
    _loadCount++;
    if (_loadCount == 2) {
      secondLoadStarted.complete();
      await releaseSecondLoad.future;
    }
    return null;
  }

  @override
  Future<void> save(String key, List<LaidOutPage> pages) async {}
}

final _longText = List.filled(
  18,
  'A bilingual paragraph with enough words to wrap across several lines. ',
).join();

final _book = ParsedBook(
  title: 'Test book',
  spine: [
    ParsedSpineItem(
      id: 'one',
      href: 'one.xhtml',
      blocks: [
        const ContentBlock(
          type: BlockType.heading1,
          runs: [InlineRun(text: 'One')],
        ),
        ContentBlock(
          type: BlockType.paragraph,
          runs: [InlineRun(text: _longText)],
        ),
      ],
    ),
    ParsedSpineItem(
      id: 'two',
      href: 'two.xhtml',
      blocks: [
        const ContentBlock(
          type: BlockType.heading1,
          runs: [InlineRun(text: 'שתיים')],
          direction: BlockTextDirection.rtl,
        ),
        ContentBlock(
          type: BlockType.paragraph,
          runs: [InlineRun(text: _longText)],
        ),
      ],
    ),
  ],
  tableOfContents: const [
    TocEntry(
      title: 'One',
      position: TextReadingPosition(
        spineIndex: 0,
        blockIndex: 0,
        charOffset: 0,
      ),
    ),
    TocEntry(
      title: 'Two',
      position: TextReadingPosition(
        spineIndex: 1,
        blockIndex: 0,
        charOffset: 0,
      ),
    ),
  ],
);

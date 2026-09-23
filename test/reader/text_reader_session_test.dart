import 'dart:async';
import 'dart:io';

import 'package:eink_launcher/reader/controllers/text_reader_session.dart';
import 'package:eink_launcher/reader/models/book_state.dart';
import 'package:eink_launcher/reader/models/content_block.dart';
import 'package:eink_launcher/reader/models/doc_ref.dart';
import 'package:eink_launcher/reader/models/laid_out_page.dart';
import 'package:eink_launcher/reader/models/parsed_book.dart';
import 'package:eink_launcher/reader/models/reading_position.dart';
import 'package:eink_launcher/reader/models/reader_settings.dart';
import 'package:eink_launcher/reader/models/toc_entry.dart';
import 'package:eink_launcher/reader/services/book_store_service.dart';
import 'package:eink_launcher/reader/services/epub_paginator_service.dart';
import 'package:eink_launcher/reader/services/pagination_cache_service.dart';
import 'package:eink_launcher/reader/services/text_search_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late TextReaderSession session;
  late _TrackingPaginationCache cache;

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
    cache = _TrackingPaginationCache(
      cacheDirectory: Directory('${directory.path}/pages'),
    );
    session = TextReaderSession(
      doc: doc,
      bookStore: BookStoreService.instance,
      paginationCache: cache,
      bookLoader: (_, _) async => _book,
    );
  });

  tearDown(() async {
    session.dispose();
    BookStoreService.instance.dispose();
    await cache.drain();
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
    'memory pressure releases text while retaining position and metadata',
    () async {
      await session.open();
      await session.prepareViewport(const Size(220, 180));
      await session.goToPage(2);
      await session.addBookmark('Retained');
      final position = session.position;
      final percent = session.percent;
      final pageCount = session.pageCount;
      final toc = session.toc;
      session.handleMemoryPressure();
      session.handleMemoryPressure();
      expect(session.book, isNull);
      expect(session.currentLaidOutPage, isNull);
      expect(session.position, position);
      expect(session.percent, percent);
      expect(session.pageCount, pageCount);
      expect(session.toc, toc);
      await session.resume();
      await _waitUntil(() => !session.isPaginating);
      expect(session.isReady, isTrue);
      expect(session.position, position);
      expect(session.bookmarks.single.label, 'Retained');
    },
  );

  test(
    'a failed open cannot replace saved state, and reopening can recover',
    () async {
      final saved = BookState(
        docId: doc.id,
        lastPath: doc.path,
        format: doc.format,
        lastRead: DateTime(2026),
        position: const TextReadingPosition(
          spineIndex: 1,
          blockIndex: 1,
          charOffset: 10,
        ),
        percent: 0.5,
      );
      BookStoreService.instance.saveBookState(saved);
      var fail = true;
      session.dispose();
      session = TextReaderSession(
        doc: doc,
        paginationCache: cache,
        bookLoader: (_, _) async {
          if (fail) throw const FormatException('Malformed book');
          return _book;
        },
      );
      await session.open();
      expect(session.isReady, isFalse);
      session.suspend();
      expect(BookStoreService.instance.getBookState(doc.id), same(saved));
      fail = false;
      await session.resume();
      expect(session.error, isNull);
      expect(session.position, saved.position);
    },
  );

  test(
    'late loading cannot revive a suspended or disposed text session',
    () async {
      final load = Completer<ParsedBook>();
      session.dispose();
      session = TextReaderSession(doc: doc, bookLoader: (_, _) => load.future);
      final opening = session.open();
      session.handleMemoryPressure();
      load.complete(_book);
      await opening;
      expect(session.isReady, isFalse);
      expect(session.book, isNull);
      final lateLoad = Completer<ParsedBook>();
      final other = TextReaderSession(
        doc: doc,
        bookLoader: (_, _) => lateLoad.future,
      );
      final pending = other.open();
      other.dispose();
      lateLoad.complete(_book);
      await pending;
      expect(other.book, isNull);
    },
  );

  test('background pagination failure is contained and recoverable', () async {
    var fail = true;
    session.dispose();
    session = TextReaderSession(
      doc: doc,
      bookLoader: (_, _) async => _book,
      paginationCache: _FailingCache(() => fail),
    );
    await session.open();
    session.updateViewport(const Size(220, 180));
    await _waitUntil(() => session.error != null);
    expect(session.isPaginating, isFalse);
    expect(session.isReady, isFalse);
    fail = false;
    session.suspend();
    await session.resume();
    await _waitUntil(() => !session.isPaginating);
    expect(session.error, isNull);
    expect(session.pageCount, greaterThan(1));
  });

  test('bookmarks are added, persisted across sessions, and removed', () async {
    await session.open();
    await session.prepareViewport(const Size(220, 180));
    await session.goToToc(_book.tableOfContents.last);

    await session.addBookmark('Chapter two');
    expect(session.bookmarks, hasLength(1));
    expect(session.bookmarks.single.label, 'Chapter two');
    expect(
      (session.bookmarks.single.position as TextReadingPosition).spineIndex,
      1,
    );

    final saved = BookStoreService.instance.getBookState(doc.id);
    expect(saved?.bookmarks, hasLength(1));

    // A freshly created session for the same doc (simulating an app
    // restart) restores the bookmark from library.json.
    final reopened = TextReaderSession(
      doc: doc,
      bookStore: BookStoreService.instance,
      paginationCache: PaginationCacheService(
        cacheDirectory: Directory('${directory.path}/pages'),
      ),
      bookLoader: (_, _) async => _book,
    );
    addTearDown(reopened.dispose);
    await reopened.open();
    expect(reopened.bookmarks, hasLength(1));
    expect(reopened.bookmarks.single.label, 'Chapter two');

    await reopened.removeBookmark(reopened.bookmarks.single.id);
    expect(reopened.bookmarks, isEmpty);
    expect(BookStoreService.instance.getBookState(doc.id)?.bookmarks, isEmpty);
  });

  test(
    'openLink to another spine chapter produces a laid-out page immediately',
    () async {
      // Regression: synchronous _goToPosition called by the old openLink left
      // the page blank (grey) when the target chapter had not yet been paginated.
      // The fix makes openLink async and calls _ensureChapterPages before
      // navigating, so content is ready by the time the call returns.
      await session.open();
      await session.prepareViewport(const Size(220, 180));

      // Start on chapter one (spineIndex 0).
      expect((session.position as TextReadingPosition).spineIndex, 0);

      // Follow a link to two.xhtml (spineIndex 1). No anchor needed — block 0.
      final opened = await session.openLink('two.xhtml');
      expect(opened, isTrue);
      expect((session.position as TextReadingPosition).spineIndex, 1);
      // The page must be laid out — not null/grey — and must match the position.
      final page = session.currentLaidOutPage;
      expect(page, isNotNull);
      expect(page!.start.spineIndex, 1);
    },
  );

  test(
    'openLink with a fragment anchor navigates to the correct block',
    () async {
      // Build a book where chapter two has a named anchor on block 1.
      final bookWithAnchor = ParsedBook(
        title: 'Anchor test',
        spine: [
          ParsedSpineItem(
            id: 'one',
            href: 'one.xhtml',
            blocks: _book.spine[0].blocks,
          ),
          ParsedSpineItem(
            id: 'two',
            href: 'two.xhtml',
            blocks: _book.spine[1].blocks,
            anchors: const {'para': 1},
          ),
        ],
        tableOfContents: _book.tableOfContents,
      );
      session.dispose();
      session = TextReaderSession(
        doc: doc,
        bookStore: BookStoreService.instance,
        paginationCache: cache,
        bookLoader: (_, _) async => bookWithAnchor,
      );
      await session.open();
      await session.prepareViewport(const Size(220, 180));

      final opened = await session.openLink('two.xhtml#para');
      expect(opened, isTrue);
      final pos = session.position as TextReadingPosition;
      expect(pos.spineIndex, 1);
      expect(pos.blockIndex, 1);
    },
  );

  test('openLink returns false for unknown href', () async {
    await session.open();
    await session.prepareViewport(const Size(220, 180));
    final opened = await session.openLink('missing.xhtml');
    expect(opened, isFalse);
    // Position must be unchanged.
    expect((session.position as TextReadingPosition).spineIndex, 0);
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

      // A jump requested while the next chapter is still mid-flight keeps the
      // pages that are already published (no blank screen) and joins the layout
      // that is already running instead of starting a second one.
      final jump = session.goToToc(_book.tableOfContents.last);
      expect(session.currentLaidOutPage, isNotNull);
      expect(cache.loadCount, 2, reason: 'the in-flight chapter is reused');

      cache.releaseSecondLoad.complete();
      await initialPagination;
      await jump;

      expect((session.position as TextReadingPosition).spineIndex, 1);
      expect(session.currentLaidOutPage!.start.spineIndex, 1);
    },
  );

  test(
    'page turns keep working while the rest of the book paginates',
    () async {
      session.dispose();
      final cache = _GatedCache(
        cacheDirectory: Directory('${directory.path}/turns'),
        blockFrom: 2,
      );
      final paginator = _CountingPaginator();
      session = TextReaderSession(
        doc: doc,
        bookStore: BookStoreService.instance,
        paginationCache: cache,
        paginator: paginator,
        bookLoader: (_, _) async => _readingBook,
      );
      await session.open();

      unawaited(session.prepareViewport(const Size(220, 180)));
      await cache.entered.future;
      expect(session.isPaginating, isTrue);
      expect(session.currentLaidOutPage!.start.spineIndex, 0);

      // Turns have to work while the remaining chapters are still being laid
      // out: nothing waits for a whole chapter any more.
      final first = session.currentPage;
      await session.nextPage();
      await session.nextPage();

      expect(session.currentPage, first + 2);
      expect((session.position as TextReadingPosition).spineIndex, 0);
      expect(
        paginator.calls[0],
        1,
        reason: 'a finished chapter is never laid out twice',
      );

      cache.release.complete();
      await _waitUntil(() => !session.isPaginating);
      expect(paginator.calls.keys, containsAll([0, 1, 2, 3]));
      expect(session.pageCount, greaterThan(3));
    },
  );

  test(
    'a page turn waiting for a chapter joins the layout already running',
    () async {
      session.dispose();
      final cache = _GatedCache(
        cacheDirectory: Directory('${directory.path}/join'),
        blockFrom: 1,
      );
      final paginator = _CountingPaginator();
      session = TextReaderSession(
        doc: doc,
        bookStore: BookStoreService.instance,
        paginationCache: cache,
        paginator: paginator,
        bookLoader: (_, _) async => _readingBook,
      );
      await session.open();

      unawaited(session.prepareViewport(const Size(220, 180)));
      await cache.entered.future;
      expect(session.currentLaidOutPage, isNull, reason: 'no page exists yet');

      final turn = session.nextPage();
      // The turn must join the layout already running for that chapter instead
      // of asking the cache (and the paginator) for that chapter a second time.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(cache.loadCount, 1, reason: 'the running layout is reused');
      cache.release.complete();
      await turn;

      expect(
        paginator.calls[0],
        1,
        reason: 'the turn reused the layout the background pass had started',
      );
      expect(session.currentPage, 1);
      expect(session.currentLaidOutPage!.start.spineIndex, 0);
      await _waitUntil(() => !session.isPaginating);
    },
  );

  test('typography changes do not hold page turns for the whole book', () async {
    session.dispose();
    final cache = _GatedCache(
      cacheDirectory: Directory('${directory.path}/settings'),
    );
    session = TextReaderSession(
      doc: doc,
      bookStore: BookStoreService.instance,
      paginationCache: cache,
      bookLoader: (_, _) async => _readingBook,
    );
    cache.blockFrom = null;
    await session.open();
    await session.prepareViewport(const Size(220, 180));

    // Keep the second chapter of the new layout unfinished so the reader is
    // provably turning pages while the background pass is still running.
    cache.blockFrom = cache.loadCount + 2;
    await session.applySettings(session.settings.copyWith(fontSizeStep: 6));

    expect(session.settings.fontSizeStep, 6);
    expect(session.currentLaidOutPage, isNotNull);
    expect(session.isPaginating, isTrue);
    final before = session.currentPage;
    await session.nextPage();
    expect(session.currentPage, before + 1);

    cache.release.complete();
    await _waitUntil(() => !session.isPaginating);
  });

  test('no page is shown before the reader\'s own page is laid out', () async {
    session.dispose();
    final position = const TextReadingPosition(
      spineIndex: 0,
      blockIndex: 580,
      charOffset: 0,
    );
    BookStoreService.instance.saveBookState(
      BookState(
        docId: doc.id,
        lastPath: doc.path,
        format: doc.format,
        lastRead: DateTime.now(),
        position: position,
      ),
    );
    session = TextReaderSession(
      doc: doc,
      bookStore: BookStoreService.instance,
      paginationCache: cache,
      bookLoader: (_, _) async => _deepChapterBook,
    );
    await session.open();
    unawaited(session.prepareViewport(const Size(220, 180)));

    // While the chapter is still being measured, every page that exists is
    // before the reading position. Showing one of them would look like a jump
    // backwards and would persist that wrong position on the next turn.
    var partialPages = 0;
    for (var attempt = 0; attempt < 8000; attempt++) {
      if (session.currentLaidOutPage != null) break;
      if (session.pageCount > partialPages) partialPages = session.pageCount;
      await Future<void>.delayed(Duration.zero);
    }
    expect(
      partialPages,
      greaterThan(0),
      reason: 'pages were published before the reader\'s own page',
    );

    await _waitUntil(() => session.currentLaidOutPage != null);
    final page = session.currentLaidOutPage!;
    expect(_compare(page.start, position), lessThanOrEqualTo(0));
    expect(_compare(position, page.end), lessThan(0));
    expect(session.position, position);

    await _waitUntil(() => !session.isPaginating);
    expect(_compare(session.position as TextReadingPosition, position), 0);
  });

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

  test(
    'search targets survive pagination, typography and bookmark reload',
    () async {
      await session.open();
      final results = await const TextSearchService().search(
        session.book!.spine,
        'words',
      );
      final match = results.matches.last;
      final entry = TocEntry(
        title: match.chapterTitle,
        position: match.position,
      );
      // Search is available even before the book has any laid-out pages.
      await session.goToToc(entry);
      await session.prepareViewport(const Size(220, 180));
      expect(session.position, match.position);
      _expectVisible(session, match.position);

      await session.goToPage(0);
      await session.goToToc(entry);
      expect(session.position, match.position);
      await session.addBookmark('Search result');
      await session.applySettings(session.settings.copyWith(fontSizeStep: 6));
      _expectVisible(session, match.position);
      await BookStoreService.instance.flush();
      BookStoreService.instance.dispose();
      await BookStoreService.instance.init(
        customFile: File('${directory.path}/library.json'),
      );
      session.dispose();
      session = TextReaderSession(
        doc: doc,
        paginationCache: cache,
        bookLoader: (_, _) async => _book,
      );
      await session.open();
      await session.prepareViewport(const Size(360, 220));
      expect(session.position, match.position);
      await session.goToPage(0);
      await session.goToToc(
        TocEntry(
          title: 'Bookmark',
          position: session.bookmarks.single.position,
        ),
      );
      expect(session.position, match.position);
      _expectVisible(session, match.position);
    },
  );
}

void _expectVisible(TextReaderSession session, TextReadingPosition target) {
  final page = session.currentLaidOutPage!;
  expect(_compare(page.start, target), lessThanOrEqualTo(0));
  expect(_compare(target, page.end), lessThan(0));
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

  int get loadCount => _loadCount;

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

// Every load misses, and calls at or after [blockFrom] stay in flight until
// [release] completes. Used to freeze background pagination at a known point.
class _GatedCache extends PaginationCacheService {
  _GatedCache({required super.cacheDirectory, this.blockFrom});

  int? blockFrom;
  final Completer<void> entered = Completer<void>();
  final Completer<void> release = Completer<void>();
  int loadCount = 0;

  @override
  Future<List<LaidOutPage>?> load(String key) async {
    loadCount++;
    final gate = blockFrom;
    if (gate != null && loadCount >= gate) {
      if (!entered.isCompleted) entered.complete();
      await release.future;
    }
    return null;
  }

  @override
  Future<void> save(String key, List<LaidOutPage> pages) async {}
}

// Counts how often a chapter is laid out (through either entry point), so
// duplicated work shows up as a failure instead of a slow device.
class _CountingPaginator extends EpubPaginatorService {
  final Map<int, int> calls = {};

  void _count(int spineIndex) =>
      calls.update(spineIndex, (value) => value + 1, ifAbsent: () => 1);

  @override
  List<LaidOutPage> paginateSpine({
    required int spineIndex,
    required List<ContentBlock> blocks,
    required Size contentSize,
    required ReaderSettings settings,
    Map<String, Size> imageSizes = const {},
  }) {
    _count(spineIndex);
    return super.paginateSpine(
      spineIndex: spineIndex,
      blocks: blocks,
      contentSize: contentSize,
      settings: settings,
      imageSizes: imageSizes,
    );
  }

  @override
  Future<List<LaidOutPage>> paginateSpineResponsive({
    required int spineIndex,
    required List<ContentBlock> blocks,
    required Size contentSize,
    required ReaderSettings settings,
    required bool Function() isCancelled,
    required void Function(List<LaidOutPage>) onProgress,
    Map<String, Size> imageSizes = const {},
    Duration yieldBudget = EpubPaginatorService.defaultYieldBudget,
  }) {
    _count(spineIndex);
    return super.paginateSpineResponsive(
      spineIndex: spineIndex,
      blocks: blocks,
      contentSize: contentSize,
      settings: settings,
      isCancelled: isCancelled,
      onProgress: onProgress,
      imageSizes: imageSizes,
      yieldBudget: yieldBudget,
    );
  }
}

// Production saves intentionally run in the background. Wait for those writes
// before removing the fixture directory, which Windows cannot delete while open.
class _TrackingPaginationCache extends PaginationCacheService {
  final _writes = <Future<void>>[];

  _TrackingPaginationCache({required super.cacheDirectory});

  @override
  Future<void> save(String key, List<LaidOutPage> pages) {
    final write = super.save(key, pages);
    _writes.add(write);
    return write;
  }

  Future<void> drain() async {
    await Future.wait(_writes);
  }
}

class _FailingCache extends PaginationCacheService {
  final bool Function() shouldFail;
  _FailingCache(this.shouldFail);

  @override
  Future<List<LaidOutPage>?> load(String key) async {
    if (shouldFail()) throw StateError('Injected pagination failure');
    return null;
  }

  @override
  Future<void> save(String key, List<LaidOutPage> pages) async {}
}

final _longText = List.filled(
  18,
  'A bilingual paragraph with enough words to wrap across several lines. ',
).join();

/// Four chapters with several pages each, for tests that need a page turn to
/// cross into text the background pass has not reached yet.
final _readingBook = ParsedBook(
  title: 'Reading book',
  spine: [
    for (var chapter = 0; chapter < 4; chapter++)
      ParsedSpineItem(
        id: 'chapter-$chapter',
        href: 'chapter-$chapter.xhtml',
        blocks: [
          ContentBlock(
            type: BlockType.heading1,
            runs: [InlineRun(text: 'Chapter $chapter')],
          ),
          for (var paragraph = 0; paragraph < 4; paragraph++)
            ContentBlock(
              type: BlockType.paragraph,
              runs: [InlineRun(text: _longText)],
            ),
        ],
      ),
  ],
);

/// A single chapter with enough blocks for the reading position to sit far
/// behind the layout frontier while the chapter is still being measured.
final _deepChapterBook = ParsedBook(
  title: 'Deep chapter',
  spine: [
    ParsedSpineItem(
      id: 'deep',
      href: 'deep.xhtml',
      blocks: [
        for (var block = 0; block < 600; block++)
          ContentBlock(
            type: BlockType.paragraph,
            runs: [InlineRun(text: 'Paragraph number $block.')],
          ),
      ],
    ),
  ],
);

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

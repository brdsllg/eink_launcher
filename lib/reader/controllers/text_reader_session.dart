import 'dart:async';
import 'dart:isolate';
import 'dart:io';

import '../services/tanach_layout_service.dart';
import '../services/tanach_sqlite_cache_service.dart';
import '../services/tanach_sqlite_search_service.dart';
import '../services/text_search_service.dart';

import 'dart:ui';

import '../models/book_state.dart';
import '../models/bookmark.dart';
import '../models/content_block.dart';
import '../models/doc_ref.dart';
import '../models/laid_out_page.dart';
import '../models/parsed_book.dart';
import '../models/reader_settings.dart';
import '../models/reading_position.dart';
import '../models/toc_entry.dart';
import '../services/book_store_service.dart';
import '../services/epub_paginator_service.dart';
import '../services/parsed_epub_cache_service.dart';
import '../services/pagination_cache_service.dart';
import '../services/reader_error_service.dart';
import '../services/text_block_parser.dart';
import 'reader_session.dart';

typedef TextBookLoader = Future<ParsedBook> Function(
  DocRef doc,
  bool honorPublisherCss,
);

class TextReaderSession extends ReaderSession {
  @override
  final DocRef doc;

  final BookStoreService _bookStore;
  final EpubPaginatorService _paginator;
  final PaginationCacheService _paginationCache;
  final TextBookLoader _bookLoader;
  final TanachSqliteCacheService _tanachCache;

  ParsedBook? _book;
  String? _pinnedDatabase;
  Future<void>? _recoveringDatabase;

  void _pinDatabase(String? path) {
    if (_pinnedDatabase == path) return;
    if (_pinnedDatabase != null) {
      TanachSqliteCacheService.release(_pinnedDatabase!);
    }
    _pinnedDatabase = path;
    if (path != null) TanachSqliteCacheService.retain(path);
  }

  Future<void> _ensureDatabase() async {
    final path = _book?.tanachDatabasePath;
    if (path == null || await File(path).exists()) return;
    await (_recoveringDatabase ??= _recoverDatabase());
  }

  Future<void> _recoverDatabase() async {
    try {
      // The cache is disposable; reconstruct it from the original EPUB if the
      // operating system removed it while the reader was suspended.
      await _bookLoader(doc, _settings.honorPublisherCss);
    } finally {
      _recoveringDatabase = null;
    }
  }

  int _settingsGeneration = 0;
  ReaderSettings _settings = const ReaderSettings();
  TextReadingPosition _position = const TextReadingPosition(
    spineIndex: 0,
    blockIndex: 0,
    charOffset: 0,
  );
  List<LaidOutPage> _pages = const [];
  final Map<int, List<LaidOutPage>> _chapterPages = {};
  final Set<int> _completedChapters = {};
  final Map<String, Size> _imageSizes = {};
  Size? imageSizeFor(String? path) => _imageSizes[path];

  Future<void> _prepareImages(ParsedBook book, int lifecycle) async {
    final settingsGeneration = _settingsGeneration;
    final sizes = <String, Size>{};
    final paths = book.spine
        .expand((s) => s.blocks)
        .where((b) => b.type == BlockType.image)
        .map((b) => b.resourcePath)
        .whereType<String>()
        .toSet();
    for (final path in paths) {
      final bytes = book.resources[path];
      if (bytes == null) continue;
      ImmutableBuffer? buffer;
      ImageDescriptor? descriptor;
      try {
        buffer = await ImmutableBuffer.fromUint8List(bytes);
        descriptor = await ImageDescriptor.encoded(buffer);
        sizes[path] = Size(
          descriptor.width.toDouble(),
          descriptor.height.toDouble(),
        );
      } catch (_) {
        // Unsupported images use the alternate-text layout.
      } finally {
        descriptor?.dispose();
        buffer?.dispose();
      }
      if (_disposed || lifecycle != _lifecycleGeneration) return;
    }
    if (_disposed ||
        lifecycle != _lifecycleGeneration ||
        settingsGeneration != _settingsGeneration) {
      return;
    }
    _imageSizes
      ..clear()
      ..addAll(sizes);
  }

  Size? _viewport;
  Size? _contentSize;
  int _currentPage = 0;
  int _paginationGeneration = 0;
  int _lifecycleGeneration = 0;
  bool _disposed = false;
  bool _hasLoadedBook = false;
  double _savedPercent = 0;
  int _retainedPageCount = 0;
  List<TocEntry> _retainedToc = const [];
  List<Bookmark> _bookmarks = const [];
  bool _isReady = false;
  bool _isSuspended = false;
  bool _isPaginating = false;
  String? _error;
  final List<int> _chapterUseOrder = [];
  static const int _maxResidentTanachChapters = 3;

  /// In-flight chapter layout per spine index for the current pagination
  /// generation. Requests sharing a chapter share one layout, so a page turn
  /// can never start a second, duplicate run of the chapter it is waiting for.
  final Map<int, _ChapterLayout> _layouts = {};

  /// Chapters whose layout failed in the current pagination generation.
  final Set<int> _failedChapters = {};

  /// Upper bound on "wait for the next batch" retries inside one page turn.
  static const int _maxTurnAttempts = 64;

  TextReaderSession({
    required this.doc,
    BookStoreService? bookStore,
    EpubPaginatorService? paginator,
    PaginationCacheService? paginationCache,
    TextBookLoader? bookLoader,
    TanachSqliteCacheService? tanachCache,
  }) : _bookStore = bookStore ?? BookStoreService.instance,
       _paginator = paginator ?? const EpubPaginatorService(),
       _paginationCache = paginationCache ?? const PaginationCacheService(),
       _tanachCache = tanachCache ?? const TanachSqliteCacheService(),
       _bookLoader = bookLoader ?? _loadBook;

  static Future<ParsedBook> _loadBook(DocRef doc, bool honorPublisherCss) {
    return switch (doc.format) {
      DocFormat.epub => const ParsedEpubCacheService().load(
        doc,
        honorPublisherCss,
      ),
      DocFormat.txt || DocFormat.markdown => const TextBlockParser().parseFile(
        doc.path,
        format: doc.format,
        title: doc.title,
        honorPublisherCss: honorPublisherCss,
      ),
      DocFormat.pdf => throw UnsupportedError('PDF uses PdfReaderSession.'),
    };
  }

  // Keep isolate closures outside the session so they cannot capture its
  // listeners, platform handles, or other unsendable UI state.
  static Future<ParsedBook> _project(
    ParsedBook source,
    ReaderSettings settings,
  ) => Isolate.run(() => TanachLayoutService.layout(source, settings));

  @override
  bool get isReady => _isReady;

  @override
  bool get isSuspended => _isSuspended;

  bool get isPaginating => _isPaginating;

  @override
  String? get error => _error;

  @override
  int get pageCount => _book == null ? _retainedPageCount : _pages.length;

  @override
  int get currentPage => _currentPage;

  @override
  double get percent {
    final book = _book;
    if (book == null) return _savedPercent;
    if (book.characterCount == 0) return 0;
    var read = 0;
    if (_position.spineIndex > 0) {
      read = book.cumulativeCharacterCounts[_position.spineIndex - 1];
    }
    final spine = book.spine[_position.spineIndex];
    var within = 0;
    for (var i = 0; i < _position.blockIndex && i < spine.blocks.length; i++) {
      within += spine.blocks[i].characterCount;
    }
    within += _position.charOffset;
    final displayed = spine.blocks.fold<int>(
      0,
      (sum, block) => sum + block.characterCount,
    );
    read += spine.isLazy && displayed > 0
        ? (within * spine.characterCount / displayed).round()
        : within;
    return (read / book.characterCount).clamp(0.0, 1.0);
  }

  @override
  ReadingPosition get position => _anchoredPosition(_position);

  @override
  List<TocEntry> get toc => _book?.tableOfContents ?? _retainedToc;

  @override
  ReaderSettings get settings => _settings;

  @override
  List<Bookmark> get bookmarks => _bookmarks;

  ParsedBook? get book => _book;

  TextSearchService get searchService {
    final book = _book;
    final path = book?.tanachDatabasePath;
    return path == null
        ? const TextSearchService()
        : TanachSqliteSearchService(
            databasePath: path,
            settings: _settings,
            ensureDatabase: _ensureDatabase,
          );
  }

  /// The page to render, or null while the page holding [position] has not been
  /// laid out yet.
  ///
  /// Chapters publish their pages while they are still being measured. Falling
  /// back to the last page available would show text from *before* the reading
  /// position and, on the next turn, move the saved position backwards, so the
  /// UI keeps showing its "laying out pages" state until the reader's own page
  /// exists.
  LaidOutPage? get currentLaidOutPage {
    if (_pages.isEmpty) return null;
    final chapter = _position.spineIndex;
    if (!_completedChapters.contains(chapter)) {
      final pages = _chapterPages[chapter];
      if (pages != null &&
          pages.isNotEmpty &&
          _comparePosition(_position, pages.last.end) > 0) {
        return null;
      }
    }
    return _pages[_currentPage.clamp(0, _pages.length - 1)];
  }

  ContentBlock blockAt(int spineIndex, int blockIndex) =>
      _book!.spine[spineIndex].blocks[blockIndex];

  @override
  Future<void> open() async {
    if (_disposed) return;
    final generation = ++_lifecycleGeneration;
    _isReady = false;
    _paginationGeneration++;
    try {
      _restorePersistedState();
      final book = await _bookLoader(doc, _settings.honorPublisherCss);
      if (_disposed || generation != _lifecycleGeneration) return;
      if (book.spine.isEmpty) {
        throw const FormatException('The document contains no reading spine.');
      }
      final settings = _settings;
      _book = book;
      _pinDatabase(book.tanachDatabasePath);
      if (book.hasLazyTanachContent) {
        final target = _spineIndexForPosition(_position, book);
        await _ensureChapterLoaded(target, settings: settings);
      }
      final projected = book.hasLazyTanachContent
          ? _book!
          : book.studyDocuments.isEmpty
          ? book
          : await _project(book, settings);
      if (_disposed || generation != _lifecycleGeneration) return;
      _book = projected;
      await _prepareImages(projected, generation);
      if (_disposed || generation != _lifecycleGeneration) return;
      _clampPositionToBook();
      _hasLoadedBook = true;
      _retainedToc = projected.tableOfContents;
      _isReady = true;
      _isSuspended = false;
      _error = null;
      notifyListeners();
      final contentSize = _contentSize;
      if (contentSize != null) unawaited(_repaginate(contentSize));
    } catch (error) {
      if (_disposed || generation != _lifecycleGeneration) return;
      _error = readerErrorMessage(error, doc.format);
      _isReady = false;
      _isPaginating = false;
      notifyListeners();
    }
  }

  @override
  void suspend() {
    if (_isSuspended || _disposed) return;
    _lifecycleGeneration++;
    _isSuspended = true;
    _isReady = false;
    _paginationGeneration++;
    _isPaginating = false;
    _abandonLayouts();
    _persistState();
    notifyListeners();
  }

  /// Drops in-flight chapter layouts. Their generation check makes any late
  /// publication a no-op, and their waiters are released so a pending
  /// navigation can see that it was cancelled.
  void _abandonLayouts() {
    for (final layout in _layouts.values) {
      layout.finish();
    }
    _layouts.clear();
    _failedChapters.clear();
  }

  @override
  void handleMemoryPressure() {
    if (_disposed) return;
    suspend();
    _savedPercent = percent;
    _retainedPageCount = pageCount;
    _book = null;
    _pinDatabase(null);
    _pages = const [];
    _chapterPages.clear();
    _completedChapters.clear();
    _imageSizes.clear();
    _chapterUseOrder.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _lifecycleGeneration++;
    _paginationGeneration++;
    _book = null;
    _pinDatabase(null);
    _pages = const [];
    _chapterPages.clear();
    _completedChapters.clear();
    _imageSizes.clear();
    _chapterUseOrder.clear();
    _abandonLayouts();
    super.dispose();
  }

  @override
  Future<void> resume() async {
    if (!_isSuspended || _disposed) return;
    if (_book == null || _error != null) {
      await open();
      return;
    }
    _isSuspended = false;
    _isReady = true;
    _error = null;
    notifyListeners();
    final contentSize = _contentSize;
    if ((_pages.isEmpty || _chapterPages.length < _book!.spine.length) &&
        contentSize != null) {
      unawaited(_repaginate(contentSize));
    }
  }

  void updateViewport(Size viewport) {
    unawaited(prepareViewport(viewport));
  }

  /// Lays the document out for [viewport].
  ///
  /// [awaitComplete] decides what this call waits for. The reader can start on
  /// the pages of the current position as soon as they exist either way; with
  /// `false` the rest of the book keeps laying out in the background, which is
  /// what typography changes use so page turns are never held for a whole book.
  Future<void> prepareViewport(
    Size viewport, {
    bool awaitComplete = true,
  }) async {
    final content = Size(
      (viewport.width - _settings.horizontalMargin * 2).clamp(
        1,
        double.infinity,
      ),
      (viewport.height - _settings.horizontalMargin * 2).clamp(
        1,
        double.infinity,
      ),
    );
    if (_viewport == viewport && _contentSize == content && _pages.isNotEmpty) {
      return;
    }
    _viewport = viewport;
    _contentSize = content;
    if (_isReady) await _repaginate(content, awaitComplete: awaitComplete);
  }

  @override
  Future<void> nextPage() async {
    await _turnPage(1);
  }

  @override
  Future<void> prevPage() async {
    await _turnPage(-1);
  }

  bool _navigationCurrent(int lifecycle, int layout) =>
      !_disposed &&
      _isReady &&
      !_isSuspended &&
      _book != null &&
      lifecycle == _lifecycleGeneration &&
      layout == _paginationGeneration;

  Future<void> _turnPage(int direction) async {
    final book = _book;
    if (!_isReady || book == null || book.spine.isEmpty) return;
    final lifecycle = _lifecycleGeneration;
    final pagination = _paginationGeneration;
    var chapter = _position.spineIndex.clamp(0, book.spine.length - 1);
    // Wait for the pages this turn needs — never for a whole chapter. A tap
    // that lands on pages the background pass has not measured yet waits for
    // the next batch (tens of milliseconds) instead of a complete layout.
    await _ensureChapterPages(chapter, through: _position);
    if (!_navigationCurrent(lifecycle, pagination)) return;
    for (var attempt = 0; attempt < _maxTurnAttempts; attempt++) {
      final index = _pageIndexForPosition(_position);
      final adjacent = index + direction;
      if (adjacent >= 0 &&
          adjacent < _pages.length &&
          _pages[adjacent].start.spineIndex == chapter &&
          _pages[adjacent].end.spineIndex == chapter) {
        _setCurrentPage(adjacent);
        _trimResidentChapters();
        return;
      }
      if (direction > 0 && !_completedChapters.contains(chapter)) {
        // The reader is at the edge of what has been laid out so far: wait for
        // the next batch rather than skipping ahead into another chapter.
        final layout = _layoutFor(chapter);
        if (layout == null) return;
        await layout.nextPublication();
        if (!_navigationCurrent(lifecycle, pagination)) return;
        continue;
      }
      // The chapter is exhausted, so cross into its neighbour.
      final next = chapter + direction;
      if (next < 0 || next >= _book!.spine.length) return;
      await _ensureChapterPages(
        next,
        need: direction > 0 ? _PageNeed.any : _PageNeed.complete,
      );
      if (!_navigationCurrent(lifecycle, pagination)) return;
      final pages = _chapterPages[next];
      chapter = next;
      // Skip chapters that laid out no pages at all (for example a decorative
      // cover) and keep looking in the same direction.
      if (pages == null || pages.isEmpty) continue;
      _goToPosition(direction > 0 ? pages.first.start : pages.last.start);
      _trimResidentChapters();
      return;
    }
  }

  @override
  Future<void> goToPage(int pageIndex) async {
    if (!_isReady || _pages.isEmpty) return;
    await _jumpTo(_pages[pageIndex.clamp(0, _pages.length - 1)].start);
  }

  @override
  Future<void> goToToc(TocEntry entry) async {
    final target = entry.position;
    if (!_isReady || target is! TextReadingPosition) return;
    await _jumpTo(target);
  }

  Future<bool> openLink(String href) async {
    final book = _book;
    if (book == null || !_isReady) return false;
    final target = href.startsWith('#')
        ? '${book.spine[_position.spineIndex].href}$href'
        : href;
    final path = target.split('#').first;
    final spineIndex = book.spine.indexWhere((item) => item.href == path);
    if (spineIndex < 0) return false;
    final anchor = target.contains('#')
        ? Uri.decodeComponent(target.substring(target.indexOf('#') + 1))
        : null;
    final block = anchor == null ? 0 : book.spine[spineIndex].anchors[anchor];
    if (block == null) return false;
    return _jumpTo(
      TextReadingPosition(
        spineIndex: spineIndex,
        blockIndex: block,
        charOffset: 0,
      ),
    );
  }

  @override
  Future<void> goToPercent(double pct) async {
    final book = _book;
    if (!_isReady || book == null || book.characterCount == 0) return;
    final lifecycle = _lifecycleGeneration;
    final layout = _paginationGeneration;
    final targetCharacter = (pct.clamp(0.0, 1.0) * book.characterCount).floor();
    var spineIndex = book.cumulativeCharacterCounts.indexWhere(
      (count) => count > targetCharacter,
    );
    if (spineIndex < 0) spineIndex = book.spine.length - 1;
    // A lazy chapter exposes its size before its text, so the offset inside the
    // chapter can only be resolved once its blocks are loaded.
    await _ensureChapterLoaded(spineIndex);
    if (!_navigationCurrent(lifecycle, layout)) return;
    final currentBook = _book!;
    final beforeSpine = spineIndex == 0
        ? 0
        : currentBook.cumulativeCharacterCounts[spineIndex - 1];
    var remaining = targetCharacter - beforeSpine;
    final blocks = currentBook.spine[spineIndex].blocks;
    if (blocks.isEmpty) return;
    final chapter = currentBook.spine[spineIndex];
    if (chapter.isLazy && chapter.characterCount > 0) {
      final displayed = blocks.fold<int>(
        0,
        (sum, block) => sum + block.characterCount,
      );
      remaining = (remaining * displayed / chapter.characterCount).round();
    }
    var blockIndex = 0;
    while (blockIndex < blocks.length - 1 &&
        remaining >= blocks[blockIndex].characterCount) {
      remaining -= blocks[blockIndex].characterCount;
      blockIndex++;
    }
    await _jumpTo(
      TextReadingPosition(
        spineIndex: spineIndex,
        blockIndex: blockIndex,
        charOffset: remaining.clamp(0, blocks[blockIndex].characterCount),
      ),
    );
  }

  @override
  Future<void> addBookmark(String label) async {
    final bookmark = Bookmark(
      id: Bookmark.generateId(),
      docId: doc.id,
      createdAt: DateTime.now(),
      label: label,
      position: _anchoredPosition(_position),
    );
    _bookmarks = List<Bookmark>.unmodifiable([..._bookmarks, bookmark]);
    notifyListeners();
    _persistState();
  }

  @override
  Future<void> removeBookmark(String id) async {
    _bookmarks = List<Bookmark>.unmodifiable(
      _bookmarks.where((b) => b.id != id),
    );
    notifyListeners();
    _persistState();
  }

  @override
  Future<void> applySettings(ReaderSettings settings) async {
    final generation = _lifecycleGeneration;
    final settingsGeneration = ++_settingsGeneration;
    _position = _anchoredPosition(_position);
    final mustReparse =
        settings.honorPublisherCss != _settings.honorPublisherCss;
    _paginationGeneration++;
    _settings = settings;
    _persistState(settingsOverride: settings);
    if (mustReparse) {
      try {
        final book = await _bookLoader(doc, settings.honorPublisherCss);
        if (_disposed || generation != _lifecycleGeneration) return;
        if (book.spine.isEmpty) {
          throw const FormatException('Empty reading spine.');
        }
        _book = book;
        await _prepareImages(book, generation);
        if (_disposed ||
            generation != _lifecycleGeneration ||
            settingsGeneration != _settingsGeneration) {
          return;
        }
        _pinDatabase(book.tanachDatabasePath);
        if (!book.hasLazyTanachContent) _clampPositionToBook();
        _retainedToc = book.tableOfContents;
      } catch (error) {
        if (_disposed || generation != _lifecycleGeneration) return;
        _error = readerErrorMessage(error, doc.format);
        _isReady = false;
        notifyListeners();
        return;
      }
    }
    final source = _book;
    if (source != null && source.hasLazyTanachContent) {
      _book = _unloadLazyChapters(source);
      _chapterUseOrder.clear();
      await _ensureChapterLoaded(
        _spineIndexForPosition(_position, _book!),
        settings: settings,
      );
      if (_disposed ||
          generation != _lifecycleGeneration ||
          settingsGeneration != _settingsGeneration) {
        return;
      }
      _clampPositionToBook();
      _retainedToc = _book!.tableOfContents;
    } else if (source != null && source.studyDocuments.isNotEmpty) {
      final projected = await _project(source, settings);
      if (_disposed ||
          generation != _lifecycleGeneration ||
          settingsGeneration != _settingsGeneration) {
        return;
      }
      _book = projected;
      _clampPositionToBook();
      _retainedToc = projected.tableOfContents;
    }
    _error = null;
    final viewport = _viewport;
    if (viewport != null) {
      _contentSize = null;
      // Wait only until the reading position has pages again. The remaining
      // chapters keep laying out in the background so page turns stay usable.
      await prepareViewport(viewport, awaitComplete: false);
    }
    if (!_disposed && generation == _lifecycleGeneration) {
      _persistState(settingsOverride: settings);
      notifyListeners();
    }
  }

  /// Lays the whole document out again for [contentSize].
  ///
  /// The chapter holding the reading position is laid out first and publishes
  /// its pages while it is still being measured, so a reader can start on the
  /// current page and turn pages long before the book is finished. With
  /// [awaitComplete] the call waits for the remaining chapters too; without it
  /// only the current position is waited for and the rest keeps running in the
  /// background.
  Future<void> _repaginate(
    Size contentSize, {
    bool awaitComplete = true,
  }) async {
    final book = _book;
    if (book == null || _isSuspended || _disposed) return;
    final generation = ++_paginationGeneration;
    _abandonLayouts();
    _isPaginating = true;
    _chapterPages.clear();
    _completedChapters.clear();
    _pages = const [];
    _currentPage = 0;
    notifyListeners();

    final priority = _position.spineIndex.clamp(0, book.spine.length - 1);
    // Read forward first: the chapters a reader is about to reach matter more
    // than the ones behind, and the position's own chapter matters most.
    final order = <int>[
      priority,
      for (var i = priority + 1; i < book.spine.length; i++) i,
      for (var i = priority - 1; i >= 0; i--) i,
    ];
    final run = _runPagination(
      contentSize: contentSize,
      generation: generation,
      order: order,
      priority: priority,
    );
    if (awaitComplete) {
      await run;
      return;
    }
    await _ensureChapterPages(priority, through: _position);
    if (_paginationCurrent(generation)) unawaited(run);
  }

  /// True while [generation] is still the layout the session wants.
  bool _paginationCurrent(int generation) =>
      !_disposed && !_isSuspended && generation == _paginationGeneration;

  /// Lays out [order] one chapter at a time, publishing each chapter's pages as
  /// they are measured. Page turns and jumps can ask for a chapter at any time;
  /// they share the in-flight layout instead of starting a second one.
  Future<void> _runPagination({
    required Size contentSize,
    required int generation,
    required List<int> order,
    required int priority,
  }) async {
    try {
      for (final spineIndex in order) {
        if (!_paginationCurrent(generation)) return;
        if (_completedChapters.contains(spineIndex)) continue;
        final layout = _layoutChapter(
          spineIndex,
          contentSize: contentSize,
          generation: generation,
        );
        if (layout != null) {
          await layout.done;
          if (layout.error != null) throw layout.error!;
        }
        if (!_paginationCurrent(generation)) return;
        final book = _book;
        if (book != null &&
            book.hasLazyTanachContent &&
            spineIndex != priority) {
          _trimResidentChapters();
        }
        notifyListeners();
        await Future<void>.delayed(Duration.zero);
      }
      if (!_paginationCurrent(generation)) return;
      _isPaginating = false;
      _error = null;
      notifyListeners();
    } catch (error) {
      if (!_paginationCurrent(generation)) return;
      _isPaginating = false;
      _isReady = false;
      _error = readerErrorMessage(error, doc.format);
      notifyListeners();
    }
  }

  Future<void> _savePages(String key, List<LaidOutPage> pages) async {
    try {
      await _paginationCache.save(key, pages);
    } catch (_) {
      // A cache write is optional; a full disk must not interrupt reading.
    }
  }

  /// Makes sure a navigation into [spineIndex] can show the page it needs.
  ///
  /// Layout is requested on demand and shared with the background pass, and the
  /// call returns as soon as the pages it asked for exist — never after a whole
  /// chapter has been laid out.
  Future<void> _ensureChapterPages(
    int spineIndex, {
    TextReadingPosition? through,
    _PageNeed need = _PageNeed.position,
  }) async {
    final book = _book;
    if (book == null || spineIndex < 0 || spineIndex >= book.spine.length) {
      return;
    }
    final lifecycle = _lifecycleGeneration;
    final generation = _paginationGeneration;
    await _ensureChapterLoaded(spineIndex);
    if (!_navigationCurrent(lifecycle, generation)) return;
    if (_completedChapters.contains(spineIndex)) return;
    final contentSize = _contentSize;
    if (contentSize == null) return;
    await _awaitPages(
      spineIndex,
      need: need,
      through: through,
      contentSize: contentSize,
      generation: generation,
    );
  }

  /// Waits until [spineIndex] satisfies [need], laying the chapter out on
  /// demand. A chapter that already has the needed pages returns immediately.
  Future<void> _awaitPages(
    int spineIndex, {
    required _PageNeed need,
    required TextReadingPosition? through,
    required Size contentSize,
    required int generation,
  }) async {
    while (true) {
      if (!_paginationCurrent(generation)) return;
      if (_failedChapters.contains(spineIndex)) return;
      if (_needSatisfied(need, through, spineIndex)) return;
      final layout = _layoutChapter(
        spineIndex,
        contentSize: contentSize,
        generation: generation,
      );
      // Nothing left to lay out: the chapter is finished (possibly with no
      // pages at all, like a decorative cover) or its layout failed.
      if (layout == null) return;
      if (_needSatisfied(need, through, spineIndex)) return;
      await layout.nextPublication();
    }
  }

  bool _needSatisfied(
    _PageNeed need,
    TextReadingPosition? through,
    int spineIndex,
  ) {
    if (_completedChapters.contains(spineIndex)) return true;
    final pages = _chapterPages[spineIndex];
    return switch (need) {
      _PageNeed.any => pages != null && pages.isNotEmpty,
      _PageNeed.position =>
        pages != null &&
            pages.isNotEmpty &&
            through != null &&
            _comparePosition(through, pages.last.end) <= 0,
      _PageNeed.complete => false,
    };
  }

  /// Jumps to [target], waiting only until that position has pages.
  ///
  /// Published pages are kept, so a jump never blanks the page on screen, and
  /// the target chapter is laid out straight away instead of waiting for the
  /// background pass to reach it.
  Future<bool> _jumpTo(TextReadingPosition target) async {
    final book = _book;
    if (book == null || book.spine.isEmpty || !_isReady) return false;
    final lifecycle = _lifecycleGeneration;
    final generation = _paginationGeneration;
    final spineIndex = _spineIndexForPosition(target, book);
    await _ensureChapterPages(spineIndex, through: target);
    if (!_navigationCurrent(lifecycle, generation)) return false;
    _goToPosition(target);
    _trimResidentChapters();
    return true;
  }

  _ChapterLayout? _layoutFor(int spineIndex) => _layouts[spineIndex];

  /// Starts (or joins) the layout of one chapter.
  ///
  /// A turn that needs a chapter the background pass has not reached yet starts
  /// it here and shares the work with any request already in flight, so the
  /// same chapter is never laid out twice.
  _ChapterLayout? _layoutChapter(
    int spineIndex, {
    required Size contentSize,
    required int generation,
  }) {
    final book = _book;
    if (book == null || spineIndex < 0 || spineIndex >= book.spine.length) {
      return null;
    }
    if (_completedChapters.contains(spineIndex) ||
        _failedChapters.contains(spineIndex)) {
      return null;
    }
    final existing = _layouts[spineIndex];
    if (existing != null) return existing;
    final layout = _ChapterLayout(spineIndex);
    _layouts[spineIndex] = layout;
    unawaited(
      _runChapterLayout(
        layout,
        contentSize: contentSize,
        generation: generation,
      ),
    );
    return layout;
  }

  Future<void> _runChapterLayout(
    _ChapterLayout layout, {
    required Size contentSize,
    required int generation,
  }) async {
    final spineIndex = layout.spineIndex;
    try {
      final book = _book;
      if (book == null || spineIndex >= book.spine.length) return;
      final cacheKey = _paginationCache.keyFor(
        docId: '${doc.id}:${book.contentFingerprint}',
        spineIndex: spineIndex,
        width: contentSize.width,
        height: contentSize.height,
        settings: _settings,
      );
      final cached = await _paginationCache.load(cacheKey);
      if (!_paginationCurrent(generation)) return;
      if (cached != null) {
        _publishChapter(
          spineIndex,
          cached,
          complete: true,
          generation: generation,
        );
        return;
      }
      // Lazy chapters load their text only when it is really needed, so a
      // cached layout for a Tanach chapter does not pull it into memory.
      await _ensureChapterLoaded(spineIndex);
      if (!_paginationCurrent(generation)) return;
      final blocks = _book!.spine[spineIndex].blocks;
      final pages = await _paginator.paginateSpineResponsive(
        spineIndex: spineIndex,
        blocks: blocks,
        contentSize: contentSize,
        imageSizes: _imageSizes,
        settings: _settings,
        isCancelled: () => !_paginationCurrent(generation),
        onProgress: (partial) => _publishChapter(
          spineIndex,
          partial,
          complete: false,
          generation: generation,
        ),
      );
      if (!_paginationCurrent(generation)) return;
      unawaited(_savePages(cacheKey, pages));
      _publishChapter(
        spineIndex,
        pages,
        complete: true,
        generation: generation,
      );
    } catch (error) {
      if (_paginationCurrent(generation)) _failedChapters.add(spineIndex);
      layout.fail(error);
    } finally {
      if (_layouts[spineIndex] == layout) _layouts.remove(spineIndex);
      layout.finish();
    }
  }

  /// Publishes the pages measured so far for one chapter. Running this per batch
  /// is what lets a reader start before the chapter — or the book — is done.
  void _publishChapter(
    int spineIndex,
    List<LaidOutPage> pages, {
    required bool complete,
    required int generation,
  }) {
    if (!_paginationCurrent(generation)) return;
    if (!complete && pages.isEmpty) return;
    _chapterPages[spineIndex] = pages;
    if (complete) _completedChapters.add(spineIndex);
    // Release waiters first so a pending turn sees the pages it was waiting for.
    _layouts[spineIndex]?.published();
    _rebuildPages();
    notifyListeners();
  }

  Future<void> _ensureChapterLoaded(
    int spineIndex, {
    ReaderSettings? settings,
  }) async {
    final book = _book;
    if (book == null ||
        !book.hasLazyTanachContent ||
        spineIndex < 0 ||
        spineIndex >= book.spine.length) {
      return;
    }
    if (book.spine[spineIndex].isLoaded) {
      _touchChapter(spineIndex);
      return;
    }
    final databasePath = book.tanachDatabasePath;
    final settingsGeneration = _settingsGeneration;
    final lifecycle = _lifecycleGeneration;
    await _ensureDatabase();
    if (_disposed ||
        lifecycle != _lifecycleGeneration ||
        settingsGeneration != _settingsGeneration) {
      return;
    }
    final loaded = await _tanachCache.loadChapter(
      book,
      spineIndex,
      settings ?? _settings,
    );
    final current = _book;
    if (_disposed ||
        lifecycle != _lifecycleGeneration ||
        current == null ||
        settingsGeneration != _settingsGeneration ||
        current.tanachDatabasePath != databasePath ||
        !current.spine[spineIndex].isLazy) {
      return;
    }
    final spine = [...current.spine];
    spine[spineIndex] = loaded;
    _book = _copyBook(current, spine);
    // Lazy chapters can introduce figures absent from the initial skeleton.
    if (loaded.blocks.any((block) => block.type == BlockType.image)) {
      await _prepareImages(_book!, lifecycle);
      if (_disposed ||
          lifecycle != _lifecycleGeneration ||
          settingsGeneration != _settingsGeneration) {
        return;
      }
    }
    _touchChapter(spineIndex);
  }

  void _touchChapter(int spineIndex) {
    _chapterUseOrder.remove(spineIndex);
    _chapterUseOrder.add(spineIndex);
  }

  void _trimResidentChapters() {
    final book = _book;
    if (book == null || !book.hasLazyTanachContent) return;
    final protected = _position.spineIndex;
    while (_chapterUseOrder.length > _maxResidentTanachChapters) {
      final candidate = _chapterUseOrder.firstWhere(
        // A chapter with pages still being measured must stay loaded: the
        // paginator and the renderer both need its blocks.
        (index) => index != protected && !_layouts.containsKey(index),
        orElse: () => -1,
      );
      if (candidate < 0) return;
      _chapterUseOrder.remove(candidate);
      final current = _book!;
      final item = current.spine[candidate];
      if (!item.isLazy || !item.isLoaded) continue;
      final spine = [...current.spine];
      spine[candidate] = ParsedSpineItem(
        id: item.id,
        href: item.href,
        title: item.title,
        blocks: const [],
        characterCount: item.characterCount,
        isLoaded: false,
        isLazy: true,
      );
      _book = _copyBook(current, spine);
    }
  }

  ParsedBook _unloadLazyChapters(ParsedBook book) => _copyBook(book, [
    for (final item in book.spine)
      if (item.isLazy)
        ParsedSpineItem(
          id: item.id,
          href: item.href,
          title: item.title,
          blocks: const [],
          characterCount: item.characterCount,
          isLoaded: false,
          isLazy: true,
        )
      else
        item,
  ]);

  ParsedBook _copyBook(ParsedBook book, List<ParsedSpineItem> spine) =>
      ParsedBook(
        title: book.title,
        author: book.author,
        language: book.language,
        rightToLeft: book.rightToLeft,
        contentFingerprint: book.contentFingerprint,
        studyDocuments: book.studyDocuments,
        studySources: book.studySources,
        studyTranslations: book.studyTranslations,
        primaryStudyTranslationId: book.primaryStudyTranslationId,
        studyProjectionKey: book.studyProjectionKey,
        spine: List.unmodifiable(spine),
        resources: book.resources,
        tableOfContents: book.tableOfContents,
        tanachDatabasePath: book.tanachDatabasePath,
      );

  int _spineIndexForPosition(TextReadingPosition position, ParsedBook book) {
    final byPath = book.spine.indexWhere(
      (item) => item.href == position.documentPath,
    );
    return byPath >= 0
        ? byPath
        : position.spineIndex.clamp(0, book.spine.length - 1);
  }

  void _rebuildPages() {
    final book = _book!;
    final pages = <LaidOutPage>[];
    // Keep every published page list in logical spine order even while some
    // chapters are still missing. Position comparisons and next/previous
    // navigation depend on this invariant.
    for (var spineIndex = 0; spineIndex < book.spine.length; spineIndex++) {
      for (final page in _chapterPages[spineIndex] ?? const <LaidOutPage>[]) {
        pages.add(
          LaidOutPage(
            pageIndex: pages.length,
            slices: page.slices,
            start: page.start,
            end: page.end,
          ),
        );
      }
    }
    _pages = List<LaidOutPage>.unmodifiable(pages);
    _currentPage = _pageIndexForPosition(_position);
  }

  void _goToPosition(TextReadingPosition target) {
    final book = _book;
    if (book == null || book.spine.isEmpty) return;
    _position = _clampPosition(target, book);
    _currentPage = _pageIndexForPosition(_position);
    // Keep the logical target (including a search match's character offset).
    // Snapping to the page start can hide it after a typography/viewport change.
    _persistState();
    notifyListeners();
  }

  int _pageIndexForPosition(TextReadingPosition target) {
    if (_pages.isEmpty) return 0;
    for (var i = 0; i < _pages.length; i++) {
      final page = _pages[i];
      if (_comparePosition(target, page.start) >= 0 &&
          (_comparePosition(target, page.end) < 0 || i == _pages.length - 1)) {
        return i;
      }
      if (_comparePosition(target, page.start) < 0) return i;
    }
    return _pages.length - 1;
  }

  void _setCurrentPage(int pageIndex) {
    _currentPage = pageIndex;
    _position = _pages[pageIndex].start;
    _persistState();
    notifyListeners();
  }

  void _restorePersistedState() {
    _settings = _bookStore.getSettingsForDoc(doc.id);
    final stored = _bookStore.getBookState(doc.id);
    _savedPercent = stored?.percent ?? 0;
    if (stored?.position case final TextReadingPosition value) {
      _position = value;
    }
    _bookmarks = stored?.bookmarks ?? const [];
  }

  void _clampPositionToBook() {
    final book = _book!;
    _position = _anchoredPosition(_clampPosition(_position, book));
  }

  TextReadingPosition _clampPosition(
    TextReadingPosition position,
    ParsedBook book,
  ) {
    final byPath = book.spine.indexWhere(
      (item) => item.href == position.documentPath,
    );
    final spineIndex = byPath >= 0
        ? byPath
        : position.spineIndex.clamp(0, book.spine.length - 1);
    final blocks = book.spine[spineIndex].blocks;
    if (blocks.isEmpty) {
      return TextReadingPosition(
        spineIndex: spineIndex,
        blockIndex: 0,
        charOffset: 0,
      );
    }
    final anchors = book.spine[spineIndex].anchors;
    final exact = anchors[position.blockId];
    final fallback = anchors[position.verseId];
    final blockIndex =
        exact ?? fallback ?? position.blockIndex.clamp(0, blocks.length - 1);
    return TextReadingPosition(
      spineIndex: spineIndex,
      blockIndex: blockIndex,
      charOffset: (exact == null && fallback != null ? 0 : position.charOffset)
          .clamp(0, blocks[blockIndex].characterCount),
    );
  }

  TextReadingPosition _anchoredPosition(TextReadingPosition position) {
    final book = _book;
    if (book == null ||
        (book.studyDocuments.isEmpty && !book.hasLazyTanachContent)) {
      return position;
    }
    final item =
        book.spine[position.spineIndex.clamp(0, book.spine.length - 1)];
    if (item.blocks.isEmpty) return position;
    final id =
        item.blocks[position.blockIndex.clamp(0, item.blocks.length - 1)].id;
    return TextReadingPosition(
      spineIndex: position.spineIndex,
      blockIndex: position.blockIndex,
      charOffset: position.charOffset,
      documentPath: item.href,
      blockId: id,
      verseId: id?.startsWith('v-') == true ? id!.split('--').first : null,
    );
  }

  void _persistState({ReaderSettings? settingsOverride}) {
    // A failed open must never overwrite a previously saved position/bookmarks.
    if (!_hasLoadedBook) return;
    final previous = _bookStore.getBookState(doc.id);
    _bookStore.saveBookState(
      BookState(
        docId: doc.id,
        lastPath: doc.path,
        format: doc.format,
        lastRead: DateTime.now(),
        position: _anchoredPosition(_position),
        percent: percent,
        settingsOverride: settingsOverride ?? previous?.settingsOverride,
        bookmarks: _bookmarks,
        annotations: previous?.annotations ?? const [],
      ),
    );
  }

  static int _comparePosition(TextReadingPosition a, TextReadingPosition b) {
    final spine = a.spineIndex.compareTo(b.spineIndex);
    if (spine != 0) return spine;
    final block = a.blockIndex.compareTo(b.blockIndex);
    if (block != 0) return block;
    return a.charOffset.compareTo(b.charOffset);
  }
}

/// What a navigation needs before it can show a chapter's page.
enum _PageNeed {
  /// At least one page exists (crossing forward into a chapter).
  any,

  /// The pages cover the position the reader is going to (turning a page, or
  /// jumping to a TOC entry, search match, or bookmark).
  position,

  /// The chapter is finished. Crossing backwards needs its last page, and page
  /// breaks are only known once the whole chapter has been measured.
  complete,
}

/// Layout work for one spine item within one pagination generation.
///
/// Both the background pass and page turns ask for chapters through this
/// object, so a chapter is laid out once and every waiter is woken by the same
/// publication. [done] completes even when the work is abandoned (suspension,
/// memory pressure, or a newer layout), which keeps pending navigations from
/// waiting forever.
class _ChapterLayout {
  _ChapterLayout(this.spineIndex);

  final int spineIndex;
  final Completer<void> _done = Completer<void>();
  final List<Completer<void>> _publications = [];
  bool _finished = false;
  Object? _error;

  /// Set when the chapter was laid out but the layout failed.
  Object? get error => _error;

  Future<void> get done => _done.future;

  /// Resolves when more pages become available, or immediately when no more
  /// will (the chapter finished or the work was abandoned).
  Future<void> nextPublication() {
    if (_finished) return Future<void>.value();
    final completer = Completer<void>();
    _publications.add(completer);
    return completer.future;
  }

  void published() => _releaseWaiters();

  void fail(Object error) {
    _error = error;
    _finish();
  }

  /// Releases waiters and lets the background pass move on, whatever the
  /// outcome. Safe to call more than once.
  void finish() => _finish();

  void _finish() {
    _finished = true;
    if (!_done.isCompleted) _done.complete();
    _releaseWaiters();
  }

  void _releaseWaiters() {
    for (final waiter in _publications) {
      if (!waiter.isCompleted) waiter.complete();
    }
    _publications.clear();
  }
}

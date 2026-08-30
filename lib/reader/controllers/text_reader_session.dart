import 'dart:async';
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
import '../services/epub_parser_service.dart';
import '../services/pagination_cache_service.dart';
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

  ParsedBook? _book;
  ReaderSettings _settings = const ReaderSettings();
  TextReadingPosition _position = const TextReadingPosition(
    spineIndex: 0,
    blockIndex: 0,
    charOffset: 0,
  );
  List<LaidOutPage> _pages = const [];
  final Map<int, List<LaidOutPage>> _chapterPages = {};
  Size? _viewport;
  Size? _contentSize;
  int _currentPage = 0;
  int _paginationGeneration = 0;
  List<Bookmark> _bookmarks = const [];
  bool _isReady = false;
  bool _isSuspended = false;
  bool _isPaginating = false;
  String? _error;

  TextReaderSession({
    required this.doc,
    BookStoreService? bookStore,
    EpubPaginatorService? paginator,
    PaginationCacheService? paginationCache,
    TextBookLoader? bookLoader,
  }) : _bookStore = bookStore ?? BookStoreService.instance,
       _paginator = paginator ?? const EpubPaginatorService(),
       _paginationCache = paginationCache ?? const PaginationCacheService(),
       _bookLoader = bookLoader ?? _loadBook;

  static Future<ParsedBook> _loadBook(DocRef doc, bool honorPublisherCss) {
    return switch (doc.format) {
      DocFormat.epub => const EpubParserService().parseFile(
        doc.path,
        honorPublisherCss: honorPublisherCss,
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

  @override
  bool get isReady => _isReady;

  @override
  bool get isSuspended => _isSuspended;

  bool get isPaginating => _isPaginating;

  @override
  String? get error => _error;

  @override
  int get pageCount => _pages.length;

  @override
  int get currentPage => _currentPage;

  @override
  double get percent {
    final book = _book;
    if (book == null || book.characterCount == 0) return 0;
    var read = 0;
    if (_position.spineIndex > 0) {
      read = book.cumulativeCharacterCounts[_position.spineIndex - 1];
    }
    final spine = book.spine[_position.spineIndex];
    for (var i = 0; i < _position.blockIndex && i < spine.blocks.length; i++) {
      read += spine.blocks[i].characterCount;
    }
    read += _position.charOffset;
    return (read / book.characterCount).clamp(0.0, 1.0);
  }

  @override
  ReadingPosition get position => _position;

  @override
  List<TocEntry> get toc => _book?.tableOfContents ?? const [];

  @override
  ReaderSettings get settings => _settings;

  @override
  List<Bookmark> get bookmarks => _bookmarks;

  ParsedBook? get book => _book;

  LaidOutPage? get currentLaidOutPage =>
      _pages.isEmpty ? null : _pages[_currentPage];

  ContentBlock blockAt(int spineIndex, int blockIndex) =>
      _book!.spine[spineIndex].blocks[blockIndex];

  @override
  Future<void> open() async {
    try {
      _restorePersistedState();
      _book = await _bookLoader(doc, _settings.honorPublisherCss);
      _clampPositionToBook();
      _isReady = true;
      _isSuspended = false;
      _error = null;
      notifyListeners();
      final contentSize = _contentSize;
      if (contentSize != null) unawaited(_repaginate(contentSize));
    } catch (error) {
      _error = 'Failed to open ${doc.title}: $error';
      _isReady = false;
      notifyListeners();
    }
  }

  @override
  void suspend() {
    if (_isSuspended) return;
    _isSuspended = true;
    _isReady = false;
    _paginationGeneration++;
    _isPaginating = false;
    _persistState();
    notifyListeners();
  }

  @override
  Future<void> resume() async {
    if (!_isSuspended) return;
    if (_book == null) {
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

  Future<void> prepareViewport(Size viewport) async {
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
    if (_isReady) await _repaginate(content);
  }

  @override
  Future<void> nextPage() async {
    if (!_isReady || _currentPage >= _pages.length - 1) return;
    _setCurrentPage(_currentPage + 1);
  }

  @override
  Future<void> prevPage() async {
    if (!_isReady || _currentPage <= 0) return;
    _setCurrentPage(_currentPage - 1);
  }

  @override
  Future<void> goToPage(int pageIndex) async {
    if (!_isReady || _pages.isEmpty) return;
    _setCurrentPage(pageIndex.clamp(0, _pages.length - 1));
  }

  @override
  Future<void> goToToc(TocEntry entry) async {
    final target = entry.position;
    if (!_isReady || target is! TextReadingPosition) return;
    _goToPosition(target);
  }

  @override
  Future<void> goToPercent(double pct) async {
    final book = _book;
    if (!_isReady || book == null || book.characterCount == 0) return;
    final targetCharacter = (pct.clamp(0.0, 1.0) * book.characterCount).floor();
    var spineIndex = book.cumulativeCharacterCounts.indexWhere(
      (count) => count > targetCharacter,
    );
    if (spineIndex < 0) spineIndex = book.spine.length - 1;
    final beforeSpine = spineIndex == 0
        ? 0
        : book.cumulativeCharacterCounts[spineIndex - 1];
    var remaining = targetCharacter - beforeSpine;
    final blocks = book.spine[spineIndex].blocks;
    if (blocks.isEmpty) return;
    var blockIndex = 0;
    while (blockIndex < blocks.length - 1 &&
        remaining >= blocks[blockIndex].characterCount) {
      remaining -= blocks[blockIndex].characterCount;
      blockIndex++;
    }
    _goToPosition(
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
      position: _position,
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
    final mustReparse =
        settings.honorPublisherCss != _settings.honorPublisherCss;
    _settings = settings;
    _persistState(settingsOverride: settings);
    if (mustReparse) {
      try {
        _book = await _bookLoader(doc, settings.honorPublisherCss);
      } catch (error) {
        _error = 'Failed to apply settings: $error';
        notifyListeners();
        return;
      }
    }
    final viewport = _viewport;
    if (viewport != null) {
      _contentSize = null;
      await prepareViewport(viewport);
    }
    notifyListeners();
  }

  Future<void> _repaginate(Size contentSize) async {
    final book = _book;
    if (book == null || _isSuspended) return;
    final generation = ++_paginationGeneration;
    _isPaginating = true;
    _chapterPages.clear();
    _pages = const [];
    _currentPage = 0;
    notifyListeners();

    final priority = _position.spineIndex.clamp(0, book.spine.length - 1);
    final order = <int>[
      priority,
      for (var i = 0; i < book.spine.length; i++)
        if (i != priority) i,
    ];
    for (final spineIndex in order) {
      if (generation != _paginationGeneration || _isSuspended) return;
      final cacheKey = _paginationCache.keyFor(
        docId: doc.id,
        spineIndex: spineIndex,
        width: contentSize.width,
        height: contentSize.height,
        settings: _settings,
      );
      var pages = await _paginationCache.load(cacheKey);
      if (pages == null) {
        pages = _paginator.paginateSpine(
          spineIndex: spineIndex,
          blocks: book.spine[spineIndex].blocks,
          contentSize: contentSize,
          settings: _settings,
        );
        unawaited(_paginationCache.save(cacheKey, pages));
      }
      if (generation != _paginationGeneration || _isSuspended) return;
      _chapterPages[spineIndex] = pages;
      _rebuildPages();
      notifyListeners();
      await Future<void>.delayed(Duration.zero);
    }
    _isPaginating = false;
    notifyListeners();
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
    if (!_chapterPages.containsKey(_position.spineIndex)) {
      // Retain the requested logical target until its priority chapter has
      // been laid out. Snapping against another loaded chapter would silently
      // lose TOC/percent jumps during progressive pagination.
      _currentPage = _pageIndexForPosition(_position);
      _persistState();
      notifyListeners();
      final contentSize = _contentSize;
      if (contentSize != null) unawaited(_repaginate(contentSize));
      return;
    }
    _currentPage = _pageIndexForPosition(_position);
    if (_pages.isNotEmpty) _position = _pages[_currentPage].start;
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
    if (stored?.position case final TextReadingPosition value) {
      _position = value;
    }
    _bookmarks = stored?.bookmarks ?? const [];
  }

  void _clampPositionToBook() {
    final book = _book!;
    _position = _clampPosition(_position, book);
  }

  TextReadingPosition _clampPosition(
    TextReadingPosition position,
    ParsedBook book,
  ) {
    final spineIndex = position.spineIndex.clamp(0, book.spine.length - 1);
    final blocks = book.spine[spineIndex].blocks;
    if (blocks.isEmpty) {
      return TextReadingPosition(
        spineIndex: spineIndex,
        blockIndex: 0,
        charOffset: 0,
      );
    }
    final blockIndex = position.blockIndex.clamp(0, blocks.length - 1);
    return TextReadingPosition(
      spineIndex: spineIndex,
      blockIndex: blockIndex,
      charOffset: position.charOffset.clamp(
        0,
        blocks[blockIndex].characterCount,
      ),
    );
  }

  void _persistState({ReaderSettings? settingsOverride}) {
    final previous = _bookStore.getBookState(doc.id);
    _bookStore.saveBookState(
      BookState(
        docId: doc.id,
        lastPath: doc.path,
        format: doc.format,
        lastRead: DateTime.now(),
        position: _position,
        percent: percent,
        settingsOverride: settingsOverride ?? previous?.settingsOverride,
        bookmarks: _bookmarks,
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

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

// NOTE: `num.clamp()` always returns `num`, even when called on an `int` or
// `double` receiver, which does not implicitly convert back to the field or
// parameter type it's assigned to. `clampDouble` (dart:ui) is used for
// double results below; int results go through `.clamp(...).toInt()`.

import '../../constants.dart';
import '../models/book_state.dart';
import '../models/bookmark.dart';
import '../models/doc_ref.dart';
import '../models/pdf_continuous_layout.dart';
import '../models/reader_settings.dart';
import '../models/reading_position.dart';
import '../models/toc_entry.dart';
import '../services/book_store_service.dart';
import '../services/page_bitmap_cache.dart';
import '../services/pdf_crop_service.dart';
import '../services/pdf_document_service.dart';
import '../services/pdf_memory_service.dart';
import '../services/reader_error_service.dart';
import 'reader_session.dart';

typedef PdfDocumentServiceFactory = PdfDocumentService Function(String path);

/// The [ReaderSession] implementation for PDF documents.
///
/// Owns a [PdfDocumentService] (native PDFium handle), a [PageBitmapCache]
/// (rendered page bitmaps), and a [PdfCropService] (auto-crop detection).
/// Position is tracked as `(pageIndex, withinPage)` per READER_PLAN.md §1.B:
/// `withinPage` is `0.0` in fit-height, the sub-screen's vertical start
/// fraction in fit-width, and the transformed viewport-top fraction in
/// Zoom / Scroll. This lets switching fit mode keep your place.
class PdfReaderSession extends ReaderSession {
  @override
  final DocRef doc;

  final BookStoreService _bookStore;
  final PdfCropService _cropService;
  final PageBitmapCache _bitmapCache;
  final PdfMemoryService _memoryService;
  final bool _adaptiveCache;
  final PdfDocumentServiceFactory _serviceFactory;

  PdfDocumentService? _documentService;

  bool _isReady = false;
  bool _isSuspended = false;
  String? _error;
  bool _disposed = false;
  bool _hasOpened = false;
  int _generation = 0;
  Future<void> _closing = Future<void>.value();

  int _pageCount = 0;
  int _pageIndex = 0;
  double _withinPage = 0.0;
  List<TocEntry> _toc = const [];
  ReaderSettings _settings = const ReaderSettings();
  final Map<int, PdfCropRect> _cropRectCache = {};
  List<Bookmark> _bookmarks = const [];
  PdfCropRect? _uniformCropRect;
  PdfContinuousLayout? _continuousLayout;
  int? _continuousCurrentPage;
  double? _continuousViewportHeight;

  /// Bumped by every *programmatic* move (tap jump, page jump, TOC, percent).
  /// User scrolling deliberately leaves it alone: the continuous view only
  /// snaps its transform when this changes, so an in-flight fling is never
  /// cancelled by a rebuild.
  int _navigationEpoch = 0;

  /// Last viewport size reported by the reader widget (Step 1.5). Sub-screen
  /// math and prefetching are no-ops until this is known.
  Size? _lastViewport;
  double _lastDevicePixelRatio = 1.0;

  PdfReaderSession({
    required this.doc,
    BookStoreService? bookStore,
    PdfCropService? cropService,
    PageBitmapCache? bitmapCache,
    PdfMemoryService? memoryService,
    PdfDocumentServiceFactory? documentServiceFactory,
  }) : _bookStore = bookStore ?? BookStoreService.instance,
       _cropService = cropService ?? PdfCropService(),
       _bitmapCache =
           bitmapCache ??
           PageBitmapCache(maxBytes: PdfMemoryService.fallbackCacheBytes),
       _memoryService = memoryService ?? PdfMemoryService.instance,
       _adaptiveCache = bitmapCache == null,
       _serviceFactory = documentServiceFactory ?? PdfDocumentService.new;

  @override
  bool get isReady => _isReady;

  @override
  bool get isSuspended => _isSuspended;

  @override
  String? get error => _error;

  @override
  int get pageCount => _pageCount;

  @override
  int get currentPage =>
      _isContinuous ? _continuousCurrentPage ?? _pageIndex : _pageIndex;

  @override
  double get percent => _pageCount == 0
      ? 0.0
      : clampDouble((_pageIndex + _withinPage) / _pageCount, 0.0, 1.0);

  @override
  ReadingPosition get position =>
      PdfReadingPosition(pageIndex: _pageIndex, withinPage: _withinPage);

  @override
  List<TocEntry> get toc => _toc;

  @override
  ReaderSettings get settings => _settings;

  @override
  List<Bookmark> get bookmarks => _bookmarks;

  /// Monotonic counter identifying the last programmatic navigation. See
  /// [_navigationEpoch].
  int get navigationEpoch => _navigationEpoch;

  /// Retained bitmap budget only; excludes UI handles and native render memory.
  int get bitmapCacheBudgetBytes => _bitmapCache.maxBytes;

  bool get _isContinuous => _settings.fitMode == PdfFitMode.zoom;

  // ---------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------

  @override
  Future<void> open() async {
    if (_disposed) return;
    final generation = ++_generation;
    _isReady = false;
    try {
      await _closing;
      if (_disposed || generation != _generation) return;
      await _configureCache(generation);
      if (_disposed || generation != _generation) return;
      _documentService ??= _serviceFactory(doc.path);
      await _documentService!.open();
      if (_disposed || generation != _generation) return;
      _pageCount = _documentService!.pageCount;
      _restorePersistedState();
      _hasOpened = true;
      _isReady = true;
      _isSuspended = false;
      _error = null;
      unawaited(_loadToc(generation));
    } catch (e) {
      if (_disposed || generation != _generation) return;
      _error = readerErrorMessage(e, doc.format);
      _isReady = false;
      _closing = _closeDocument();
    }
    notifyListeners();
  }

  @override
  void suspend() {
    if (_isSuspended || _disposed) return;
    _generation++;
    _isSuspended = true;
    _isReady = false;
    // Continuous scrolling only persists on page changes, so capture the
    // exact sub-page offset before the bitmaps and handles go away.
    _persistState();
    _bitmapCache.clear();
    _closing = _closeDocument();
    notifyListeners();
  }

  @override
  Future<void> resume() async {
    if (!_isSuspended || _disposed) return;
    final generation = ++_generation;
    try {
      await _closing;
      if (_disposed || generation != _generation) return;
      await _configureCache(generation);
      if (_disposed || generation != _generation) return;
      _documentService ??= _serviceFactory(doc.path);
      await _documentService!.open();
      if (_disposed || generation != _generation) return;
      _pageCount = _documentService!.pageCount;
      if (!_hasOpened) _restorePersistedState();
      _pageIndex = _pageIndex.clamp(0, _pageCount - 1);
      _hasOpened = true;
      _isSuspended = false;
      _isReady = true;
      _error = null;
      _navigationEpoch++;
      unawaited(_loadToc(generation));
      notifyListeners();
    } catch (e) {
      if (_disposed || generation != _generation) return;
      _error = readerErrorMessage(e, doc.format);
      _isReady = false;
      _closing = _closeDocument();
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _bitmapCache.clear();
    _closing = _closeDocument();
    super.dispose();
  }

  Future<void> _closeDocument() async {
    try {
      await _documentService?.close();
    } catch (_) {
      // Cleanup must not produce an unhandled async error during suspension.
    }
  }

  Future<void> _configureCache(int generation) async {
    // Explicitly injected caches retain their caller-selected budgets.
    if (!_adaptiveCache) return;
    final budget = await _memoryService.cacheBudgetBytes();
    if (_disposed || generation != _generation) return;
    _bitmapCache.resize(budget);
  }

  // ---------------------------------------------------------------------
  // Navigation
  // ---------------------------------------------------------------------

  @override
  Future<void> nextPage() async {
    if (!_isReady) return;
    final viewport = _lastViewport;
    if (_isContinuous) {
      if (viewport != null && _continuousLayout != null) {
        _moveContinuousViewport(_continuousViewportHeight ?? viewport.height);
      }
      return;
    }
    if (_settings.fitMode == PdfFitMode.fitWidth && viewport != null) {
      final starts = await _subScreenStarts(_pageIndex, viewport);
      final idx = _nearestIndex(starts, _withinPage);
      if (idx < starts.length - 1) {
        _withinPage = starts[idx + 1];
        _afterPositionChanged();
        return;
      }
    }
    if (_pageIndex >= _pageCount - 1) return;
    _pageIndex += 1;
    _withinPage = 0.0;
    _afterPositionChanged();
  }

  @override
  Future<void> prevPage() async {
    if (!_isReady) return;
    final viewport = _lastViewport;
    if (_isContinuous) {
      if (viewport != null && _continuousLayout != null) {
        _moveContinuousViewport(
          -(_continuousViewportHeight ?? viewport.height),
        );
      }
      return;
    }
    if (_settings.fitMode == PdfFitMode.fitWidth && viewport != null) {
      final starts = await _subScreenStarts(_pageIndex, viewport);
      final idx = _nearestIndex(starts, _withinPage);
      if (idx > 0) {
        _withinPage = starts[idx - 1];
        _afterPositionChanged();
        return;
      }
    }
    if (_pageIndex <= 0) return;
    _pageIndex -= 1;
    if (_settings.fitMode == PdfFitMode.fitWidth && viewport != null) {
      final starts = await _subScreenStarts(_pageIndex, viewport);
      _withinPage = starts.last;
    } else {
      _withinPage = 0.0;
    }
    _afterPositionChanged();
  }

  @override
  Future<void> goToPage(int pageIndex) async {
    if (!_isReady || _pageCount == 0) return;
    _pageIndex = pageIndex.clamp(0, _pageCount - 1).toInt();
    _withinPage = 0.0;
    _continuousCurrentPage = _pageIndex;
    _afterPositionChanged();
  }

  @override
  Future<void> goToToc(TocEntry entry) async {
    final target = entry.position;
    if (!_isReady || _pageCount == 0 || target is! PdfReadingPosition) return;
    _pageIndex = target.pageIndex.clamp(0, _pageCount - 1).toInt();
    _withinPage = target.withinPage;
    _continuousCurrentPage = _pageIndex;
    _afterPositionChanged();
  }

  @override
  Future<void> goToPercent(double pct) async {
    if (!_isReady || _pageCount == 0) return;
    final clamped = clampDouble(pct, 0.0, 1.0);
    _pageIndex = (clamped * _pageCount)
        .floor()
        .clamp(0, _pageCount - 1)
        .toInt();
    _withinPage = 0.0;
    _continuousCurrentPage = _pageIndex;
    _afterPositionChanged();
  }

  @override
  Future<void> addBookmark(String label) async {
    final bookmark = Bookmark(
      id: Bookmark.generateId(),
      docId: doc.id,
      createdAt: DateTime.now(),
      label: label,
      position: position,
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
    final oldSettings = _settings;
    _settings = settings;
    if (oldSettings.fitMode != settings.fitMode) {
      _continuousLayout = null;
      // The incoming view must anchor itself to the preserved logical
      // position rather than wherever its transform happens to sit.
      _navigationEpoch++;
    }
    if (settings.fitMode == PdfFitMode.zoom) {
      _continuousCurrentPage ??= _pageIndex;
    } else {
      _continuousCurrentPage = null;
    }
    notifyListeners();
    _persistState(settingsOverride: settings);
  }

  /// Reports the current render viewport so sub-screen math and prefetch
  /// have something to work with. Called by the reader widget (Step 1.5) on
  /// every layout; cheap to call repeatedly since it no-ops when unchanged.
  void updateViewport(Size size, {double? devicePixelRatio}) {
    _lastViewport = size;
    if (devicePixelRatio != null &&
        devicePixelRatio.isFinite &&
        devicePixelRatio > 0) {
      _lastDevicePixelRatio = devicePixelRatio;
    }
  }

  // ---------------------------------------------------------------------
  // Continuous-scroll geometry and position mapping
  // ---------------------------------------------------------------------

  Future<PdfContinuousLayout> continuousLayoutForViewport(Size viewport) async {
    if (!_isReady || viewport.width <= 0 || viewport.height <= 0) {
      throw StateError('Cannot prepare continuous layout before opening');
    }
    updateViewport(viewport);
    final cached = _continuousLayout;
    if (cached != null && cached.viewportWidth == viewport.width) return cached;

    // Zoom / scroll always uses one stable document-wide crop. A per-page or
    // user-disabled crop would change page geometry while panning.
    final crop = await _resolveUniformCropRect();
    final pageSizes = List<Size>.generate(_pageCount, (pageIndex) {
      final info = _documentService!.pageInfo(pageIndex);
      return Size(info.width, info.height);
    }, growable: false);
    final layout = PdfContinuousLayout.fromPageSizes(
      pageSizes: pageSizes,
      viewportWidth: viewport.width,
      cropWidth: crop.width,
      cropHeight: crop.height,
    );
    _continuousLayout = layout;
    _continuousViewportHeight = viewport.height;
    _continuousCurrentPage = layout.dominantPage(
      layout.offsetForPosition(
        position as PdfReadingPosition,
        viewportHeight: viewport.height,
      ),
      viewport.height,
    );
    return layout;
  }

  double continuousOffsetForPosition(
    PdfContinuousLayout layout,
    double viewportHeight,
  ) {
    return layout.offsetForPosition(
      position as PdfReadingPosition,
      viewportHeight: viewportHeight,
    );
  }

  /// Records a user-driven scroll without rebuilding on every drag pixel.
  /// Listeners are notified only when the dominant page shown in the menu
  /// changes, and the navigation epoch is deliberately left untouched so the
  /// view never fights the user's own pan or fling.
  void updateContinuousScrollOffset(
    double offset,
    PdfContinuousLayout layout,
    double viewportHeight,
  ) {
    if (!_isContinuous) return;
    _continuousViewportHeight = viewportHeight;
    final logical = layout.positionForOffset(offset);
    final dominant = layout.dominantPage(offset, viewportHeight);
    final pageChanged = dominant != _continuousCurrentPage;
    final logicalPageChanged = logical.pageIndex != _pageIndex;
    _pageIndex = logical.pageIndex;
    _withinPage = logical.withinPage;
    _continuousCurrentPage = dominant;
    // Rebuilding a BookState on every transform tick would allocate through
    // an entire fling; page boundaries plus suspend() are enough.
    if (pageChanged || logicalPageChanged) _persistState();
    if (pageChanged) notifyListeners();
  }

  void _moveContinuousViewport(double delta) {
    final layout = _continuousLayout;
    final viewport = _lastViewport;
    if (layout == null || viewport == null) return;
    final visibleHeight = _continuousViewportHeight ?? viewport.height;
    final current = continuousOffsetForPosition(layout, visibleHeight);
    final target = (current + delta)
        .clamp(0.0, layout.maxScrollOffset(visibleHeight))
        .toDouble();
    final logical = layout.positionForOffset(target);
    _pageIndex = logical.pageIndex;
    _withinPage = logical.withinPage;
    _continuousCurrentPage = layout.dominantPage(target, visibleHeight);
    _afterPositionChanged();
  }

  // ---------------------------------------------------------------------
  // Rendering
  // ---------------------------------------------------------------------

  /// Renders (or returns from cache) the bitmap for the current position at
  /// [viewport]. Used by the tap-driven fit-height and fit-width modes only:
  /// Zoom / Scroll is always continuous and renders through
  /// [renderContinuousTile].
  /// The caller owns the returned image handle and must dispose it.
  Future<Image> renderCurrentView(
    Size viewport, {
    double devicePixelRatio = 1.0,
  }) async {
    if (!_isReady) {
      throw StateError('Cannot render: session for ${doc.title} is not ready');
    }
    if (_isContinuous) {
      throw StateError(
        'Zoom / Scroll renders through renderContinuousTile, not whole pages',
      );
    }
    updateViewport(viewport, devicePixelRatio: devicePixelRatio);
    return _renderPageAt(
      _pageIndex,
      _withinPage,
      viewport,
      devicePixelRatio: devicePixelRatio,
    );
  }

  /// Rasterises one tile of [pageIndex] for the continuous view.
  /// The caller owns the returned image handle and must dispose it.
  ///
  /// [region] is the tile's rectangle within the page, expressed as fractions
  /// of the page's laid-out size (`0..1` on both axes). Tiling in *two*
  /// dimensions is what keeps deep zoom affordable: the number of device
  /// pixels on screen is constant regardless of zoom, so only a handful of
  /// tiles are ever needed. Rendering full-width strips instead forced
  /// enormous bitmaps that hit the dimension cap and came back downscaled —
  /// which is what made zoomed pages look blurry.
  ///
  /// [renderScale] is the quantised pinch zoom, pushed all the way down into
  /// PDFium so vector content is genuinely re-rasterised rather than
  /// magnified as a bitmap.
  Future<Image> renderContinuousTile(
    int pageIndex,
    PdfContinuousLayout layout, {
    double devicePixelRatio = 1.0,
    double renderScale = 1.0,
    Rect region = const Rect.fromLTRB(0, 0, 1, 1),
  }) async {
    if (!_isReady || !_isContinuous) {
      throw StateError('Continuous PDF rendering is not active');
    }
    final generation = _generation;
    if (pageIndex < 0 || pageIndex >= layout.pageHeights.length) {
      throw RangeError.index(pageIndex, layout.pageHeights, 'pageIndex');
    }
    final crop = await _resolveUniformCropRect();
    _checkGeneration(generation);

    final left = clampDouble(region.left, 0.0, 0.9999);
    final right = clampDouble(region.right, left + 0.0001, 1.0);
    final top = clampDouble(region.top, 0.0, 0.9999);
    final bottom = clampDouble(region.bottom, top + 0.0001, 1.0);
    final tileCrop = PdfCropRect(
      left: crop.left + left * crop.width,
      top: crop.top + top * crop.height,
      right: crop.left + right * crop.width,
      bottom: crop.top + bottom * crop.height,
    );

    final density = devicePixelRatio * renderScale;
    final pixelWidth = math.max(
      1,
      (layout.viewportWidth * (right - left) * density).round(),
    );
    final pixelHeight = math.max(
      1,
      (layout.pageHeights[pageIndex] * (bottom - top) * density).round(),
    );

    final key = PdfBitmapCacheKey(
      pageIndex: pageIndex,
      pixelWidth: pixelWidth,
      pixelHeight: pixelHeight,
      cropLeft: tileCrop.left,
      cropTop: tileCrop.top,
      cropRight: tileCrop.right,
      cropBottom: tileCrop.bottom,
    );
    final cached = _bitmapCache.get(key);
    if (cached != null) return cached.clone();
    final image = await _documentService!.renderPage(
      pageIndex: pageIndex,
      pixelWidth: pixelWidth,
      pixelHeight: pixelHeight,
      crop: tileCrop,
      maxDimension: kPdfMaxTileDimension,
    );
    if (_disposed || generation != _generation) {
      image.dispose();
      throw StateError('PDF rendering was cancelled.');
    }
    return _cacheAndOwn(key, image);
  }

  Future<Image> _renderPageAt(
    int pageIndex,
    double withinPage,
    Size viewport, {
    double devicePixelRatio = 1.0,
  }) async {
    final generation = _generation;
    final crop = await _resolveCropRect(pageIndex);
    _checkGeneration(generation);
    final info = _documentService!.pageInfo(pageIndex);
    final geometry = _geometryFor(
      info,
      crop,
      viewport,
      withinPage,
      devicePixelRatio,
    );

    final key = PdfBitmapCacheKey(
      pageIndex: pageIndex,
      pixelWidth: geometry.pixelWidth,
      pixelHeight: geometry.pixelHeight,
      cropLeft: geometry.crop.left,
      cropTop: geometry.crop.top,
      cropRight: geometry.crop.right,
      cropBottom: geometry.crop.bottom,
    );
    final cached = _bitmapCache.get(key);
    if (cached != null) return cached.clone();

    final image = await _documentService!.renderPage(
      pageIndex: pageIndex,
      pixelWidth: geometry.pixelWidth,
      pixelHeight: geometry.pixelHeight,
      crop: geometry.crop,
    );
    if (_disposed || generation != _generation) {
      image.dispose();
      throw StateError('PDF rendering was cancelled.');
    }
    return _cacheAndOwn(key, image);
  }

  Image _cacheAndOwn(PdfBitmapCacheKey key, Image image) {
    // Clone before insertion: concurrent render completion can replace/evict
    // an entry before the widget receives its Future. Oversized bitmaps are
    // not cached; their original handle transfers to the caller instead.
    final owned = image.clone();
    if (_bitmapCache.put(key, image)) return owned;
    owned.dispose();
    return image;
  }

  /// Computes output pixel size and the (possibly sub-screen-sliced) crop
  /// rect to render, for the current [ReaderSettings.fitMode].
  ({int pixelWidth, int pixelHeight, PdfCropRect crop}) _geometryFor(
    PdfPageInfo info,
    PdfCropRect crop,
    Size viewport,
    double withinPage,
    double devicePixelRatio,
  ) {
    final croppedWidth = info.width * crop.width;
    final croppedHeight = info.height * crop.height;

    switch (_settings.fitMode) {
      case PdfFitMode.fitHeight:
        final pixelHeight = (viewport.height * devicePixelRatio).round();
        final pixelWidth =
            (viewport.height * croppedWidth / croppedHeight * devicePixelRatio)
                .round();
        return (pixelWidth: pixelWidth, pixelHeight: pixelHeight, crop: crop);

      case PdfFitMode.fitWidth:
        final scale = viewport.width / croppedWidth;
        final scaledHeight = croppedHeight * scale;
        final subFracHeight = scaledHeight <= 0
            ? 1.0
            : clampDouble(viewport.height / scaledHeight, 0.0, 1.0);
        final top = clampDouble(
          crop.top + withinPage * crop.height,
          crop.top,
          crop.bottom - 0.0001,
        );
        final bottom = clampDouble(
          top + subFracHeight * crop.height,
          top + 0.0001,
          crop.bottom,
        );
        final subCrop = PdfCropRect(
          left: crop.left,
          top: top,
          right: crop.right,
          bottom: bottom,
        );
        return (
          pixelWidth: (viewport.width * devicePixelRatio).round(),
          pixelHeight: (viewport.height * devicePixelRatio).round(),
          crop: subCrop,
        );

      case PdfFitMode.zoom:
        // Zoom / Scroll is exclusively continuous. Rendering a whole page
        // here and letting a transform magnify it is what used to make
        // zoomed vector PDFs blurry, so there is no such path any more.
        throw StateError(
          'Zoom / Scroll geometry is owned by PdfContinuousLayout',
        );
    }
  }

  /// The vertical start fractions (of the *cropped* page) for each
  /// fit-width sub-screen, spaced one viewport height apart minus the
  /// configured overlap. `[0.0]` when the page fits in one screen.
  Future<List<double>> _subScreenStarts(int pageIndex, Size viewport) async {
    final crop = await _resolveCropRect(pageIndex);
    final info = _documentService!.pageInfo(pageIndex);
    final croppedWidth = info.width * crop.width;
    final croppedHeight = info.height * crop.height;
    if (croppedWidth <= 0 ||
        croppedHeight <= 0 ||
        viewport.width <= 0 ||
        viewport.height <= 0) {
      return const [0.0];
    }

    final scale = viewport.width / croppedWidth;
    final scaledHeight = croppedHeight * scale;
    if (scaledHeight <= viewport.height) return const [0.0];

    final overlap = clampDouble(_settings.splitOverlap, 0.0, 0.9);
    final step = viewport.height * (1 - overlap);
    final starts = <double>[0.0];
    var offset = step;
    while (offset < scaledHeight - viewport.height) {
      starts.add(offset / scaledHeight);
      offset += step;
    }
    // Anchor the final sub-screen to the bottom of the page so nothing past
    // the last line is ever left off-screen.
    starts.add(
      clampDouble((scaledHeight - viewport.height) / scaledHeight, 0.0, 1.0),
    );
    return starts;
  }

  static int _nearestIndex(List<double> values, double target) {
    var bestIndex = 0;
    var bestDelta = double.infinity;
    for (var i = 0; i < values.length; i++) {
      final delta = (values[i] - target).abs();
      if (delta < bestDelta) {
        bestDelta = delta;
        bestIndex = i;
      }
    }
    return bestIndex;
  }

  Future<PdfCropRect> _resolveCropRect(int pageIndex) async {
    final generation = _generation;
    if (!_settings.autoCrop) return PdfCropRect.fullPage;
    final cached = _cropRectCache[pageIndex];
    if (cached != null) return cached;
    final page = _documentService!.pageAt(pageIndex);
    final detected = await _cropService.detectPageCrop(page);
    _checkGeneration(generation);
    _cropRectCache[pageIndex] = detected;
    _persistState();
    return detected;
  }

  Future<PdfCropRect> _resolveUniformCropRect() async {
    final generation = _generation;
    final cached = _uniformCropRect;
    if (cached != null) return cached;
    final detected = await _cropService.detectDocumentCrop(
      pageCount: _pageCount,
      pageAt: _documentService!.pageAt,
    );
    _checkGeneration(generation);
    _uniformCropRect = detected;
    _persistState();
    return detected;
  }

  // ---------------------------------------------------------------------
  // Prefetch
  // ---------------------------------------------------------------------

  void _prefetchNeighbors() {
    if (_isContinuous) return;
    unawaited(_prefetchPage(_pageIndex + 1));
    unawaited(_prefetchPage(_pageIndex - 1));
  }

  Future<void> _prefetchPage(int pageIndex) async {
    final viewport = _lastViewport;
    if (viewport == null || pageIndex < 0 || pageIndex >= _pageCount) return;
    if (!_isReady || _isSuspended || _isContinuous) return;
    try {
      final image = await _renderPageAt(
        pageIndex,
        0.0,
        viewport,
        devicePixelRatio: _lastDevicePixelRatio,
      );
      image.dispose();
    } catch (_) {
      // Best-effort: a failed prefetch must never surface to the reader UI.
    }
  }

  // ---------------------------------------------------------------------
  // Persistence
  // ---------------------------------------------------------------------

  Future<void> _loadToc(int generation) async {
    try {
      final toc = await _documentService!.loadOutline();
      if (_disposed || generation != _generation) return;
      _toc = toc;
    } catch (_) {
      if (_disposed || generation != _generation) return;
      _toc = const [];
    }
    notifyListeners();
  }

  void _restorePersistedState() {
    final saved = _bookStore.getBookState(doc.id);
    _settings = _bookStore.getSettingsForDoc(doc.id);
    if (saved == null) {
      _pageIndex = 0;
      _withinPage = 0.0;
      return;
    }
    final position = saved.position;
    if (position is PdfReadingPosition) {
      _pageIndex = position.pageIndex.clamp(0, _pageCount - 1).toInt();
      _withinPage = position.withinPage;
    }
    _bookmarks = saved.bookmarks;
    _cropRectCache
      ..clear()
      ..addEntries(
        saved.cachedCropRects.entries.map(
          (e) => MapEntry(e.key, PdfCropRect.fromList(e.value)),
        ),
      );
    final uniformCrop = saved.uniformPdfCrop;
    _uniformCropRect = uniformCrop == null
        ? null
        : PdfCropRect.fromList(uniformCrop);
  }

  void _afterPositionChanged() {
    _navigationEpoch++;
    notifyListeners();
    _persistState();
    _prefetchNeighbors();
  }

  void _persistState({ReaderSettings? settingsOverride}) {
    if (!_hasOpened) return;
    final existing = _bookStore.getBookState(doc.id);
    _bookStore.saveBookState(
      BookState(
        docId: doc.id,
        lastPath: doc.path,
        format: doc.format,
        lastRead: DateTime.now(),
        position: position,
        percent: percent,
        settingsOverride: settingsOverride ?? existing?.settingsOverride,
        bookmarks: _bookmarks,
        cachedCropRects: {
          for (final entry in _cropRectCache.entries)
            entry.key: entry.value.toList(),
        },
        uniformPdfCrop: _uniformCropRect?.toList(),
      ),
    );
  }

  void _checkGeneration(int generation) {
    if (_disposed || generation != _generation || !_isReady) {
      throw StateError('PDF operation was cancelled.');
    }
  }
}

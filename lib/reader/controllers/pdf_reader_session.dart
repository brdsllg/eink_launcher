import 'dart:async';
import 'dart:ui';

// NOTE: `num.clamp()` always returns `num`, even when called on an `int` or
// `double` receiver, which does not implicitly convert back to the field or
// parameter type it's assigned to. `clampDouble` (dart:ui) is used for
// double results below; int results go through `.clamp(...).toInt()`.

import '../../constants.dart';
import '../models/book_state.dart';
import '../models/doc_ref.dart';
import '../models/reader_settings.dart';
import '../models/reading_position.dart';
import '../models/toc_entry.dart';
import '../services/book_store_service.dart';
import '../services/page_bitmap_cache.dart';
import '../services/pdf_crop_service.dart';
import '../services/pdf_document_service.dart';
import 'reader_session.dart';

typedef PdfDocumentServiceFactory = PdfDocumentService Function(String path);

/// The [ReaderSession] implementation for PDF documents.
///
/// Owns a [PdfDocumentService] (native PDFium handle), a [PageBitmapCache]
/// (rendered page bitmaps), and a [PdfCropService] (auto-crop detection).
/// Position is tracked as `(pageIndex, withinPage)` per READER_PLAN.md §1.B:
/// `withinPage` is `0.0` in fit-height and free-zoom, and the sub-screen's
/// vertical start fraction in fit-width — this is what lets switching fit
/// mode mid-document keep your place.
class PdfReaderSession extends ReaderSession {
  @override
  final DocRef doc;

  final BookStoreService _bookStore;
  final PdfCropService _cropService;
  final PageBitmapCache _bitmapCache;
  final PdfDocumentServiceFactory _serviceFactory;

  PdfDocumentService? _documentService;

  bool _isReady = false;
  bool _isSuspended = false;
  String? _error;

  int _pageCount = 0;
  int _pageIndex = 0;
  double _withinPage = 0.0;
  List<TocEntry> _toc = const [];
  ReaderSettings _settings = const ReaderSettings();
  final Map<int, PdfCropRect> _cropRectCache = {};

  /// Last viewport size reported by the reader widget (Step 1.5). Sub-screen
  /// math and prefetching are no-ops until this is known.
  Size? _lastViewport;

  PdfReaderSession({
    required this.doc,
    BookStoreService? bookStore,
    PdfCropService? cropService,
    PageBitmapCache? bitmapCache,
    PdfDocumentServiceFactory? documentServiceFactory,
  }) : _bookStore = bookStore ?? BookStoreService.instance,
       _cropService = cropService ?? PdfCropService(),
       _bitmapCache = bitmapCache ?? PageBitmapCache(),
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
  int get currentPage => _pageIndex;

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

  // ---------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------

  @override
  Future<void> open() async {
    _documentService ??= _serviceFactory(doc.path);
    try {
      await _documentService!.open();
      _pageCount = _documentService!.pageCount;
      _restorePersistedState();
      _isReady = true;
      _isSuspended = false;
      _error = null;
      unawaited(_loadToc());
    } catch (e) {
      _error = 'Failed to open ${doc.title}: $e';
      _isReady = false;
    }
    notifyListeners();
  }

  @override
  void suspend() {
    if (_isSuspended) return;
    _isSuspended = true;
    _isReady = false;
    _bitmapCache.clear();
    unawaited(_documentService?.close());
    notifyListeners();
  }

  @override
  Future<void> resume() async {
    if (!_isSuspended) return;
    try {
      _documentService ??= _serviceFactory(doc.path);
      await _documentService!.open();
      _isSuspended = false;
      _isReady = true;
      _error = null;
      notifyListeners();
    } catch (e) {
      _error = 'Failed to resume ${doc.title}: $e';
      notifyListeners();
      rethrow;
    }
  }

  @override
  void dispose() {
    _bitmapCache.clear();
    unawaited(_documentService?.close());
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // Navigation
  // ---------------------------------------------------------------------

  @override
  Future<void> nextPage() async {
    if (!_isReady) return;
    final viewport = _lastViewport;
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
    _afterPositionChanged();
  }

  @override
  Future<void> goToToc(TocEntry entry) async {
    final target = entry.position;
    if (!_isReady || _pageCount == 0 || target is! PdfReadingPosition) return;
    _pageIndex = target.pageIndex.clamp(0, _pageCount - 1).toInt();
    _withinPage = target.withinPage;
    _afterPositionChanged();
  }

  @override
  Future<void> goToPercent(double pct) async {
    if (!_isReady || _pageCount == 0) return;
    final clamped = clampDouble(pct, 0.0, 1.0);
    _pageIndex = (clamped * _pageCount).floor().clamp(0, _pageCount - 1).toInt();
    _withinPage = 0.0;
    _afterPositionChanged();
  }

  @override
  Future<void> applySettings(ReaderSettings settings) async {
    _settings = settings;
    notifyListeners();
    _persistState(settingsOverride: settings);
  }

  /// Reports the current render viewport so sub-screen math and prefetch
  /// have something to work with. Called by the reader widget (Step 1.5) on
  /// every layout; cheap to call repeatedly since it no-ops when unchanged.
  void updateViewport(Size size) {
    if (size == _lastViewport) return;
    _lastViewport = size;
  }

  // ---------------------------------------------------------------------
  // Rendering
  // ---------------------------------------------------------------------

  /// Renders (or returns from cache) the bitmap for the current position at
  /// [viewport]. This is the render pipeline the dedicated `pdf_page_view.dart`
  /// widget (Step 1.5) is expected to call; the session owns the fit-mode
  /// geometry and crop resolution so that widget stays a thin presenter.
  Future<Image> renderCurrentView(Size viewport) async {
    if (!_isReady) {
      throw StateError('Cannot render: session for ${doc.title} is not ready');
    }
    updateViewport(viewport);
    return _renderPageAt(_pageIndex, _withinPage, viewport);
  }

  Future<Image> _renderPageAt(
    int pageIndex,
    double withinPage,
    Size viewport,
  ) async {
    final crop = await _resolveCropRect(pageIndex);
    final info = _documentService!.pageInfo(pageIndex);
    final geometry = _geometryFor(info, crop, viewport, withinPage);

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
    if (cached != null) return cached;

    final image = await _documentService!.renderPage(
      pageIndex: pageIndex,
      pixelWidth: geometry.pixelWidth,
      pixelHeight: geometry.pixelHeight,
      crop: geometry.crop,
    );
    _bitmapCache.put(key, image);
    return image;
  }

  /// Computes output pixel size and the (possibly sub-screen-sliced) crop
  /// rect to render, for the current [ReaderSettings.fitMode].
  ///
  /// Continuous scroll (Phase 1b) is treated as fit-height for now — one
  /// full top-anchored page per screen — until the cumulative height table
  /// and scrollable view land.
  ({int pixelWidth, int pixelHeight, PdfCropRect crop}) _geometryFor(
    PdfPageInfo info,
    PdfCropRect crop,
    Size viewport,
    double withinPage,
  ) {
    final croppedWidth = info.width * crop.width;
    final croppedHeight = info.height * crop.height;

    switch (_settings.fitMode) {
      case PdfFitMode.fitHeight:
      case PdfFitMode.continuousScroll:
        final pixelHeight = viewport.height.round();
        final pixelWidth = (viewport.height * croppedWidth / croppedHeight)
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
          pixelWidth: viewport.width.round(),
          pixelHeight: viewport.height.round(),
          crop: subCrop,
        );

      case PdfFitMode.freeZoom:
        // Base render for InteractiveViewer (Step 1.5) to scale further; go
        // as large as the shared render ceiling allows.
        final aspect = croppedWidth / croppedHeight;
        var pixelWidth = kPdfMaxRenderDimension.round();
        var pixelHeight = (kPdfMaxRenderDimension / aspect).round();
        if (pixelHeight > kPdfMaxRenderDimension) {
          pixelHeight = kPdfMaxRenderDimension.round();
          pixelWidth = (kPdfMaxRenderDimension * aspect).round();
        }
        return (
          pixelWidth: pixelWidth,
          pixelHeight: pixelHeight,
          crop: crop,
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
    if (!_settings.autoCrop) return PdfCropRect.fullPage;
    final cached = _cropRectCache[pageIndex];
    if (cached != null) return cached;
    final page = _documentService!.pageAt(pageIndex);
    final detected = await _cropService.detectPageCrop(page);
    _cropRectCache[pageIndex] = detected;
    _persistState();
    return detected;
  }

  // ---------------------------------------------------------------------
  // Prefetch
  // ---------------------------------------------------------------------

  void _prefetchNeighbors() {
    unawaited(_prefetchPage(_pageIndex + 1));
    unawaited(_prefetchPage(_pageIndex - 1));
  }

  Future<void> _prefetchPage(int pageIndex) async {
    final viewport = _lastViewport;
    if (viewport == null || pageIndex < 0 || pageIndex >= _pageCount) return;
    if (!_isReady || _isSuspended) return;
    try {
      await _renderPageAt(pageIndex, 0.0, viewport);
    } catch (_) {
      // Best-effort: a failed prefetch must never surface to the reader UI.
    }
  }

  // ---------------------------------------------------------------------
  // Persistence
  // ---------------------------------------------------------------------

  Future<void> _loadToc() async {
    try {
      _toc = await _documentService!.loadOutline();
    } catch (_) {
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
    _cropRectCache
      ..clear()
      ..addEntries(
        saved.cachedCropRects.entries.map(
          (e) => MapEntry(e.key, PdfCropRect.fromList(e.value)),
        ),
      );
  }

  void _afterPositionChanged() {
    notifyListeners();
    _persistState();
    _prefetchNeighbors();
  }

  void _persistState({ReaderSettings? settingsOverride}) {
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
        bookmarks: existing?.bookmarks ?? const [],
        cachedCropRects: {
          for (final entry in _cropRectCache.entries)
            entry.key: entry.value.toList(),
        },
      ),
    );
  }
}

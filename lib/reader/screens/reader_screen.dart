import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../constants.dart';
import '../../widgets/adaptive_grid.dart';
import '../../widgets/page_button_scope.dart';
import '../controllers/pdf_reader_session.dart';
import '../controllers/reader_session.dart';
import '../controllers/reader_session_registry.dart';
import '../controllers/text_reader_session.dart';
import '../models/bookmark.dart';
import '../models/doc_ref.dart';
import '../models/reader_settings.dart';
import '../models/reading_position.dart';
import '../models/toc_entry.dart';
import '../services/book_store_service.dart';
import '../services/reader_error_service.dart';
import '../services/pdf_render_scheduler.dart';
import '../services/pdf_thumbnail_cache_service.dart';
import '../services/text_search_service.dart';
import '../widgets/pdf_page_view.dart';
import '../widgets/reader_menu_overlay.dart';
import '../widgets/reader_error_view.dart';
import '../widgets/reader_tab_strip.dart';
import '../widgets/tap_zone_layer.dart';
import '../widgets/text_page_view.dart';
import 'reader_bookmarks_screen.dart';
import 'reader_search_screen.dart';
import 'reader_settings_screen.dart';
import 'reader_toc_screen.dart';

/// Full-bleed, format-agnostic reader shell.
///
class ReaderScreen extends StatefulWidget {
  final DocRef doc;
  final ReaderSessionRegistry registry;
  final Future<ui.Image?> Function(String docId) openingPreviewLoader;

  ReaderScreen({
    super.key,
    required this.doc,
    ReaderSessionRegistry? registry,
    Future<ui.Image?> Function(String docId)? openingPreviewLoader,
  }) : registry = registry ?? ReaderSessionRegistry.instance,
       openingPreviewLoader =
           openingPreviewLoader ??
           PdfThumbnailCacheService.instance.loadOpeningPreview;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen>
    with WidgetsBindingObserver {
  ReaderSession? _session;
  late DocRef _doc;
  ui.Image? _openingPreview;
  int _loadGeneration = 0;
  int _contentGeneration = 0;
  bool _waitingForContent = true;
  bool _backgrounded = false;
  String? _loadError;
  bool _menuVisible = true;
  bool _navigating = false;
  bool _loadingSession = false;
  bool _memoryPaused = false;
  bool _shownStateWarning = false;

  @override
  void initState() {
    super.initState();
    _doc = widget.doc;
    WidgetsBinding.instance.addObserver(this);
    widget.registry.addListener(_tabsChanged);
    unawaited(_loadSession());
  }

  void _tabsChanged() {
    if (mounted) setState(() {});
  }

  bool _isCurrentLoad(int generation) =>
      mounted &&
      generation == _loadGeneration &&
      !_backgrounded &&
      !_memoryPaused;

  void _clearOpeningPreview() {
    final previous = _openingPreview;
    _openingPreview = null;
    if (previous != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
    }
  }

  Future<void> _readOpeningPreview(DocRef doc, int generation) async {
    try {
      final image = await widget.openingPreviewLoader(doc.id);
      if (!_isCurrentLoad(generation) || !_waitingForContent) {
        image?.dispose();
        return;
      }
      setState(() => _openingPreview = image);
    } catch (_) {
      // A missing or unreadable optional cache must never prevent opening a book.
    }
  }

  Future<void> _loadSession({DocRef? doc}) async {
    final target = doc ?? _doc;
    final generation = ++_loadGeneration;
    final retained = widget.registry.sessionFor(target.id);
    final ready =
        retained != null &&
        retained.isReady &&
        !retained.isSuspended &&
        retained.doc.path == target.path;
    setState(() {
      _doc = target;
      _session = ready ? retained : null;
      _loadingSession = !ready;
      _waitingForContent = !ready;
      if (!ready) ++_contentGeneration;
      _menuVisible = true;
      _navigating = false;
      _loadError = null;
      _clearOpeningPreview();
    });
    // Register immediately: Back must retain even an opening tab while the
    // library is still being read. Restoration merges these local changes.
    widget.registry.selectTab(target);
    if (!ready && target.format == DocFormat.pdf) {
      unawaited(_readOpeningPreview(target, generation));
    }
    try {
      await widget.registry.restoreTabs();
      if (!mounted || !_isCurrentLoad(generation)) return;
      final warning = BookStoreService.instance.recoveryWarning;
      if (warning != null && !_shownStateWarning) {
        _shownStateWarning = true;
        await showDialog<void>(
          context: context,
          animationStyle: AnimationStyle.noAnimation,
          builder: (context) => GridDialog(
            title: const Text('Reading state'),
            content: Text(warning),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Continue'),
              ),
            ],
          ),
        );
        if (!_isCurrentLoad(generation)) return;
      }
      final session = await widget.registry.obtain(target);
      if (!_isCurrentLoad(generation)) return;
      setState(() {
        _session = session;
        _loadError = null;
        if (session.error != null || !session.isReady) {
          _waitingForContent = false;
          _clearOpeningPreview();
        }
      });
      await _applyOrientation(session.settings.landscape);
    } catch (error) {
      if (!_isCurrentLoad(generation)) return;
      setState(() {
        _loadError = readerErrorMessage(error, target.format);
        _waitingForContent = false;
        _clearOpeningPreview();
      });
    } finally {
      if (_isCurrentLoad(generation)) setState(() => _loadingSession = false);
    }
  }

  void _switchTab(DocRef doc) {
    if (doc.id == _doc.id && !_memoryPaused) return;
    _memoryPaused = false;
    unawaited(_loadSession(doc: doc));
  }

  void _closeTab(DocRef doc) {
    final closingCurrent = doc.id == _doc.id;
    if (closingCurrent) {
      ++_loadGeneration;
      _session = null;
      _clearOpeningPreview();
    }
    final next = widget.registry.closeTab(doc.id);
    if (!closingCurrent) return;
    if (next == null) {
      Navigator.of(context).pop();
    } else {
      _memoryPaused = false;
      unawaited(_loadSession(doc: next));
    }
  }

  void _contentReady(int generation) {
    if (!_isCurrentLoad(generation) || !_waitingForContent) return;
    setState(() {
      _waitingForContent = false;
      _clearOpeningPreview();
    });
  }

  Future<void> _resumeSession() async {
    if (!_memoryPaused) await _loadSession();
  }

  Future<void> _retry() async {
    if (_loadingSession) return;
    _memoryPaused = false;
    _session?.suspend();
    await _loadSession();
  }

  @override
  void didHaveMemoryPressure() {
    if (!mounted) return;
    setState(() {
      ++_loadGeneration;
      _memoryPaused = true;
      _loadingSession = false;
      _waitingForContent = false;
      _menuVisible = false;
      _clearOpeningPreview();
    });
    // The app-lifetime ReaderMemoryPressureObserver releases all sessions,
    // including hidden ones. This observer only manages the visible fallback.
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    unawaited(BookStoreService.instance.flush());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _backgrounded = false;
        unawaited(_resumeSession());
      case AppLifecycleState.inactive:
        unawaited(BookStoreService.instance.flush());
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _backgrounded = true;
        ++_loadGeneration;
        widget.registry.suspendAll();
        unawaited(BookStoreService.instance.flush());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.registry.removeListener(_tabsChanged);
    ++_loadGeneration;
    _clearOpeningPreview();
    final session = _session ?? widget.registry.sessionFor(_doc.id);
    if (session is PdfReaderSession) session.cancelPendingWork();
    unawaited(BookStoreService.instance.flush());
    unawaited(SystemChrome.setPreferredOrientations(const []));
    super.dispose();
  }

  Future<void> _navigate(
    Future<void> Function() operation, {
    bool orderedPdfTurn = false,
  }) async {
    // PDF sessions preserve ordered turn intent themselves. Locking here drops
    // taps while Fit Width waits for crop geometry, and blocks superseding jumps.
    final lockNavigation = !orderedPdfTurn;
    if (lockNavigation && _navigating) return;
    if (lockNavigation) _navigating = true;
    final generation = _loadGeneration;
    try {
      await operation();
      if (_isCurrentLoad(generation)) setState(() => _loadError = null);
    } on PdfRenderCancelledException {
      // Normal supersession from navigation, settings, or suspension.
    } catch (error) {
      if (_isCurrentLoad(generation)) {
        setState(() => _loadError = readerErrorMessage(error, _doc.format));
      }
    } finally {
      if (lockNavigation && generation == _loadGeneration) _navigating = false;
    }
  }

  Future<void> _applyOrientation(bool landscape) {
    return SystemChrome.setPreferredOrientations(
      landscape
          ? const [DeviceOrientation.landscapeLeft]
          : const [DeviceOrientation.portraitUp],
    );
  }

  Future<void> _applySettings(ReaderSettings settings) async {
    final session = _session;
    if (session == null) return;
    final generation = _loadGeneration;
    await _navigate(() async {
      await session.applySettings(settings);
      if (_isCurrentLoad(generation)) {
        await _applyOrientation(settings.landscape);
      }
    });
  }

  Future<void> _openSettings() async {
    final session = _session;
    if (session == null) return;
    final settings = await Navigator.of(context).push<ReaderSettings>(
      noTransitionRoute(
        ReaderSettingsScreen(
          initialSettings: session.settings,
          format: session.doc.format,
        ),
      ),
    );
    if (settings != null && mounted) await _applySettings(settings);
  }

  Future<void> _showPageJump() async {
    final session = _session;
    if (session == null || session.pageCount == 0) return;
    final controller = TextEditingController(
      text: (session.currentPage + 1).toString(),
    );
    final page = await showDialog<int>(
      context: context,
      animationStyle: AnimationStyle.noAnimation,
      builder: (context) => GridDialog(
        title: Text('Go to page (1–${session.pageCount})'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: 'Page',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) {
            final parsed = int.tryParse(value);
            if (parsed != null) Navigator.of(context).pop(parsed);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(int.tryParse(controller.text)),
            child: const Text('Go'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (page == null || !mounted) return;
    await _navigate(
      () => session.goToPage(page.clamp(1, session.pageCount).toInt() - 1),
    );
  }

  Future<void> _showPercentJump() async {
    final session = _session;
    if (session == null) return;
    final controller = TextEditingController(
      text: (session.percent * 100).round().toString(),
    );
    final percent = await showDialog<int>(
      context: context,
      animationStyle: AnimationStyle.noAnimation,
      builder: (context) => GridDialog(
        title: const Text('Go to percent'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: 'Percent (0–100)',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) =>
              Navigator.of(context).pop(int.tryParse(value)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(int.tryParse(controller.text)),
            child: const Text('Go'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (percent == null || !mounted) return;
    await _navigate(() => session.goToPercent(percent.clamp(0, 100) / 100));
  }

  Future<void> _openToc() async {
    final session = _session;
    if (session == null || session.toc.isEmpty) return;
    final entry = await Navigator.of(context)
        .push(noTransitionRoute(ReaderTocScreen(entries: session.toc)));
    if (entry != null && mounted) await _navigate(() => session.goToToc(entry));
  }

  Future<void> _openBookmarks() async {
    final session = _session;
    if (session == null) return;
    final bookmark = await Navigator.of(context).push<Bookmark>(
      noTransitionRoute(ReaderBookmarksScreen(session: session)),
    );
    if (bookmark == null || !mounted) return;
    // Bookmarks reuse the TOC's own jump machinery — both are just a title
    // plus a logical position as far as the session is concerned.
    await _navigate(
      () => session.goToToc(
        TocEntry(title: bookmark.label, position: bookmark.position),
      ),
    );
  }

  Future<void> _openSearch() async {
    final session = _session;
    if (session is! TextReaderSession || session.book == null) return;
    final match = await Navigator.of(context).push<TextSearchMatch>(
      noTransitionRoute(ReaderSearchScreen(spine: session.book!.spine)),
    );
    if (match == null || !mounted) return;
    await _navigate(
      () => session.goToToc(
        TocEntry(title: match.chapterTitle, position: match.position),
      ),
    );
    if (mounted) setState(() => _menuVisible = false);
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    if (session == null) return _buildShell(null);
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) => _buildShell(session),
    );
  }

  Widget _tabStrip() => ReaderTabStrip(
    tabs: widget.registry.tabs,
    selectedTabId: _doc.id,
    onSelect: _switchTab,
    onClose: _closeTab,
  );

  void _turnFromButton(ReaderSession session, {required bool forward}) {
    if (_menuVisible) setState(() => _menuVisible = false);
    unawaited(
      _navigate(
        forward ? session.nextPage : session.prevPage,
        orderedPdfTurn: session is PdfReaderSession,
      ),
    );
  }

  Widget _buildShell(ReaderSession? session) {
    final error = _memoryPaused
        ? 'Reading was paused to free memory. Your position has been saved.'
        : session?.error ??
              _loadError ??
              (!_loadingSession && session?.isReady != true
                  ? 'Reader is paused'
                  : null);
    if (error != null) {
      return Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              _tabStrip(),
              Expanded(
                child: ReaderErrorView(
                  message: error,
                  onRetry: _retry,
                  retryLabel: _memoryPaused ? 'Continue reading' : 'Retry',
                ),
              ),
            ],
          ),
        ),
      );
    }
    final loading = _loadingSession || _waitingForContent;
    final state = BookStoreService.instance.getBookState(_doc.id);
    final settings =
        session?.settings ??
        BookStoreService.instance.getSettingsForDoc(_doc.id);
    final savedPosition = state?.position;
    final isPdf = _doc.format == DocFormat.pdf;
    return PageButtonScope(
      enabled: !loading && !_backgrounded && session?.isReady == true,
      onPrevious: session == null
          ? null
          : () => _turnFromButton(session, forward: false),
      onNext: session == null
          ? null
          : () => _turnFromButton(session, forward: true),
      child: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            if (session?.isReady == true) _buildReader(session!),
            if (loading)
              ColoredBox(
                key: const Key('reader-opening-preview'),
                color: Colors.white,
                child: _openingPreview != null
                    ? ColorFiltered(
                        colorFilter: ColorFilter.matrix(
                          settings.colorEnabled
                              ? const [
                                  1,
                                  0,
                                  0,
                                  0,
                                  0,
                                  0,
                                  1,
                                  0,
                                  0,
                                  0,
                                  0,
                                  0,
                                  1,
                                  0,
                                  0,
                                  0,
                                  0,
                                  0,
                                  1,
                                  0,
                                ]
                              : const [
                                  .299,
                                  .587,
                                  .114,
                                  0,
                                  0,
                                  .299,
                                  .587,
                                  .114,
                                  0,
                                  0,
                                  .299,
                                  .587,
                                  .114,
                                  0,
                                  0,
                                  0,
                                  0,
                                  0,
                                  1,
                                  0,
                                ],
                        ),
                        child: RawImage(
                          image: _openingPreview,
                          fit: BoxFit.fill,
                          filterQuality: FilterQuality.none,
                        ),
                      )
                    : Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(_doc.title, textAlign: TextAlign.center),
                        ),
                      ),
              ),
            if (_menuVisible || loading)
              ReaderMenuOverlay(
                title: _doc.title,
                currentPage:
                    session?.currentPage ??
                    (savedPosition is PdfReadingPosition
                        ? savedPosition.pageIndex
                        : 0),
                pageCount: session?.pageCount ?? 0,
                settings: settings,
                tabStrip: _tabStrip(),
                controlsEnabled: !loading,
                onCloseReader: () => Navigator.of(context).pop(),
                onDismiss: () {
                  if (!loading) setState(() => _menuVisible = false);
                },
                onOpenBookmarks: _openBookmarks,
                onJumpToPage: _showPageJump,
                onSelectFitMode: (fitMode) =>
                    _applySettings(settings.copyWith(fitMode: fitMode)),
                onToggleOrientation: () => _applySettings(
                  settings.copyWith(landscape: !settings.landscape),
                ),
                onOpenSettings: _openSettings,
                showPdfControls: isPdf,
                onOpenToc: session == null || session.toc.isEmpty
                    ? null
                    : _openToc,
                onOpenSearch: isPdf ? null : _openSearch,
                onJumpToPercent: _showPercentJump,
                percent: session?.percent ?? state?.percent,
              ),
            if (loading)
              const IgnorePointer(
                child: Align(
                  alignment: Alignment(0, 0.35),
                  child: DecoratedBox(
                    key: Key('reader-loading-indicator'),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.fromBorderSide(
                        BorderSide(color: Colors.black),
                      ),
                    ),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.hourglass_empty, size: 18),
                          SizedBox(width: 8),
                          Text('Loading…'),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildReader(ReaderSession session) {
    final isPdf = session is PdfReaderSession;
    final generation = _loadGeneration;
    return TapZoneLayer(
      // A cached resume can finish before the next frame. Give its presenter
      // a new readiness callback even if the same session State would survive.
      key: ValueKey((session, _contentGeneration)),
      zoomMode: isPdf && session.settings.fitMode == PdfFitMode.zoom,
      onPrevious: () => _navigate(session.prevPage, orderedPdfTurn: isPdf),
      onMenu: () => setState(() => _menuVisible = !_menuVisible),
      onNext: () => _navigate(session.nextPage, orderedPdfTurn: isPdf),
      child: isPdf
          ? PdfPageView(
              session: session,
              onRetry: _retry,
              onContentReady: () => _contentReady(generation),
            )
          : session is TextReaderSession
          ? TextPageView(
              session: session,
              onContentReady: () => _contentReady(generation),
            )
          : const SizedBox.shrink(),
    );
  }
}

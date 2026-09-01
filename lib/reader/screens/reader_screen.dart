import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../constants.dart';
import '../controllers/pdf_reader_session.dart';
import '../controllers/reader_session.dart';
import '../controllers/reader_session_registry.dart';
import '../controllers/text_reader_session.dart';
import '../models/bookmark.dart';
import '../models/doc_ref.dart';
import '../models/reader_settings.dart';
import '../models/toc_entry.dart';
import '../services/book_store_service.dart';
import '../services/reader_error_service.dart';
import '../services/pdf_render_scheduler.dart';
import '../services/text_search_service.dart';
import '../widgets/pdf_page_view.dart';
import '../widgets/reader_menu_overlay.dart';
import '../widgets/reader_error_view.dart';
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

  ReaderScreen({super.key, required this.doc, ReaderSessionRegistry? registry})
    : registry = registry ?? ReaderSessionRegistry.instance;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen>
    with WidgetsBindingObserver {
  ReaderSession? _session;
  String? _loadError;
  bool _menuVisible = false;
  bool _navigating = false;
  bool _loadingSession = false;
  bool _memoryPaused = false;
  bool _shownStateWarning = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadSession());
  }

  Future<void> _loadSession() async {
    if (_loadingSession) return;
    setState(() {
      _loadingSession = true;
      _loadError = null;
    });
    try {
      await BookStoreService.instance.init();
      if (!mounted) return;
      final warning = BookStoreService.instance.recoveryWarning;
      if (warning != null && !_shownStateWarning) {
        _shownStateWarning = true;
        await showDialog<void>(
          context: context,
          animationStyle: AnimationStyle.noAnimation,
          builder: (context) => AlertDialog(
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
        if (!mounted) return;
      }
      final session = await widget.registry.obtain(widget.doc);
      if (!mounted) return;
      setState(() {
        _session = session;
        _loadError = null;
      });
      await _applyOrientation(session.settings.landscape);
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadError = readerErrorMessage(error, widget.doc.format));
    } finally {
      if (mounted) setState(() => _loadingSession = false);
    }
  }

  Future<void> _resumeSession() async {
    if (!_memoryPaused) await _loadSession();
  }

  Future<void> _retry() async {
    if (_loadingSession) return;
    _memoryPaused = false;
    _menuVisible = false;
    _session?.suspend();
    await _loadSession();
  }

  @override
  void didHaveMemoryPressure() {
    if (!mounted) return;
    setState(() {
      _memoryPaused = true;
      _menuVisible = false;
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
        unawaited(_resumeSession());
      case AppLifecycleState.inactive:
        unawaited(BookStoreService.instance.flush());
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        widget.registry.suspendAll();
        unawaited(BookStoreService.instance.flush());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final session = _session;
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
    try {
      await operation();
      if (mounted) setState(() => _loadError = null);
    } on PdfRenderCancelledException {
      // Normal supersession from navigation, settings, or suspension.
    } catch (error) {
      if (mounted) {
        setState(
          () => _loadError = readerErrorMessage(error, widget.doc.format),
        );
      }
    } finally {
      if (lockNavigation) _navigating = false;
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
    await _navigate(() async {
      await session.applySettings(settings);
      await _applyOrientation(settings.landscape);
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
      builder: (context) => AlertDialog(
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
      builder: (context) => AlertDialog(
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
    if (_memoryPaused) {
      return Scaffold(
        body: ReaderErrorView(
          message: 'Reading was paused to free memory. Your position has been saved.',
          onRetry: _retry,
          retryLabel: 'Continue reading',
        ),
      );
    }
    if (_loadingSession) {
      return Scaffold(
        body: ReaderErrorView(message: 'Opening ${widget.doc.title}…'),
      );
    }
    if (session == null) {
      return Scaffold(
        body: ReaderErrorView(
          message: _loadError ?? 'Could not open this document.',
          onRetry: _retry,
        ),
      );
    }

    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final error = session.error ?? _loadError;
        return Scaffold(
          body: error != null
              ? ReaderErrorView(message: error, onRetry: _retry)
              : _buildReader(session),
        );
      },
    );
  }

  Widget _buildReader(ReaderSession session) {
    if (!session.isReady) {
      return ReaderErrorView(
        message: 'Reader is paused',
        onRetry: _retry,
        retryLabel: 'Continue reading',
      );
    }
    if (session is! PdfReaderSession && session is! TextReaderSession) {
      return const ReaderErrorView(
        message: 'This document format is not implemented yet.',
      );
    }

    final isPdf = session is PdfReaderSession;

    return Stack(
      fit: StackFit.expand,
      children: [
        TapZoneLayer(
          zoomMode: isPdf && session.settings.fitMode == PdfFitMode.zoom,
          onPrevious: () => _navigate(session.prevPage, orderedPdfTurn: isPdf),
          onMenu: () => setState(() => _menuVisible = !_menuVisible),
          onNext: () => _navigate(session.nextPage, orderedPdfTurn: isPdf),
          child: isPdf
              ? PdfPageView(session: session, onRetry: _retry)
              : TextPageView(session: session as TextReaderSession),
        ),
        if (_menuVisible)
          ReaderMenuOverlay(
            title: session.doc.title,
            currentPage: session.currentPage,
            pageCount: session.pageCount,
            settings: session.settings,
            onCloseReader: () => Navigator.of(context).pop(),
            onDismiss: () => setState(() => _menuVisible = false),
            onOpenBookmarks: _openBookmarks,
            onJumpToPage: _showPageJump,
            onSelectFitMode: (fitMode) =>
                _applySettings(session.settings.copyWith(fitMode: fitMode)),
            onToggleOrientation: () => _applySettings(
              session.settings.copyWith(landscape: !session.settings.landscape),
            ),
            onOpenSettings: _openSettings,
            showPdfControls: isPdf,
            onOpenToc: session.toc.isEmpty ? null : _openToc,
            onOpenSearch: isPdf ? null : _openSearch,
            onJumpToPercent: _showPercentJump,
            percent: session.percent,
          ),
      ],
    );
  }
}

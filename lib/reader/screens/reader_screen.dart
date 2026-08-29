import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../constants.dart';
import '../controllers/pdf_reader_session.dart';
import '../controllers/reader_session.dart';
import '../controllers/reader_session_registry.dart';
import '../models/doc_ref.dart';
import '../models/reader_settings.dart';
import '../services/book_store_service.dart';
import '../widgets/pdf_page_view.dart';
import '../widgets/reader_menu_overlay.dart';
import '../widgets/tap_zone_layer.dart';
import 'reader_settings_screen.dart';

/// Full-bleed, format-agnostic reader shell.
///
/// Only [PdfReaderSession] has a page presenter in Phase 1. EPUB/TXT/Markdown
/// continue to open externally until [TextReaderSession] lands in Phase 2.
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadSession());
  }

  Future<void> _loadSession() async {
    if (_loadingSession) return;
    _loadingSession = true;
    try {
      await BookStoreService.instance.init();
      final session = await widget.registry.obtain(widget.doc);
      if (!mounted) return;
      setState(() {
        _session = session;
        _loadError = session.error;
      });
      await _applyOrientation(session.settings.landscape);
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadError = 'Could not open ${widget.doc.title}: $error');
    } finally {
      _loadingSession = false;
    }
  }

  Future<void> _resumeSession() async {
    if (_loadingSession) return;
    _loadingSession = true;
    try {
      final session = await widget.registry.obtain(widget.doc);
      if (!mounted) return;
      setState(() {
        _session = session;
        _loadError = session.error;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _loadError = 'Could not resume reader: $error');
      }
    } finally {
      _loadingSession = false;
    }
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
    unawaited(BookStoreService.instance.flush());
    unawaited(SystemChrome.setPreferredOrientations(const []));
    super.dispose();
  }

  Future<void> _navigate(Future<void> Function() operation) async {
    if (_navigating) return;
    _navigating = true;
    try {
      await operation();
    } finally {
      _navigating = false;
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
    await session.applySettings(settings);
    await _applyOrientation(settings.landscape);
  }

  Future<void> _cycleFitMode() async {
    final session = _session;
    if (session == null) return;
    final next = switch (session.settings.fitMode) {
      PdfFitMode.fitHeight => PdfFitMode.fitWidth,
      PdfFitMode.fitWidth => PdfFitMode.continuousScroll,
      PdfFitMode.continuousScroll => PdfFitMode.freeZoom,
      PdfFitMode.freeZoom => PdfFitMode.fitHeight,
    };
    await _applySettings(session.settings.copyWith(fitMode: next));
  }

  Future<void> _openSettings() async {
    final session = _session;
    if (session == null) return;
    final settings = await Navigator.of(context).push<ReaderSettings>(
      noTransitionRoute(
        ReaderSettingsScreen(initialSettings: session.settings),
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

  @override
  Widget build(BuildContext context) {
    final session = _session;
    if (session == null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              _loadError ?? 'Opening ${widget.doc.title}…',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final error = session.error ?? _loadError;
        return Scaffold(
          body: error != null
              ? _ErrorView(message: error)
              : _buildReader(session),
        );
      },
    );
  }

  Widget _buildReader(ReaderSession session) {
    if (!session.isReady) {
      return const Center(child: Text('Reader is paused'));
    }
    if (session is! PdfReaderSession) {
      return const _ErrorView(
        message: 'This document format is not implemented yet.',
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        TapZoneLayer(
          zoomMode: session.settings.fitMode == PdfFitMode.freeZoom,
          onPrevious: () => _navigate(session.prevPage),
          onMenu: () => setState(() => _menuVisible = !_menuVisible),
          onNext: () => _navigate(session.nextPage),
          child: PdfPageView(session: session),
        ),
        if (_menuVisible)
          ReaderMenuOverlay(
            title: session.doc.title,
            currentPage: session.currentPage,
            pageCount: session.pageCount,
            settings: session.settings,
            onCloseReader: () => Navigator.of(context).pop(),
            onDismiss: () => setState(() => _menuVisible = false),
            onPrevious: () => _navigate(session.prevPage),
            onNext: () => _navigate(session.nextPage),
            onJumpToPage: _showPageJump,
            onCycleFitMode: _cycleFitMode,
            onToggleCrop: () => _applySettings(
              session.settings.copyWith(autoCrop: !session.settings.autoCrop),
            ),
            onToggleOrientation: () => _applySettings(
              session.settings.copyWith(landscape: !session.settings.landscape),
            ),
            onOpenSettings: _openSettings,
          ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;

  const _ErrorView({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 20),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Back to files'),
            ),
          ],
        ),
      ),
    );
  }
}

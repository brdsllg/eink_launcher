import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../constants.dart';
import '../controllers/pdf_reader_session.dart';
import '../controllers/reader_session.dart';
import '../controllers/reader_session_registry.dart';
import '../controllers/text_reader_session.dart';
import '../models/doc_ref.dart';
import '../models/reader_settings.dart';
import '../services/book_store_service.dart';
import '../widgets/pdf_page_view.dart';
import '../widgets/reader_menu_overlay.dart';
import '../widgets/tap_zone_layer.dart';
import '../widgets/text_page_view.dart';
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
    if (session is! PdfReaderSession && session is! TextReaderSession) {
      return const _ErrorView(
        message: 'This document format is not implemented yet.',
      );
    }

    final isPdf = session is PdfReaderSession;

    return Stack(
      fit: StackFit.expand,
      children: [
        TapZoneLayer(
          zoomMode: isPdf && session.settings.fitMode == PdfFitMode.zoom,
          onPrevious: () => _navigate(session.prevPage),
          onMenu: () => setState(() => _menuVisible = !_menuVisible),
          onNext: () => _navigate(session.nextPage),
          child: isPdf
              ? PdfPageView(session: session)
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
            onJumpToPage: _showPageJump,
            onSelectFitMode: (fitMode) =>
                _applySettings(session.settings.copyWith(fitMode: fitMode)),
            onToggleOrientation: () => _applySettings(
              session.settings.copyWith(landscape: !session.settings.landscape),
            ),
            onOpenSettings: _openSettings,
            showPdfControls: isPdf,
            onOpenToc: session.toc.isEmpty ? null : _openToc,
            onJumpToPercent: _showPercentJump,
            percent: session.percent,
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

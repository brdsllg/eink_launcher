import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;

import '../controllers/pdf_reader_session.dart';
import '../models/pdf_continuous_layout.dart';
import '../models/reader_settings.dart';
import 'no_momentum_scroll_physics.dart';

/// Thin PDF presenter. Rendering geometry, crop detection, and bitmap caching
/// remain owned by [PdfReaderSession].
class PdfPageView extends StatefulWidget {
  final PdfReaderSession session;

  const PdfPageView({super.key, required this.session});

  @override
  State<PdfPageView> createState() => _PdfPageViewState();
}

class _PdfPageViewState extends State<PdfPageView> {
  Future<ui.Image>? _renderFuture;
  Object? _renderSignature;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.white,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final viewport = Size(constraints.maxWidth, constraints.maxHeight);
          if (viewport.isEmpty) return const SizedBox.shrink();

          final settings = widget.session.settings;
          if (settings.fitMode == PdfFitMode.continuousScroll) {
            return _ContinuousPdfView(
              session: widget.session,
              viewport: viewport,
            );
          }

          final position = widget.session.position;
          final signature = Object.hash(
            viewport.width,
            viewport.height,
            position,
            settings.fitMode,
            settings.autoCrop,
            settings.splitOverlap,
          );
          if (_renderSignature != signature) {
            _renderSignature = signature;
            _renderFuture = widget.session.renderCurrentView(viewport);
          }

          return FutureBuilder<ui.Image>(
            future: _renderFuture,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return _Message(
                  text: 'Could not render this page.\n${snapshot.error}',
                );
              }
              final image = snapshot.data;
              if (image == null) {
                // A plain page is intentional: animated progress indicators
                // generate needless refreshes and ghosting on e-ink.
                return const ColoredBox(color: Colors.white);
              }
              final page = RawImage(
                image: image,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.none,
              );
              if (settings.fitMode != PdfFitMode.freeZoom) {
                return Center(child: page);
              }
              return InteractiveViewer(
                key: ValueKey(_renderSignature),
                minScale: 1,
                maxScale: 5,
                panEnabled: true,
                scaleEnabled: true,
                boundaryMargin: const EdgeInsets.all(80),
                child: SizedBox.fromSize(size: viewport, child: page),
              );
            },
          );
        },
      ),
    );
  }
}

class _ContinuousPdfView extends StatefulWidget {
  final PdfReaderSession session;
  final Size viewport;

  const _ContinuousPdfView({required this.session, required this.viewport});

  @override
  State<_ContinuousPdfView> createState() => _ContinuousPdfViewState();
}

class _ContinuousPdfViewState extends State<_ContinuousPdfView> {
  late final ScrollController _controller;
  Future<PdfContinuousLayout>? _layoutFuture;
  PdfContinuousLayout? _layout;
  Object? _layoutSignature;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController()..addListener(_handleScroll);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  void _handleScroll() {
    final layout = _layout;
    if (layout == null || !_controller.hasClients) return;
    widget.session.updateContinuousScrollOffset(
      _controller.offset,
      layout,
      widget.viewport.height,
    );
  }

  void _synchronizeOffset(PdfContinuousLayout layout) {
    final desired = widget.session.continuousOffsetForPosition(
      layout,
      widget.viewport.height,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) return;
      final target = desired
          .clamp(
            _controller.position.minScrollExtent,
            _controller.position.maxScrollExtent,
          )
          .toDouble();
      if ((_controller.offset - target).abs() > 0.5) {
        _controller.jumpTo(target);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final signature = Object.hash(
      widget.viewport.width,
      widget.viewport.height,
      widget.session.settings.autoCrop,
    );
    if (_layoutSignature != signature) {
      _layoutSignature = signature;
      _layout = null;
      _layoutFuture = widget.session.continuousLayoutForViewport(
        widget.viewport,
      );
    }

    return FutureBuilder<PdfContinuousLayout>(
      future: _layoutFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _Message(
            text: 'Could not prepare continuous view.\n${snapshot.error}',
          );
        }
        final layout = snapshot.data;
        if (layout == null) return const ColoredBox(color: Colors.white);
        _layout = layout;
        _synchronizeOffset(layout);
        return ListView.builder(
          key: const Key('continuous-pdf-list'),
          controller: _controller,
          primary: false,
          padding: EdgeInsets.zero,
          physics: widget.session.settings.scrollMomentum
              ? const ClampingScrollPhysics()
              : const NoMomentumScrollPhysics(),
          itemCount: layout.pageCount,
          itemExtentBuilder: (index, dimensions) =>
              index < layout.pageCount ? layout.pageHeights[index] : null,
          scrollCacheExtent: const ScrollCacheExtent.viewport(2),
          addAutomaticKeepAlives: false,
          itemBuilder: (context, pageIndex) => _ContinuousPdfTile(
            key: ValueKey(pageIndex),
            session: widget.session,
            layout: layout,
            pageIndex: pageIndex,
          ),
        );
      },
    );
  }
}

class _ContinuousPdfTile extends StatefulWidget {
  final PdfReaderSession session;
  final PdfContinuousLayout layout;
  final int pageIndex;

  const _ContinuousPdfTile({
    super.key,
    required this.session,
    required this.layout,
    required this.pageIndex,
  });

  @override
  State<_ContinuousPdfTile> createState() => _ContinuousPdfTileState();
}

class _ContinuousPdfTileState extends State<_ContinuousPdfTile> {
  late Future<ui.Image> _imageFuture;

  @override
  void initState() {
    super.initState();
    _requestImage();
  }

  @override
  void didUpdateWidget(covariant _ContinuousPdfTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pageIndex != widget.pageIndex ||
        oldWidget.layout != widget.layout ||
        oldWidget.session != widget.session) {
      _requestImage();
    }
  }

  void _requestImage() {
    _imageFuture = widget.session.renderContinuousPage(
      widget.pageIndex,
      widget.layout,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ui.Image>(
      future: _imageFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const ColoredBox(
            color: Colors.white,
            child: Center(child: Text('Page could not be rendered')),
          );
        }
        final image = snapshot.data;
        if (image == null) return const ColoredBox(color: Colors.white);
        return RawImage(
          image: image,
          fit: BoxFit.fill,
          filterQuality: FilterQuality.none,
        );
      },
    );
  }
}

class _Message extends StatelessWidget {
  final String text;

  const _Message({required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(text, textAlign: TextAlign.center),
      ),
    );
  }
}

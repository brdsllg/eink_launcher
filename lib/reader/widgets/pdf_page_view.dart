import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../controllers/pdf_reader_session.dart';
import '../models/pdf_continuous_layout.dart';
import '../models/reader_settings.dart';

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
          final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);

          final settings = widget.session.settings;
          if (settings.fitMode == PdfFitMode.zoom) {
            return _ContinuousPdfView(
              session: widget.session,
              viewport: viewport,
              devicePixelRatio: devicePixelRatio,
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
            devicePixelRatio,
          );
          if (_renderSignature != signature) {
            _renderSignature = signature;
            _renderFuture = widget.session.renderCurrentView(
              viewport,
              devicePixelRatio: devicePixelRatio,
            );
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
              return Center(
                child: RawImage(
                  image: image,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.none,
                ),
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
  final double devicePixelRatio;

  const _ContinuousPdfView({
    required this.session,
    required this.viewport,
    required this.devicePixelRatio,
  });

  @override
  State<_ContinuousPdfView> createState() => _ContinuousPdfViewState();
}

class _ContinuousPdfViewState extends State<_ContinuousPdfView> {
  late final TransformationController _controller;
  Future<PdfContinuousLayout>? _layoutFuture;
  PdfContinuousLayout? _layout;
  Object? _layoutSignature;
  bool _interactionActive = false;
  bool _syncScheduled = false;

  @override
  void initState() {
    super.initState();
    _controller = TransformationController()..addListener(_handleTransform);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_handleTransform)
      ..dispose();
    super.dispose();
  }

  void _handleTransform() {
    final layout = _layout;
    if (layout == null) return;
    final scale = _controller.value.getMaxScaleOnAxis();
    final visibleHeight = widget.viewport.height / scale;
    final offset = _controller
        .toScene(Offset.zero)
        .dy
        .clamp(0.0, layout.maxScrollOffset(visibleHeight))
        .toDouble();
    widget.session.updateContinuousScrollOffset(offset, layout, visibleHeight);
  }

  void _synchronizeTransform(PdfContinuousLayout layout) {
    if (_interactionActive || _syncScheduled) return;
    _syncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncScheduled = false;
      if (!mounted || _interactionActive) return;
      final scale = _controller.value.getMaxScaleOnAxis();
      final visibleHeight = widget.viewport.height / scale;
      final desired = widget.session.continuousOffsetForPosition(
        layout,
        visibleHeight,
      );
      final current = _controller.toScene(Offset.zero).dy;
      if ((current - desired).abs() <= 0.5) return;
      final next = _controller.value.clone()
        ..setTranslationRaw(_controller.value.entry(0, 3), -desired * scale, 0);
      _controller.value = next;
    });
  }

  @override
  Widget build(BuildContext context) {
    final signature = Object.hash(
      widget.viewport.width,
      widget.viewport.height,
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
        _synchronizeTransform(layout);
        return InteractiveViewer.builder(
          key: const Key('continuous-pdf-viewer'),
          transformationController: _controller,
          alignment: Alignment.topLeft,
          minScale: 1,
          maxScale: 5,
          panEnabled: true,
          scaleEnabled: true,
          onInteractionStart: (_) => _interactionActive = true,
          onInteractionEnd: (_) {
            _interactionActive = false;
            _handleTransform();
          },
          builder: (context, visibleQuad) {
            final childHeight = math.max(
              layout.totalHeight,
              widget.viewport.height,
            );
            if (layout.pageCount == 0) {
              return SizedBox(width: layout.viewportWidth, height: childHeight);
            }

            final points = [
              visibleQuad.point0,
              visibleQuad.point1,
              visibleQuad.point2,
              visibleQuad.point3,
            ];
            final visibleTop = points
                .map((point) => point.y)
                .reduce(math.min)
                .clamp(0.0, layout.totalHeight)
                .toDouble();
            final visibleBottom = points
                .map((point) => point.y)
                .reduce(math.max)
                .clamp(0.0, layout.totalHeight)
                .toDouble();
            final lookAhead = math.max(
              visibleBottom - visibleTop,
              widget.viewport.height,
            );
            final firstPage = layout.pageAtOffset(
              math.max(0.0, visibleTop - lookAhead),
            );
            final lastPage = layout.pageAtOffset(
              math.min(layout.totalHeight, visibleBottom + lookAhead),
            );
            final scale = _controller.value.getMaxScaleOnAxis();
            final renderScale = scale.ceil().clamp(1, 5);

            return SizedBox(
              width: layout.viewportWidth,
              height: childHeight,
              child: Stack(
                children: [
                  for (
                    var pageIndex = firstPage;
                    pageIndex <= lastPage;
                    pageIndex += 1
                  )
                    Positioned(
                      key: ValueKey(pageIndex),
                      left: 0,
                      top: layout.pageTop(pageIndex),
                      width: layout.viewportWidth,
                      height: layout.pageHeights[pageIndex],
                      child: _ContinuousPdfTile(
                        session: widget.session,
                        layout: layout,
                        pageIndex: pageIndex,
                        devicePixelRatio: widget.devicePixelRatio * renderScale,
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _ContinuousPdfTile extends StatefulWidget {
  final PdfReaderSession session;
  final PdfContinuousLayout layout;
  final int pageIndex;
  final double devicePixelRatio;

  const _ContinuousPdfTile({
    required this.session,
    required this.layout,
    required this.pageIndex,
    required this.devicePixelRatio,
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
        oldWidget.session != widget.session ||
        oldWidget.devicePixelRatio != widget.devicePixelRatio) {
      _requestImage();
    }
  }

  void _requestImage() {
    _imageFuture = widget.session.renderContinuousPage(
      widget.pageIndex,
      widget.layout,
      devicePixelRatio: widget.devicePixelRatio,
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

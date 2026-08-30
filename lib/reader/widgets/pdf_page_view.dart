import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../constants.dart';
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

/// One continuous, always-zoomable document canvas.
///
/// Four rules keep this honest:
///
/// * The pinch scale is quantised and pushed back into PDFium, and pages are
///   cut into a 2-D grid so only the tiles actually on screen are rendered.
///   Full-width strips used to blow past the render dimension cap and come
///   back silently downscaled, which is what made zoom look blurry.
/// * Zooming out below fit-width needs a matching `boundaryMargin`.
///   InteractiveViewer floors the scale at `viewport.width /
///   boundaryRect.width` independently of `minScale`, so with a zero margin
///   the floor is exactly 1.0 no matter what `minScale` says.
/// * The floor itself is derived from real page geometry, so "fully zoomed
///   out" means about [kPdfZoomOutPageSpan] pages tall on any document.
/// * The transform is only snapped to the session's logical position when the
///   session reports a *programmatic* move. Snapping on every rebuild used to
///   cancel the user's own fling, which made the mode feel page-by-page.
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
  PdfContinuousLayout? _syncedLayout;
  int _syncedEpoch = -1;
  bool? _syncedAllowZoomOut;
  double _renderScale = 1.0;
  bool _interactionActive = false;

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
    if (scale <= 0) return;
    final visibleHeight = widget.viewport.height / scale;
    final offset = _controller
        .toScene(Offset.zero)
        .dy
        .clamp(0.0, layout.maxScrollOffset(visibleHeight))
        .toDouble();
    widget.session.updateContinuousScrollOffset(offset, layout, visibleHeight);
  }

  /// Re-rasterise at the settled zoom. Doing this mid-pinch would re-render
  /// on every gesture frame and stutter badly on e-ink, so the existing
  /// bitmaps are scaled during the gesture and sharpened once it ends.
  ///
  /// A pure pan leaves the quantised scale unchanged and therefore does *not*
  /// call setState — which matters, because a rebuild at the instant a fling
  /// starts would replace every tile and kill the perceived momentum.
  void _updateRenderScale() {
    final quantized = _quantizeRenderScale(
      _controller.value.getMaxScaleOnAxis(),
    );
    if (quantized == _renderScale) return;
    setState(() => _renderScale = quantized);
  }

  static double _quantizeRenderScale(double scale) {
    for (final rung in kPdfZoomRenderScales) {
      if (scale <= rung + 0.001) return rung;
    }
    return kPdfZoomRenderScales.last;
  }

  /// The pinch floor for this document: enough zoom-out to show about
  /// [kPdfZoomOutPageSpan] pages at once. A tall page needs a smaller scale
  /// than a squarer one, so this cannot be a constant.
  double _minScaleFor(PdfContinuousLayout layout) {
    if (!widget.session.settings.allowZoomOutBeyondFit) return kPdfMinZoomScale;
    if (layout.pageHeights.isEmpty) return kPdfMinZoomScaleBeyondFit;
    final index = widget.session.currentPage
        .clamp(0, layout.pageHeights.length - 1)
        .toInt();
    var pageHeight = layout.pageHeights[index];
    if (pageHeight <= 0) pageHeight = layout.totalHeight / layout.pageCount;
    if (pageHeight <= 0) return kPdfMinZoomScaleBeyondFit;
    final target =
        widget.viewport.height / (kPdfZoomOutPageSpan * pageHeight);
    return target
        .clamp(kPdfMinZoomScaleBeyondFit, kPdfMinZoomScale)
        .toDouble();
  }

  void _synchronizeTransform(PdfContinuousLayout layout) {
    final epoch = widget.session.navigationEpoch;
    if (_syncedLayout == layout && _syncedEpoch == epoch) return;
    // Claim the epoch immediately so repeated builds can't queue a second
    // callback that would fight the first one.
    _syncedLayout = layout;
    _syncedEpoch = epoch;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _interactionActive) return;
      final scale = _controller.value.getMaxScaleOnAxis();
      if (scale <= 0) return;
      final visibleHeight = widget.viewport.height / scale;
      final desired = widget.session.continuousOffsetForPosition(
        layout,
        visibleHeight,
      );
      final currentY = _controller.toScene(Offset.zero).dy;
      if ((currentY - desired).abs() <= 0.5) return;
      // Horizontal pan is deliberately preserved: a TOC or page jump should
      // not throw away where the reader was looking across the page.
      final panX = _controller.value.entry(0, 3);
      _controller.value = _controller.value.clone()
        ..setTranslationRaw(panX, -desired * scale, 0);
    });
  }

  /// Turning zoom-out off while the page is smaller than the screen would
  /// leave the view stuck outside the new limits, so snap back to fit-width.
  void _enforceZoomOutSetting(bool allowZoomOut) {
    if (_syncedAllowZoomOut == allowZoomOut) return;
    _syncedAllowZoomOut = allowZoomOut;
    if (allowZoomOut) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_controller.value.getMaxScaleOnAxis() >= 1.0) return;
      _controller.value = _controller.value.clone()..setIdentity();
      _updateRenderScale();
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

    final allowZoomOut = widget.session.settings.allowZoomOutBeyondFit;
    _enforceZoomOutSetting(allowZoomOut);

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

        final minScale = _minScaleFor(layout);

        // InteractiveViewer refuses to shrink its child below its boundary
        // rect, so the margin — not minScale alone — is what actually
        // permits zooming out past the page.
        final slack = minScale < 1.0 ? (1 / minScale - 1) / 2 : 0.0;
        final boundaryMargin = slack > 0
            ? EdgeInsets.symmetric(
                horizontal: layout.viewportWidth * slack,
                vertical: widget.viewport.height * slack,
              )
            : EdgeInsets.zero;

        return InteractiveViewer.builder(
          key: const Key('continuous-pdf-viewer'),
          transformationController: _controller,
          alignment: Alignment.topLeft,
          minScale: minScale,
          maxScale: kPdfMaxZoomScale,
          boundaryMargin: boundaryMargin,
          panEnabled: true,
          scaleEnabled: true,
          interactionEndFrictionCoefficient: kPdfFlingFrictionCoefficient,
          onInteractionStart: (_) => _interactionActive = true,
          onInteractionEnd: (_) {
            _interactionActive = false;
            _handleTransform();
            _updateRenderScale();
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
            final visibleLeft = points
                .map((point) => point.x)
                .reduce(math.min)
                .clamp(0.0, layout.viewportWidth)
                .toDouble();
            final visibleRight = points
                .map((point) => point.x)
                .reduce(math.max)
                .clamp(0.0, layout.viewportWidth)
                .toDouble();

            // Generous vertical look-ahead so a fling glides over rendered
            // content instead of running into blank tiles, which is what
            // made momentum look absent.
            final spanY = math.max(1.0, visibleBottom - visibleTop);
            final spanX = math.max(1.0, visibleRight - visibleLeft);
            final rangeTop = math.max(0.0, visibleTop - spanY * 0.75);
            final rangeBottom = math.min(
              layout.totalHeight,
              visibleBottom + spanY * 0.75,
            );
            final rangeLeft = math.max(0.0, visibleLeft - spanX * 0.35);
            final rangeRight = math.min(
              layout.viewportWidth,
              visibleRight + spanX * 0.35,
            );

            // Tile side in layout space that maps to at most
            // kPdfTileSidePixels device pixels. Because the on-screen pixel
            // count is constant, so is the cost, at every zoom level.
            final density = widget.devicePixelRatio * _renderScale;
            final maxTileSide = math.max(16.0, kPdfTileSidePixels / density);

            final columns = math.max(
              1,
              (layout.viewportWidth / maxTileSide).ceil(),
            );
            final columnWidth = layout.viewportWidth / columns;

            final tiles = <Widget>[];
            final firstPage = layout.pageAtOffset(rangeTop);
            final lastPage = layout.pageAtOffset(rangeBottom);
            for (
              var pageIndex = firstPage;
              pageIndex <= lastPage;
              pageIndex += 1
            ) {
              final pageTop = layout.pageTop(pageIndex);
              final pageHeight = layout.pageHeights[pageIndex];
              if (pageHeight <= 0) continue;
              final rows = math.max(1, (pageHeight / maxTileSide).ceil());
              final rowHeight = pageHeight / rows;

              for (var row = 0; row < rows; row += 1) {
                final tileTop = pageTop + row * rowHeight;
                if (tileTop + rowHeight <= rangeTop || tileTop >= rangeBottom) {
                  continue;
                }
                for (var column = 0; column < columns; column += 1) {
                  final tileLeft = column * columnWidth;
                  if (tileLeft + columnWidth <= rangeLeft ||
                      tileLeft >= rangeRight) {
                    continue;
                  }
                  tiles.add(
                    Positioned(
                      key: ValueKey('$pageIndex/$rows.$row/$columns.$column'),
                      left: tileLeft,
                      top: tileTop,
                      width: columnWidth,
                      height: rowHeight,
                      child: _ContinuousPdfTile(
                        session: widget.session,
                        layout: layout,
                        pageIndex: pageIndex,
                        region: Rect.fromLTRB(
                          column / columns,
                          row / rows,
                          (column + 1) / columns,
                          (row + 1) / rows,
                        ),
                        devicePixelRatio: widget.devicePixelRatio,
                        renderScale: _renderScale,
                      ),
                    ),
                  );
                }
              }
            }

            return SizedBox(
              width: layout.viewportWidth,
              height: childHeight,
              child: Stack(children: tiles),
            );
          },
        );
      },
    );
  }
}

/// One rendered tile of one page.
///
/// The bitmap is a [ui.Image.clone] of the cached image: the shared
/// bitmap cache may evict and dispose its copy at any time, and a disposed
/// image that is still on screen crashes the rasteriser. Cloning is
/// refcounted, so the pixels are shared and released once both copies go.
class _ContinuousPdfTile extends StatefulWidget {
  final PdfReaderSession session;
  final PdfContinuousLayout layout;
  final int pageIndex;
  final Rect region;
  final double devicePixelRatio;
  final double renderScale;

  const _ContinuousPdfTile({
    required this.session,
    required this.layout,
    required this.pageIndex,
    required this.region,
    required this.devicePixelRatio,
    required this.renderScale,
  });

  @override
  State<_ContinuousPdfTile> createState() => _ContinuousPdfTileState();
}

class _ContinuousPdfTileState extends State<_ContinuousPdfTile> {
  ui.Image? _image;
  bool _failed = false;
  int _requestToken = 0;

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
        oldWidget.region != widget.region ||
        oldWidget.devicePixelRatio != widget.devicePixelRatio ||
        oldWidget.renderScale != widget.renderScale) {
      _requestImage();
    }
  }

  @override
  void dispose() {
    _requestToken += 1;
    _image?.dispose();
    _image = null;
    super.dispose();
  }

  void _requestImage() {
    final token = ++_requestToken;
    widget.session
        .renderContinuousTile(
          widget.pageIndex,
          widget.layout,
          devicePixelRatio: widget.devicePixelRatio,
          renderScale: widget.renderScale,
          region: widget.region,
        )
        .then(
          (image) {
            if (!mounted || token != _requestToken) return;
            _adopt(image.clone(), failed: false);
          },
          onError: (Object _) {
            if (!mounted || token != _requestToken) return;
            _adopt(null, failed: true);
          },
        );
  }

  void _adopt(ui.Image? next, {required bool failed}) {
    final previous = _image;
    setState(() {
      _image = next;
      _failed = failed;
    });
    if (previous != null) {
      // Never dispose inside the frame that may still be painting it.
      WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
    }
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    if (image == null) {
      // Extents are known up front, so a plain white tile is never a layout
      // shift; and a spinner would animate, which e-ink cannot afford.
      return ColoredBox(
        color: Colors.white,
        child: _failed
            ? const Center(child: Text('Page could not be rendered'))
            : null,
      );
    }
    return RawImage(
      image: image,
      fit: BoxFit.fill,
      // Bilinear only matters mid-pinch, before the tile is re-rasterised at
      // the settled zoom; nearest-neighbour looks blocky in that window.
      filterQuality: FilterQuality.low,
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

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../constants.dart';
import '../controllers/pdf_reader_session.dart';
import '../models/pdf_continuous_layout.dart';
import '../models/reader_settings.dart';
import '../services/reader_error_service.dart';
import 'reader_error_view.dart';

/// Thin PDF presenter. Rendering geometry, crop detection, and bitmap caching
/// remain owned by [PdfReaderSession].
class PdfPageView extends StatefulWidget {
  final PdfReaderSession session;
  final VoidCallback? onRetry;

  const PdfPageView({super.key, required this.session, this.onRetry});

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
              onRetry: widget.onRetry,
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
                return ReaderErrorView(
                  message: readerErrorMessage(
                    snapshot.error!,
                    widget.session.doc.format,
                  ),
                  onRetry:
                      widget.onRetry ??
                      () => setState(() => _renderSignature = null),
                );
              }
              final image = snapshot.data;
              if (image == null) {
                // A plain page is intentional: animated progress indicators
                // generate needless refreshes and ghosting on e-ink.
                return const ColoredBox(color: Colors.white);
              }
              return Center(child: _OwnedPdfImage(image: image));
            },
          );
        },
      ),
    );
  }
}

/// A fit-mode page also needs its own image handle: suspension or cache
/// eviction must not dispose the handle currently being painted by RawImage.
class _OwnedPdfImage extends StatefulWidget {
  final ui.Image image;

  const _OwnedPdfImage({required this.image});

  @override
  State<_OwnedPdfImage> createState() => _OwnedPdfImageState();
}

class _OwnedPdfImageState extends State<_OwnedPdfImage> {
  late ui.Image _image;

  @override
  void initState() {
    super.initState();
    _image = widget.image.clone();
  }

  @override
  void didUpdateWidget(covariant _OwnedPdfImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.image, widget.image)) return;
    final previous = _image;
    _image = widget.image.clone();
    WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
  }

  @override
  void dispose() {
    _image.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RawImage(
    image: _image,
    fit: BoxFit.contain,
    filterQuality: FilterQuality.none,
  );
}

/// One continuous, always-zoomable document canvas with real momentum.
///
/// This deliberately does **not** use `InteractiveViewer`. Two of its
/// behaviours were unfixable from outside:
///
/// * It calls `onInteractionEnd` *before* starting its fling, so reacting to
///   the gesture (new render scale, new dominant page) rebuilt and blanked
///   every tile exactly as the glide began — movement across white, which on a
///   ~30 fps e-ink panel is indistinguishable from no momentum at all.
/// * Its fling uses `FrictionSimulation`, which is not the curve Android users
///   expect and which decays within a handful of frames.
///
/// So the transform is owned here as a `scale` plus a scene-space `origin` (the
/// document coordinate sitting at the viewport's top-left), and releases are
/// animated with [ClampingScrollSimulation] — Flutter's port of the AOSP
/// `OverScroller` fling curve that every Android list scroll uses. Driving it
/// from a bare [Ticker] means no rebuild can interrupt it.
///
/// Owning the clamp also makes zooming out past the page exact: undersized
/// content is simply centred, with none of the "pan into blank space" side
/// effect that `boundaryMargin` slack caused.
class _ContinuousPdfView extends StatefulWidget {
  final PdfReaderSession session;
  final Size viewport;
  final double devicePixelRatio;
  final VoidCallback? onRetry;

  const _ContinuousPdfView({
    required this.session,
    required this.viewport,
    required this.devicePixelRatio,
    this.onRetry,
  });

  @override
  State<_ContinuousPdfView> createState() => _ContinuousPdfViewState();
}

class _ContinuousPdfViewState extends State<_ContinuousPdfView>
    with SingleTickerProviderStateMixin {
  Future<PdfContinuousLayout>? _layoutFuture;
  PdfContinuousLayout? _layout;
  Object? _layoutSignature;
  PdfContinuousLayout? _syncedLayout;
  int _syncedEpoch = -1;
  bool? _syncedAllowZoomOut;

  /// Current view transform: `screen = (scene - origin) * scale`.
  double _scale = 1.0;
  double _originX = 0.0;
  double _originY = 0.0;

  /// Zoom rung the tiles are currently rasterised at. Changes are deferred
  /// until a gesture *and* its fling are over, so a glide never blanks tiles.
  double _renderScale = 1.0;
  double? _oldRenderScale;
  Timer? _oldScaleTimer;

  late final Ticker _flingTicker;
  Simulation? _flingX;
  Simulation? _flingY;
  double _lastFlingX = 0.0;
  double _lastFlingY = 0.0;

  bool _interacting = false;
  bool _renderFailed = false;
  double _gestureStartScale = 1.0;
  Offset _gestureStartScene = Offset.zero;

  @override
  void initState() {
    super.initState();
    _flingTicker = createTicker(_onFlingTick);
  }

  @override
  void dispose() {
    _flingTicker.dispose();
    _oldScaleTimer?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // Transform limits
  // ---------------------------------------------------------------------

  /// The pinch floor for this document: enough zoom-out to show about
  /// [kPdfZoomOutPageSpan] pages at once. A tall page needs a smaller scale
  /// than a squarer one, so this cannot be a constant.
  double _minScaleFor(PdfContinuousLayout layout) {
    if (!widget.session.settings.allowZoomOutBeyondFit) return kPdfMinZoomScale;
    if (layout.pageCount == 0) return kPdfMinZoomScale;
    final index = widget.session.currentPage
        .clamp(0, layout.pageHeights.length - 1)
        .toInt();
    var pageHeight = layout.pageHeights[index];
    if (pageHeight <= 0) pageHeight = layout.totalHeight / layout.pageCount;
    if (pageHeight <= 0) return kPdfMinZoomScaleBeyondFit;
    final target = widget.viewport.height / (kPdfZoomOutPageSpan * pageHeight);
    return target.clamp(kPdfMinZoomScaleBeyondFit, kPdfMinZoomScale).toDouble();
  }

  /// Clamps a candidate origin so the document can never be dragged off
  /// screen, centring it on whichever axis it is smaller than the viewport.
  ({double x, double y}) _clampOrigin(
    double x,
    double y,
    PdfContinuousLayout layout,
  ) {
    final visibleWidth = widget.viewport.width / _scale;
    final visibleHeight = widget.viewport.height / _scale;
    final contentWidth = layout.viewportWidth;
    final contentHeight = math.max(layout.totalHeight, 0.0);

    final clampedX = contentWidth <= visibleWidth
        ? (contentWidth - visibleWidth) / 2
        : x.clamp(0.0, contentWidth - visibleWidth).toDouble();
    final clampedY = contentHeight <= visibleHeight
        ? (contentHeight - visibleHeight) / 2
        : y.clamp(0.0, contentHeight - visibleHeight).toDouble();
    return (x: clampedX, y: clampedY);
  }

  /// Applies a new origin and reports the resulting scroll offset to the
  /// session. Returns true when the origin actually moved.
  bool _setOrigin(double x, double y, PdfContinuousLayout layout) {
    final clamped = _clampOrigin(x, y, layout);
    final moved =
        (clamped.x - _originX).abs() > 0.01 ||
        (clamped.y - _originY).abs() > 0.01;
    if (mounted) {
      setState(() {
        _originX = clamped.x;
        _originY = clamped.y;
      });
    } else {
      _originX = clamped.x;
      _originY = clamped.y;
    }
    widget.session.updateContinuousScrollOffset(
      math.max(0.0, clamped.y),
      layout,
      widget.viewport.height / _scale,
    );
    return moved;
  }

  // ---------------------------------------------------------------------
  // Gestures
  // ---------------------------------------------------------------------

  void _onScaleStart(ScaleStartDetails details) {
    _stopFling();
    final layout = _layout;
    if (layout == null) return;
    _interacting = true;
    _gestureStartScale = _scale;
    // The document point currently under the user's fingers. Keeping this
    // point pinned is what makes a pinch feel anchored rather than sliding.
    _gestureStartScene =
        Offset(_originX, _originY) + details.localFocalPoint / _scale;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final layout = _layout;
    if (layout == null) return;
    final minScale = _minScaleFor(layout);
    _scale = (_gestureStartScale * details.scale)
        .clamp(minScale, kPdfMaxZoomScale)
        .toDouble();
    final target = _gestureStartScene - details.localFocalPoint / _scale;
    _setOrigin(target.dx, target.dy, layout);
  }

  void _onScaleEnd(ScaleEndDetails details) {
    _interacting = false;
    final layout = _layout;
    if (layout == null) {
      _settleRenderScale();
      return;
    }
    final velocity = details.velocity.pixelsPerSecond;
    if (velocity.distance < kPdfMinFlingVelocity) {
      _settleRenderScale();
      return;
    }
    // Screen velocity → scene velocity. Dragging the page up (negative dy)
    // must increase the scroll offset, hence the sign flip.
    _startFling(-velocity.dx / _scale, -velocity.dy / _scale, layout);
  }

  // ---------------------------------------------------------------------
  // Momentum
  // ---------------------------------------------------------------------

  void _startFling(double sceneVx, double sceneVy, PdfContinuousLayout layout) {
    _flingTicker.stop();
    _flingX = sceneVx.abs() < 1
        ? null
        : ClampingScrollSimulation(
            position: _originX,
            velocity: sceneVx,
            friction: kPdfFlingFriction,
          );
    _flingY = sceneVy.abs() < 1
        ? null
        : ClampingScrollSimulation(
            position: _originY,
            velocity: sceneVy,
            friction: kPdfFlingFriction,
          );
    if (_flingX == null && _flingY == null) {
      _settleRenderScale();
      return;
    }
    _lastFlingX = _originX;
    _lastFlingY = _originY;
    _flingTicker.start();
  }

  void _onFlingTick(Duration elapsed) {
    final layout = _layout;
    if (layout == null) {
      _stopFling();
      _settleRenderScale();
      return;
    }
    final t = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    final simX = _flingX;
    final simY = _flingY;
    final targetX = simX?.x(t) ?? _originX;
    final targetY = simY?.x(t) ?? _originY;
    final moved = _setOrigin(targetX, targetY, layout);

    final finished = (simX?.isDone(t) ?? true) && (simY?.isDone(t) ?? true);
    // Pinned against an edge with nothing left to travel: stop rather than
    // burn e-ink refreshes on a simulation that can no longer move anything.
    final stalled =
        !moved &&
        (targetX - _lastFlingX).abs() + (targetY - _lastFlingY).abs() > 0.5;
    _lastFlingX = targetX;
    _lastFlingY = targetY;
    if (finished || stalled) {
      _stopFling();
      _settleRenderScale();
    }
  }

  void _stopFling() {
    if (_flingTicker.isTicking) _flingTicker.stop(canceled: true);
    _flingX = null;
    _flingY = null;
  }

  // ---------------------------------------------------------------------
  // Render scale
  // ---------------------------------------------------------------------

  /// Re-rasterise at the settled zoom, once the gesture *and* any fling are
  /// finished. Re-rendering mid-gesture would thrash PDFium; re-rendering
  /// mid-fling would swap every tile for a blank one and destroy the illusion
  /// of momentum, which is precisely what used to happen.
  void _settleRenderScale() {
    final quantized = _quantizeRenderScale(_scale);
    if (quantized == _renderScale || !mounted) return;

    final previousScale = _renderScale;
    setState(() {
      _oldRenderScale = previousScale;
      _renderScale = quantized;
    });

    _oldScaleTimer?.cancel();
    _oldScaleTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted && _oldRenderScale == previousScale) {
        setState(() {
          _oldRenderScale = null;
        });
      }
    });
  }

  static double _quantizeRenderScale(double scale) {
    for (final rung in kPdfZoomRenderScales) {
      if (scale <= rung + 0.001) return rung;
    }
    return kPdfZoomRenderScales.last;
  }

  // ---------------------------------------------------------------------
  // Session synchronisation
  // ---------------------------------------------------------------------

  void _synchronizeTransform(PdfContinuousLayout layout) {
    final epoch = widget.session.navigationEpoch;
    if (_syncedLayout == layout && _syncedEpoch == epoch) return;
    // Claim the epoch immediately so repeated builds can't queue a second
    // callback that would fight the first one.
    _syncedLayout = layout;
    _syncedEpoch = epoch;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _interacting || _flingTicker.isTicking) return;
      final desired = widget.session.continuousOffsetForPosition(
        layout,
        widget.viewport.height / _scale,
      );
      if ((desired - _originY).abs() <= 0.5) return;
      // Horizontal pan is deliberately preserved: a TOC or page jump should
      // not throw away where the reader was looking across the page.
      _setOrigin(_originX, desired, layout);
    });
  }

  /// Turning zoom-out off while the page is smaller than the screen would
  /// leave the view stuck outside the new limits, so snap back to fit-width.
  void _enforceZoomOutSetting(bool allowZoomOut) {
    if (_syncedAllowZoomOut == allowZoomOut) return;
    _syncedAllowZoomOut = allowZoomOut;
    if (allowZoomOut) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final layout = _layout;
      if (!mounted || layout == null || _scale >= kPdfMinZoomScale) return;
      _stopFling();
      _scale = kPdfMinZoomScale;
      _setOrigin(_originX, _originY, layout);
      _settleRenderScale();
    });
  }

  // ---------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_renderFailed) {
      return ReaderErrorView(
        message:
            'Could not render this PDF page. Try again or choose another file.',
        onRetry: widget.onRetry ?? () => setState(() => _renderFailed = false),
      );
    }
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

    _enforceZoomOutSetting(widget.session.settings.allowZoomOutBeyondFit);

    return FutureBuilder<PdfContinuousLayout>(
      future: _layoutFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return ReaderErrorView(
            message: readerErrorMessage(
              snapshot.error!,
              widget.session.doc.format,
            ),
            onRetry:
                widget.onRetry ?? () => setState(() => _layoutSignature = null),
          );
        }
        final layout = snapshot.data;
        if (layout == null) return const ColoredBox(color: Colors.white);
        _layout = layout;
        _synchronizeTransform(layout);

        return GestureDetector(
          key: const Key('continuous-pdf-surface'),
          behavior: HitTestBehavior.opaque,
          // ScaleGestureRecognizer covers both one-finger pans and two-finger
          // pinches, and loses the arena to a stationary tap, so the tap zones
          // wrapping this widget keep working.
          onScaleStart: _onScaleStart,
          onScaleUpdate: _onScaleUpdate,
          onScaleEnd: _onScaleEnd,
          child: ClipRect(
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                if (_oldRenderScale != null)
                  ..._buildTiles(layout, _oldRenderScale!),
                ..._buildTiles(layout, _renderScale),
              ],
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildTiles(
    PdfContinuousLayout layout,
    double targetRenderScale,
  ) {
    if (layout.pageCount == 0 || layout.totalHeight <= 0) {
      return const [SizedBox.expand()];
    }

    final visibleWidth = widget.viewport.width / _scale;
    final visibleHeight = widget.viewport.height / _scale;
    final visibleLeft = _originX;
    final visibleTop = _originY;

    // Generous vertical look-ahead so a fling glides over rendered content
    // instead of running into blank tiles.
    final rangeTop = math.max(0.0, visibleTop - visibleHeight * 0.75);
    final rangeBottom = math.min(
      layout.totalHeight,
      visibleTop + visibleHeight * 1.75,
    );
    final rangeLeft = math.max(0.0, visibleLeft - visibleWidth * 0.35);
    final rangeRight = math.min(
      layout.viewportWidth,
      visibleLeft + visibleWidth * 1.35,
    );
    if (rangeBottom <= rangeTop || rangeRight <= rangeLeft) {
      return const [SizedBox.expand()];
    }

    // Tile side in document space that maps to at most kPdfTileSidePixels
    // device pixels. Because the on-screen pixel count is constant, so is the
    // cost, at every zoom level — and no request ever hits the dimension cap
    // that used to silently downscale zoomed pages into blurriness.
    final density = widget.devicePixelRatio * targetRenderScale;
    final maxTileSide = math.max(16.0, kPdfTileSidePixels / density);

    final columns = math.max(1, (layout.viewportWidth / maxTileSide).ceil());
    final columnWidth = layout.viewportWidth / columns;

    final tiles = <Widget>[const SizedBox.expand()];
    final firstPage = layout.pageAtOffset(rangeTop);
    final lastPage = layout.pageAtOffset(
      math.min(rangeBottom, layout.totalHeight - 0.01),
    );

    for (var pageIndex = firstPage; pageIndex <= lastPage; pageIndex += 1) {
      final pageTop = layout.pageTop(pageIndex);
      final pageHeight = layout.pageHeights[pageIndex];
      if (pageHeight <= 0) continue;
      final rows = math.max(1, (pageHeight / maxTileSide).ceil());
      final rowHeight = pageHeight / rows;

      for (var row = 0; row < rows; row += 1) {
        final tileTop = pageTop + row * rowHeight;
        if (tileTop + rowHeight <= rangeTop || tileTop >= rangeBottom) continue;
        for (var column = 0; column < columns; column += 1) {
          final tileLeft = column * columnWidth;
          if (tileLeft + columnWidth <= rangeLeft || tileLeft >= rangeRight) {
            continue;
          }
          tiles.add(
            Positioned(
              key: ValueKey(
                '${targetRenderScale.toStringAsFixed(2)}/$pageIndex/$rows.$row/$columns.$column',
              ),
              left: (tileLeft - _originX) * _scale,
              top: (tileTop - _originY) * _scale,
              // Half a pixel of overdraw hides hairline seams between
              // adjacent tiles after fractional rounding.
              width: columnWidth * _scale + 0.5,
              height: rowHeight * _scale + 0.5,
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
                renderScale: targetRenderScale,
                onError: () {
                  if (mounted && !_renderFailed) {
                    setState(() => _renderFailed = true);
                  }
                },
              ),
            ),
          );
        }
      }
    }
    return tiles;
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
  final VoidCallback onError;

  const _ContinuousPdfTile({
    required this.session,
    required this.layout,
    required this.pageIndex,
    required this.region,
    required this.devicePixelRatio,
    required this.renderScale,
    required this.onError,
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
            widget.onError();
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
      if (_failed) {
        return const ColoredBox(
          color: Colors.white,
          child: Center(child: Text('Page could not be rendered')),
        );
      }
      return const SizedBox.expand();
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

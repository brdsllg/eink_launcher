import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../constants.dart';
import '../controllers/pdf_reader_session.dart';
import '../models/pdf_continuous_layout.dart';
import '../models/reader_settings.dart';
import '../services/pdf_render_scheduler.dart';
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
  ui.Image? _fitImage;
  Object? _fitError;
  int _fitRequestToken = 0;
  Object? _renderSignature;
  PdfRenderRequest? _fitRequest;
  Timer? _fitRetryTimer;

  @override
  void dispose() {
    _fitRequestToken++;
    _fitRequest?.cancel();
    _fitRetryTimer?.cancel();
    _fitImage?.dispose();
    super.dispose();
  }

  void _replaceFitImage(ui.Image? image) {
    final previous = _fitImage;
    _fitImage = image;
    if (previous != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
    }
  }

  void _requestFitImage(Size viewport, double devicePixelRatio) {
    final token = ++_fitRequestToken;
    _fitRequest?.cancel();
    _fitRetryTimer?.cancel();
    final request = _fitRequest = PdfRenderRequest();
    _fitError = null;
    widget.session
        .renderCurrentView(
          viewport,
          devicePixelRatio: devicePixelRatio,
          request: request,
        )
        .then(
          (image) {
            if (!mounted || token != _fitRequestToken) {
              image.dispose();
              return;
            }
            setState(() => _replaceFitImage(image));
          },
          onError: (Object error) {
            if (!mounted || token != _fitRequestToken) return;
            if (error is PdfRenderCancelledException) {
              if (!request.isCancelled) {
                _fitRetryTimer = Timer(const Duration(milliseconds: 100), () {
                  if (mounted && token == _fitRequestToken) {
                    setState(() => _renderSignature = null);
                  }
                });
              }
              return;
            }
            setState(() {
              _fitError = error;
              _replaceFitImage(null);
            });
          },
        );
  }

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
            if (_renderSignature != null) {
              _renderSignature = null;
              _fitRequestToken++;
              _fitRequest?.cancel();
              _replaceFitImage(null);
              _fitError = null;
            }
            return _ContinuousPdfView(
              session: widget.session,
              viewport: viewport,
              devicePixelRatio: devicePixelRatio,
              onRetry: widget.onRetry,
            );
          }

          final position = widget.session.position;
          final signature = Object.hash(
            widget.session,
            widget.session.navigationEpoch,
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
            _requestFitImage(viewport, devicePixelRatio);
          }

          if (_fitError != null) {
            return ReaderErrorView(
              message: readerErrorMessage(
                _fitError!,
                widget.session.doc.format,
              ),
              onRetry:
                  widget.onRetry ??
                  () => setState(() => _renderSignature = null),
            );
          }
          // A plain page while loading avoids animated e-ink refreshes.
          return Center(
            child: RawImage(
              image: _fitImage,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.none,
            ),
          );
        },
      ),
    );
  }
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
  int _observedNavigationEpoch = -1;
  bool? _syncedAllowZoomOut;

  /// Current view transform: `screen = (scene - origin) * scale`.
  double _scale = 1.0;
  double _originX = 0.0;
  double _originY = 0.0;

  /// Zoom rung the tiles are currently rasterised at. Changes are deferred
  /// until a gesture *and* its fling are over, so a glide never blanks tiles.
  double _renderScale = 1.0;
  Timer? _refinementTimer;
  Timer? _retryTimer;
  bool _waitingForIdle = false;
  bool _refiningScale = false;
  double _scrollDirection = 1.0;
  final Map<String, _PdfRaster> _tiles = {};
  final Map<int, _PdfRaster> _previews = {};
  List<_PdfTileSpec> _tileSpecs = const [];
  final List<_PdfFallbackTile> _fallbackTiles = [];

  // One bounded set of already displayed pixels, never a second active grid.
  // Previews cover any region omitted when this limit is reached.
  static const _maxFallbackBytes = 16 * 1024 * 1024;
  static const _refinementDelay = Duration(milliseconds: 200);

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
    _observedNavigationEpoch = widget.session.navigationEpoch;
    widget.session.addListener(_onSessionNavigation);
  }

  @override
  void dispose() {
    widget.session.removeListener(_onSessionNavigation);
    _flingTicker.dispose();
    _refinementTimer?.cancel();
    _retryTimer?.cancel();
    _releaseRasters();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _ContinuousPdfView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) {
      oldWidget.session.removeListener(_onSessionNavigation);
      widget.session.addListener(_onSessionNavigation);
      _observedNavigationEpoch = widget.session.navigationEpoch;
    }
    if (oldWidget.session != widget.session ||
        oldWidget.viewport != widget.viewport ||
        oldWidget.devicePixelRatio != widget.devicePixelRatio) {
      _refinementTimer?.cancel();
      _retryTimer?.cancel();
      _waitingForIdle = false;
      _releaseRasters();
      _layoutSignature = null;
      _refiningScale = false;
      _renderFailed = false;
    }
  }

  void _onSessionNavigation() {
    final epoch = widget.session.navigationEpoch;
    if (epoch == _observedNavigationEpoch) return;
    _observedNavigationEpoch = epoch;
    // Stop synchronously at notification: the next ticker callback otherwise
    // overwrites the requested logical position before the widget can build.
    _stopFling();
    _refinementTimer?.cancel();
    if (mounted) setState(() => _waitingForIdle = false);
  }

  void _releaseRasters() {
    for (final raster in [..._tiles.values, ..._previews.values]) {
      raster.release();
    }
    _tiles.clear();
    _previews.clear();
    _tileSpecs = const [];
    _releaseFallback();
  }

  void _releaseFallback() {
    for (final tile in _fallbackTiles) {
      _releaseAfterFrame(tile.image);
    }
    _fallbackTiles.clear();
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
    if ((clamped.y - _originY).abs() > 0.01) {
      _scrollDirection = clamped.y > _originY ? 1 : -1;
    }
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
    _refinementTimer?.cancel();
    _waitingForIdle = false;
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
    if (!mounted) return;
    _refinementTimer?.cancel();
    setState(() => _waitingForIdle = true);
    _refinementTimer = Timer(_refinementDelay, () {
      if (!mounted || _interacting || _flingTicker.isTicking) return;
      final quantized = _quantizeRenderScale(_scale);
      setState(() {
        _waitingForIdle = false;
        if (quantized != _renderScale) {
          _captureFallback();
          _renderScale = quantized;
          _refiningScale = true;
        }
      });
    });
  }

  Rect get _visibleRect => Rect.fromLTWH(
    _originX,
    _originY,
    widget.viewport.width / _scale,
    widget.viewport.height / _scale,
  );

  void _captureFallback() {
    // A second pinch must not replace a complete fallback with the few tiles
    // that happened to finish in the interrupted refinement.
    if (_refiningScale && _fallbackTiles.isNotEmpty) return;
    _releaseFallback();
    var retainedBytes = 0;
    final visiblePixelBytes =
        (widget.viewport.width *
                widget.devicePixelRatio *
                widget.viewport.height *
                widget.devicePixelRatio *
                4 *
                2)
            .ceil();
    final budget = math.min(
      _maxFallbackBytes,
      math.min(widget.session.bitmapCacheBudgetBytes, visiblePixelBytes),
    );
    for (final spec in _tileSpecs) {
      if (!spec.bounds.overlaps(_visibleRect)) continue;
      final image = _tiles[spec.key]?.image;
      if (image == null) continue;
      final bytes = image.width * image.height * 4;
      if (retainedBytes + bytes > budget) continue;
      _fallbackTiles.add(_PdfFallbackTile(spec.bounds, image.clone()));
      retainedBytes += bytes;
    }
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
      if (!mounted || _syncedEpoch != epoch) return;
      if (_interacting) {
        _syncedEpoch = -1;
        return;
      }
      // User scrolls do not advance the epoch. A new epoch is an explicit
      // navigation command and must interrupt, rather than be lost to, a fling.
      _stopFling();
      final desired = widget.session.continuousOffsetForPosition(
        layout,
        widget.viewport.height / _scale,
      );
      // Horizontal pan is deliberately preserved: a TOC or page jump should
      // not throw away where the reader was looking across the page.
      if ((desired - _originY).abs() > 0.5) {
        _setOrigin(_originX, desired, layout);
      }
      // Even a clamped jump cancels the old refinement timer. Restore it when
      // the logical target already matches the current viewport.
      _settleRenderScale();
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
        onRetry:
            widget.onRetry ??
            () => setState(() {
              _releaseRasters();
              _refiningScale = false;
              _renderFailed = false;
            }),
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
              children: _buildRasterLayers(layout),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildRasterLayers(PdfContinuousLayout layout) {
    if (layout.pageCount == 0 || layout.totalHeight <= 0) {
      return const [SizedBox.expand()];
    }
    final visible = _visibleRect;
    final moving = _interacting || _flingTicker.isTicking || _waitingForIdle;
    final previewRange = _lookAheadRect(layout, ahead: 1.0, behind: 0.25);
    final detailRange = moving
        ? visible
        : _lookAheadRect(layout, ahead: 0.35, behind: 0.10);

    // Coarse coverage gets first use of the renderer. Detail is only requested
    // at rest; during motion, keep usable pixels and spend work on previews of
    // the pages being approached instead of abandoned high-density tiles.
    _syncPreviews(layout, previewRange, visible);
    final specs = _describeTiles(
      layout,
      detailRange,
    ).where((spec) => !moving || _tiles.containsKey(spec.key)).toList();
    specs.sort((a, b) {
      final aVisible = a.bounds.overlaps(visible);
      final bVisible = b.bounds.overlaps(visible);
      if (aVisible != bVisible) return aVisible ? -1 : 1;
      return (a.bounds.center - visible.center).distanceSquared.compareTo(
        (b.bounds.center - visible.center).distanceSquared,
      );
    });
    _syncTiles(layout, specs, visible);
    _tileSpecs = specs;

    // Only the current viewport gates the handoff. Offscreen prefetch must not
    // delay sharp text, and a timer must never discard the last useful pixels.
    if (_refiningScale && !moving) {
      final visibleSpecs = _describeTiles(layout, visible);
      if (visibleSpecs.isNotEmpty &&
          visibleSpecs.every((spec) => _tiles[spec.key]?.image != null)) {
        _refiningScale = false;
        _releaseFallback();
      }
    }
    _fallbackTiles.removeWhere((tile) {
      if (tile.bounds.overlaps(visible)) return false;
      _releaseAfterFrame(tile.image);
      return true;
    });

    return [
      const SizedBox.expand(),
      for (final entry in _previews.entries)
        if (entry.value.image != null)
          _positionImage(
            Rect.fromLTWH(
              0,
              layout.pageTop(entry.key),
              layout.viewportWidth,
              layout.pageHeights[entry.key],
            ),
            entry.value.image!,
            ValueKey('pdf-preview-${entry.key}'),
          ),
      for (var index = 0; index < _fallbackTiles.length; index++)
        _positionImage(
          _fallbackTiles[index].bounds,
          _fallbackTiles[index].image,
          ValueKey('pdf-fallback-$index'),
        ),
      if (!_refiningScale)
        for (final spec in specs)
          if (_tiles[spec.key]?.image != null)
            _positionImage(
              spec.bounds,
              _tiles[spec.key]!.image!,
              ValueKey('pdf-detail-${spec.key}'),
            ),
    ];
  }

  Rect _lookAheadRect(
    PdfContinuousLayout layout, {
    required double ahead,
    required double behind,
  }) {
    final visible = _visibleRect;
    final before = _scrollDirection < 0 ? ahead : behind;
    final after = _scrollDirection < 0 ? behind : ahead;
    return Rect.fromLTRB(
      math.max(0, visible.left - visible.width * 0.10),
      math.max(0, visible.top - visible.height * before),
      math.min(layout.viewportWidth, visible.right + visible.width * 0.10),
      math.min(layout.totalHeight, visible.bottom + visible.height * after),
    );
  }

  List<_PdfTileSpec> _describeTiles(PdfContinuousLayout layout, Rect range) {
    final clipped = range.intersect(
      Rect.fromLTWH(0, 0, layout.viewportWidth, layout.totalHeight),
    );
    if (clipped.isEmpty) return const [];
    final density = widget.devicePixelRatio * _renderScale;
    final maxTileSide = math.max(16.0, kPdfTileSidePixels / density);
    final columns = math.max(1, (layout.viewportWidth / maxTileSide).ceil());
    final columnWidth = layout.viewportWidth / columns;
    final firstPage = layout.pageAtOffset(clipped.top);
    final lastPage = layout.pageAtOffset(
      math.min(clipped.bottom, layout.totalHeight - 0.01),
    );
    final specs = <_PdfTileSpec>[];
    for (final pageIndex in _nearestIndices(
      firstPage,
      lastPage,
      layout.pageAtOffset(_visibleRect.center.dy),
    )) {
      final pageTop = layout.pageTop(pageIndex);
      final pageHeight = layout.pageHeights[pageIndex];
      if (pageHeight <= 0) continue;
      final rows = math.max(1, (pageHeight / maxTileSide).ceil());
      final rowHeight = pageHeight / rows;
      final firstRow = ((clipped.top - pageTop) / rowHeight)
          .floor()
          .clamp(0, rows - 1)
          .toInt();
      final lastRow =
          ((clipped.bottom - pageTop) / rowHeight)
              .ceil()
              .clamp(1, rows)
              .toInt() -
          1;
      final firstColumn = (clipped.left / columnWidth)
          .floor()
          .clamp(0, columns - 1)
          .toInt();
      final lastColumn =
          (clipped.right / columnWidth).ceil().clamp(1, columns).toInt() - 1;
      for (final row in _nearestIndices(
        firstRow,
        lastRow,
        ((_visibleRect.center.dy - pageTop) / rowHeight).floor(),
      )) {
        final tileTop = pageTop + row * rowHeight;
        if (tileTop + rowHeight <= clipped.top || tileTop >= clipped.bottom) {
          continue;
        }
        for (final column in _nearestIndices(
          firstColumn,
          lastColumn,
          (_visibleRect.center.dx / columnWidth).floor(),
        )) {
          final tileLeft = column * columnWidth;
          if (tileLeft + columnWidth <= clipped.left ||
              tileLeft >= clipped.right) {
            continue;
          }
          specs.add(
            _PdfTileSpec(
              key:
                  '${_renderScale.toStringAsFixed(2)}/$pageIndex/'
                  '$rows.$row/$columns.$column',
              pageIndex: pageIndex,
              region: Rect.fromLTRB(
                column / columns,
                row / rows,
                (column + 1) / columns,
                (row + 1) / rows,
              ),
              bounds: Rect.fromLTWH(tileLeft, tileTop, columnWidth, rowHeight),
            ),
          );
          if (specs.length >= 48) return specs;
        }
      }
    }
    return specs;
  }

  Iterable<int> _nearestIndices(int first, int last, int center) sync* {
    if (last < first) return;
    final middle = center.clamp(first, last).toInt();
    yield middle;
    for (var offset = 1; offset <= last - first; offset++) {
      if (middle + offset <= last) yield middle + offset;
      if (middle - offset >= first) yield middle - offset;
    }
  }

  void _syncPreviews(PdfContinuousLayout layout, Rect range, Rect visible) {
    final first = layout.pageAtOffset(range.top);
    final last = layout.pageAtOffset(
      math.min(range.bottom, layout.totalHeight - 0.01),
    );
    final pages = _nearestIndices(
      first,
      last,
      layout.pageAtOffset(visible.center.dy),
    ).take(8).toList();
    double distance(int page) {
      final top = layout.pageTop(page);
      final bottom = top + layout.pageHeights[page];
      if (bottom > visible.top && top < visible.bottom) return 0;
      return math.min(
        (top - visible.bottom).abs(),
        (bottom - visible.top).abs(),
      );
    }

    pages.sort((a, b) => distance(a).compareTo(distance(b)));
    // Also bound demand for unusual documents containing many tiny pages.
    // Visible pages precede neighbors, and each preview is capped by session.
    final desired = pages.take(8).toSet();
    for (final page in _previews.keys.toList()) {
      if (!desired.contains(page)) _previews.remove(page)!.release();
    }
    for (final page in desired) {
      final priority = distance(page) == 0
          ? PdfRenderPriority.visiblePreview
          : PdfRenderPriority.prefetch;
      final existing = _previews[page];
      if (existing != null) {
        existing.request.priority = priority;
        continue;
      }
      final raster = _PdfRaster(PdfRenderRequest(priority: priority));
      _previews[page] = raster;
      unawaited(
        widget.session
            .renderContinuousPreview(page, layout, request: raster.request)
            .then(
              (image) {
                if (!mounted || !identical(_previews[page], raster)) {
                  image.dispose();
                  return;
                }
                setState(() => raster.image = image);
              },
              onError: (Object error) {
                // A preview is optional. A real detail failure still reaches
                // the existing Retry/Back UI; cancellation is never an error.
                if (!mounted || !identical(_previews[page], raster)) return;
                if (error is PdfRenderCancelledException &&
                    !raster.request.isCancelled) {
                  _previews.remove(page)!.release();
                  _scheduleDemandRetry();
                }
              },
            ),
      );
    }
  }

  void _syncTiles(
    PdfContinuousLayout layout,
    List<_PdfTileSpec> specs,
    Rect visible,
  ) {
    final desired = specs.map((spec) => spec.key).toSet();
    for (final key in _tiles.keys.toList()) {
      if (!desired.contains(key)) _tiles.remove(key)!.release();
    }
    for (final spec in specs) {
      final priority = spec.bounds.overlaps(visible)
          ? PdfRenderPriority.visible
          : PdfRenderPriority.prefetch;
      final existing = _tiles[spec.key];
      if (existing != null) {
        existing.request.priority = priority;
        continue;
      }
      final raster = _PdfRaster(PdfRenderRequest(priority: priority));
      _tiles[spec.key] = raster;
      unawaited(
        widget.session
            .renderContinuousTile(
              spec.pageIndex,
              layout,
              devicePixelRatio: widget.devicePixelRatio,
              renderScale: _renderScale,
              region: spec.region,
              request: raster.request,
            )
            .then(
              (image) {
                if (!mounted || !identical(_tiles[spec.key], raster)) {
                  image.dispose();
                  return;
                }
                setState(() => raster.image = image);
              },
              onError: (Object error) {
                if (!mounted || !identical(_tiles[spec.key], raster)) return;
                if (error is PdfRenderCancelledException) {
                  if (!raster.request.isCancelled) {
                    _tiles.remove(spec.key)!.release();
                    _scheduleDemandRetry();
                  }
                  return;
                }
                setState(() => _renderFailed = true);
              },
            ),
      );
    }
  }

  Widget _positionImage(Rect bounds, ui.Image image, Key key) {
    return Positioned(
      key: key,
      left: (bounds.left - _originX) * _scale,
      top: (bounds.top - _originY) * _scale,
      // Half-pixel overdraw avoids seams at fractional transforms.
      width: bounds.width * _scale + 0.5,
      height: bounds.height * _scale + 0.5,
      child: RawImage(
        image: image,
        fit: BoxFit.fill,
        filterQuality: FilterQuality.low,
      ),
    );
  }

  void _scheduleDemandRetry() {
    if (_retryTimer?.isActive ?? false) return;
    _retryTimer = Timer(const Duration(milliseconds: 100), () {
      if (mounted) setState(() {});
    });
  }
}

class _PdfTileSpec {
  final String key;
  final int pageIndex;
  final Rect region;
  final Rect bounds;

  const _PdfTileSpec({
    required this.key,
    required this.pageIndex,
    required this.region,
    required this.bounds,
  });
}

class _PdfRaster {
  final PdfRenderRequest request;
  ui.Image? image;

  _PdfRaster(this.request);

  void release() {
    request.cancel();
    final previous = image;
    image = null;
    if (previous != null) _releaseAfterFrame(previous);
  }
}

class _PdfFallbackTile {
  final Rect bounds;
  final ui.Image image;

  _PdfFallbackTile(this.bounds, this.image);
}

void _releaseAfterFrame(ui.Image image) {
  WidgetsBinding.instance.addPostFrameCallback((_) => image.dispose());
}

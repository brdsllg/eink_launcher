import 'package:flutter/material.dart';

// Shared storage root — present on every Android device. Used as the
// universal fallback home folder and as the "whole device" search scope.
const String kStorageRoot = '/storage/emulated/0';

// Default row height for generic paginated lists such as the app drawer. The
// file browser overrides this with its orientation-derived shared band height.
const double kRowHeight = 60.0;

// Default navigation height for generic paginated lists. The file browser
// overrides this so its bottom bar exactly matches every other band.
const double kNavBarHeight = 56.0;

// The file browser divides the full display into a fixed number of equal
// horizontal bands. These totals include its top, Up, and bottom bars.
const int kPortraitBarCount = 15;
const int kLandscapeBarCount = 12;

// Phase 8: no page-transition animations (e-ink ghosting/jank risk). Wrap
// any pushed route in this instead of using MaterialPageRoute directly.
Route<T> noTransitionRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
  );
}

// -----------------------------------------------------------------------------
// Reader Constants
// -----------------------------------------------------------------------------

/// File extensions opened by the built-in document reader.
const Set<String> kReadableExtensions = {'.pdf', '.epub', '.txt', '.md'};

/// Three equal vertical tap zones: previous, menu, and next.
const double kTapZoneEdgeWidthRatio = 1 / 3;
const double kTapZoneCenterWidthRatio = 1 / 3;

/// Default vertical sub-screen overlap for fit-width page turns. Zoom / Scroll
/// never uses it: that mode moves by the currently visible viewport height.
const double kPdfDefaultSplitOverlap = 0.06;

/// Maximum pixel dimension on the long edge when rendering whole PDF pages
/// for the tap-driven fit-height and fit-width modes.
const double kPdfMaxRenderDimension = 2048.0;

/// Zoom / Scroll pinch ceiling.
const double kPdfMaxZoomScale = 5.0;

/// Zoom / Scroll pinch floor when zooming out past the page is disabled.
/// 1.0 means "page exactly fills the screen width".
const double kPdfMinZoomScale = 1.0;

/// Zoom / Scroll pinch floor when zooming out past the page is enabled
/// (the default). Reaching it also requires a matching `boundaryMargin`,
/// because InteractiveViewer independently refuses to shrink a child below
/// the size of its own boundary rect.
const double kPdfMinZoomScaleBeyondFit = 0.4;

/// Discrete zoom rungs at which Zoom / Scroll re-rasterises pages through
/// PDFium. Without this, zooming would only magnify an existing bitmap and
/// vector content would go soft.
const List<double> kPdfZoomRenderScales = [
  0.5,
  0.75,
  1.0,
  1.5,
  2.0,
  3.0,
  4.0,
  5.0,
];

/// Longest side, in device pixels, of one Zoom / Scroll tile. Pages are cut
/// into a 2-D grid of at most this size, so a deep zoom renders only the few
/// tiles actually on screen instead of one enormous full-width strip.
const double kPdfTileSidePixels = 1536.0;

/// Hard ceiling for a single tile render. Tiles are built to stay under
/// [kPdfTileSidePixels], so this should never bind; if it ever did, PDFium
/// output would be silently downscaled and zoom would look blurry.
const double kPdfMaxTileDimension = 2048.0;

/// Friction applied to a Zoom / Scroll fling. Lower than Flutter's default
/// (0.0000135) because an e-ink panel only shows a handful of frames, so a
/// short glide is indistinguishable from no momentum at all.
const double kPdfFlingFrictionCoefficient = 0.0000035;

/// Memory budget for rendered PDF bitmaps. Zoom / Scroll keeps a grid of
/// zoomed tiles plus look-ahead resident at once.
const int kPdfBitmapCacheBytes = 96 * 1024 * 1024;

/// Auto-crop threshold: pixel luminance below this value is considered ink/content.
const int kPdfInkLuminanceThreshold = 245;

/// Font size steps mapping (step 0..7) to logical font points.
const List<double> kReaderFontSizeSteps = [
  12.0,
  14.0,
  16.0,
  18.0,
  20.0,
  22.0,
  26.0,
  30.0,
];

/// Margin steps mapping (step 0..3: tight, normal, wide, extra).
const List<double> kReaderMarginSteps = [8.0, 16.0, 24.0, 36.0];

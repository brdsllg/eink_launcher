import 'package:flutter/material.dart';

// Shared storage root — present on every Android device. Used as the
// universal fallback home folder and as the "whole device" search scope.
const String kStorageRoot = '/storage/emulated/0';

// Fixed row height for paginated lists (file browser, app drawer). Rows are
// pinned to this height so the page-size calculation in each screen
// (available height ÷ row height) is exact, regardless of text scale or
// theme density.
const double kRowHeight = 60.0;

// Height of the Previous/Next bar under each paginated list. Must match
// PageNavBar's own height — kept as one constant so they can't drift apart.
const double kNavBarHeight = 56.0;

// Height of the file browser's "Up a folder" bar. Kept separate from
// kNavBarHeight since it isn't load-bearing for any page-size math, just
// visual consistency with the enlarged nav bar.
const double kFolderUpBarHeight = 56.0;

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
const Set<String> kReadableExtensions = {
  '.pdf',
  '.epub',
  '.txt',
  '.md',
};

/// Tap zone proportions across the viewport width for page turning & menu.
const double kTapZoneEdgeWidthRatio = 0.30;
const double kTapZoneCenterWidthRatio = 0.40;
const double kTapZoneZoomEdgeRatio = 0.12;

/// Default vertical sub-screen overlap for fit-width and continuous scroll tap-jump.
const double kPdfDefaultSplitOverlap = 0.06;

/// Maximum pixel dimension on the long edge when rendering PDF pages.
const double kPdfMaxRenderDimension = 2048.0;

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
const List<double> kReaderMarginSteps = [
  8.0,
  16.0,
  24.0,
  36.0,
];

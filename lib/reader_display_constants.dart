// Pure-Dart reader display constants.
//
// Split out of lib/constants.dart (which imports package:flutter/material.dart)
// so laptop-side tooling (tool/build_study_index.dart) and `dart analyze/run`
// can use these values without a Flutter SDK. The app-facing constants.dart
// re-exports this file, so existing imports keep working unchanged.
const double kPdfDefaultSplitOverlap = 0.06;

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

/// Zoom / Scroll pinch floor when zooming out past the page is disabled.
/// 1.0 means "page exactly fills the screen width".
const double kPdfMinZoomScale = 1.0;

/// Absolute hard floor for the Zoom / Scroll pinch, regardless of what
/// [kPdfZoomOutPageSpan] works out to.
const double kPdfMinZoomScaleBeyondFit = 0.2;

/// How many pages tall the viewport becomes when Zoom / Scroll is pinched all
/// the way out.
const double kPdfZoomOutPageSpan = 2.0;

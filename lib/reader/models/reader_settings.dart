import '../../constants.dart';

enum PdfFitMode { fitHeight, fitWidth, zoom }

enum ParagraphMode { blankLine, firstLineIndent }

class ReaderSettings {
  // Text formats typography
  final String latinFontFamily;
  final String hebrewFontFamily;
  final int fontSizeStep; // index into kReaderFontSizeSteps (0..7)
  final double lineHeight; // 1.2 .. 2.0
  final int marginStep; // index into kReaderMarginSteps (0..3)
  final bool justify;
  final bool hyphenate;
  final ParagraphMode paragraphMode;
  final bool honorPublisherCss;

  // PDF display
  final PdfFitMode fitMode;
  final bool autoCrop;
  final double splitOverlap;

  /// Zoom / Scroll only: allow pinching in below the fit-width size, so pages
  /// shrink and roughly two pages fit on screen at once. Default on.
  final bool allowZoomOutBeyondFit;

  // Shared
  final bool landscape;

  const ReaderSettings({
    this.latinFontFamily = 'Literata',
    this.hebrewFontFamily = 'Frank Ruhl Libre',
    this.fontSizeStep = 3, // 18.0 pt
    this.lineHeight = 1.4,
    this.marginStep = 1, // 16.0 px
    this.justify = true,
    this.hyphenate = true,
    this.paragraphMode = ParagraphMode.blankLine,
    this.honorPublisherCss = true,
    this.fitMode = PdfFitMode.fitHeight,
    this.autoCrop = true,
    this.splitOverlap = kPdfDefaultSplitOverlap,
    this.allowZoomOutBeyondFit = true,
    this.landscape = false,
  });

  double get fontSize =>
      kReaderFontSizeSteps[fontSizeStep.clamp(
        0,
        kReaderFontSizeSteps.length - 1,
      )];
  double get horizontalMargin =>
      kReaderMarginSteps[marginStep.clamp(0, kReaderMarginSteps.length - 1)];

  /// The absolute Zoom / Scroll pinch floor implied by
  /// [allowZoomOutBeyondFit]. The view narrows this further per document so
  /// that fully zoomed out shows about [kPdfZoomOutPageSpan] pages, which
  /// depends on the real page aspect ratio and so cannot live here.
  double get minZoomScale =>
      allowZoomOutBeyondFit ? kPdfMinZoomScaleBeyondFit : kPdfMinZoomScale;

  ReaderSettings copyWith({
    String? latinFontFamily,
    String? hebrewFontFamily,
    int? fontSizeStep,
    double? lineHeight,
    int? marginStep,
    bool? justify,
    bool? hyphenate,
    ParagraphMode? paragraphMode,
    bool? honorPublisherCss,
    PdfFitMode? fitMode,
    bool? autoCrop,
    double? splitOverlap,
    bool? allowZoomOutBeyondFit,
    bool? landscape,
  }) {
    return ReaderSettings(
      latinFontFamily: latinFontFamily ?? this.latinFontFamily,
      hebrewFontFamily: hebrewFontFamily ?? this.hebrewFontFamily,
      fontSizeStep: fontSizeStep ?? this.fontSizeStep,
      lineHeight: lineHeight ?? this.lineHeight,
      marginStep: marginStep ?? this.marginStep,
      justify: justify ?? this.justify,
      hyphenate: hyphenate ?? this.hyphenate,
      paragraphMode: paragraphMode ?? this.paragraphMode,
      honorPublisherCss: honorPublisherCss ?? this.honorPublisherCss,
      fitMode: fitMode ?? this.fitMode,
      autoCrop: autoCrop ?? this.autoCrop,
      splitOverlap: splitOverlap ?? this.splitOverlap,
      allowZoomOutBeyondFit:
          allowZoomOutBeyondFit ?? this.allowZoomOutBeyondFit,
      landscape: landscape ?? this.landscape,
    );
  }

  Map<String, dynamic> toJson() => {
    'latinFontFamily': latinFontFamily,
    'hebrewFontFamily': hebrewFontFamily,
    'fontSizeStep': fontSizeStep,
    'lineHeight': lineHeight,
    'marginStep': marginStep,
    'justify': justify,
    'hyphenate': hyphenate,
    'paragraphMode': paragraphMode.name,
    'honorPublisherCss': honorPublisherCss,
    'fitMode': fitMode.name,
    'autoCrop': autoCrop,
    'splitOverlap': splitOverlap,
    'allowZoomOutBeyondFit': allowZoomOutBeyondFit,
    'landscape': landscape,
  };

  factory ReaderSettings.fromJson(Map<String, dynamic> json) {
    final storedFitMode = json['fitMode'] as String?;
    final fitMode = switch (storedFitMode) {
      'fitWidth' => PdfFitMode.fitWidth,
      'continuousScroll' || 'freeZoom' || 'zoom' => PdfFitMode.zoom,
      _ => PdfFitMode.fitHeight,
    };
    return ReaderSettings(
      latinFontFamily: json['latinFontFamily'] as String? ?? 'Literata',
      hebrewFontFamily:
          json['hebrewFontFamily'] as String? ?? 'Frank Ruhl Libre',
      fontSizeStep: json['fontSizeStep'] as int? ?? 3,
      lineHeight: (json['lineHeight'] as num?)?.toDouble() ?? 1.4,
      marginStep: json['marginStep'] as int? ?? 1,
      justify: json['justify'] as bool? ?? true,
      hyphenate: json['hyphenate'] as bool? ?? true,
      paragraphMode: json['paragraphMode'] != null
          ? ParagraphMode.values.byName(json['paragraphMode'] as String)
          : ParagraphMode.blankLine,
      honorPublisherCss: json['honorPublisherCss'] as bool? ?? true,
      fitMode: fitMode,
      autoCrop: json['autoCrop'] as bool? ?? true,
      splitOverlap:
          (json['splitOverlap'] as num?)?.toDouble() ?? kPdfDefaultSplitOverlap,
      allowZoomOutBeyondFit: json['allowZoomOutBeyondFit'] as bool? ?? true,
      landscape: json['landscape'] as bool? ?? false,
    );
  }
}

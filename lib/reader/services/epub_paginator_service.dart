import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/content_block.dart';
import '../models/laid_out_page.dart';
import '../models/reader_settings.dart';
import '../models/reading_position.dart';
import 'hyphenation_service.dart';

/// Deterministic layout shared by EPUB, plain-text, and Markdown documents.
///
/// Pagination deliberately runs on the UI isolate: [TextPainter] is the same
/// engine used by the eventual page widget, so page boundaries are real line
/// boundaries rather than estimates that can clip glyphs when rendered.
class EpubPaginatorService {
  const EpubPaginatorService();

  List<LaidOutPage> paginateSpine({
    required int spineIndex,
    required List<ContentBlock> blocks,
    required Size contentSize,
    required ReaderSettings settings,
    Map<String, Size> imageSizes = const {},
  }) {
    if (contentSize.width <= 0 || contentSize.height <= 0 || blocks.isEmpty) {
      return const [];
    }

    final pages = <LaidOutPage>[];
    var pageSlices = <BlockSlice>[];
    var usedHeight = 0.0;

    void finishPage() {
      if (pageSlices.isEmpty) return;
      final first = pageSlices.first;
      final last = pageSlices.last;
      pages.add(
        LaidOutPage(
          pageIndex: pages.length,
          slices: List<BlockSlice>.unmodifiable(pageSlices),
          start: TextReadingPosition(
            spineIndex: spineIndex,
            blockIndex: first.blockIndex,
            charOffset: first.startCharOffset,
          ),
          end: TextReadingPosition(
            spineIndex: spineIndex,
            blockIndex: last.blockIndex,
            charOffset: last.endCharOffset,
          ),
        ),
      );
      pageSlices = <BlockSlice>[];
      usedHeight = 0;
    }

    for (var blockIndex = 0; blockIndex < blocks.length; blockIndex++) {
      final block = blocks[blockIndex];
      final layout = TextBlockLayout.measure(
        block: block,
        width: contentSize.width,
        pageHeight: contentSize.height,
        settings: settings,
        imageSize: block.resourcePath == null
            ? null
            : imageSizes[block.resourcePath],
      );

      if (layout.lines.isEmpty) {
        final remaining = contentSize.height - usedHeight;
        if (pageSlices.isNotEmpty && layout.height > remaining + 0.01) {
          finishPage();
        }
        final sliceHeight = math.min(layout.height, contentSize.height);
        pageSlices.add(
          BlockSlice(
            blockIndex: blockIndex,
            startCharOffset: 0,
            endCharOffset: block.characterCount,
            sourceTop: 0,
            height: sliceHeight,
          ),
        );
        usedHeight += sliceHeight;
        if (usedHeight >= contentSize.height - 0.01) finishPage();
        continue;
      }

      var lineIndex = 0;
      while (lineIndex < layout.lines.length) {
        var remaining = contentSize.height - usedHeight;
        var fitCount = layout.linesFitting(
          startLine: lineIndex,
          availableHeight: remaining,
        );

        if (fitCount == 0 && pageSlices.isNotEmpty) {
          finishPage();
          remaining = contentSize.height;
          fitCount = layout.linesFitting(
            startLine: lineIndex,
            availableHeight: remaining,
          );
        }

        // A line can exceed the page only with extreme settings. Always make
        // forward progress and clip it to the viewport rather than looping.
        if (fitCount == 0) fitCount = 1;

        final linesLeft = layout.lines.length - lineIndex;
        if (lineIndex == 0 &&
            fitCount == 1 &&
            linesLeft > 1 &&
            pageSlices.isNotEmpty) {
          finishPage();
          continue;
        }
        if (linesLeft - fitCount == 1 && fitCount > 1) fitCount -= 1;

        final firstLine = layout.lines[lineIndex];
        final lastLine = layout.lines[lineIndex + fitCount - 1];
        final isLastSlice = lineIndex + fitCount == layout.lines.length;
        final rawHeight = lastLine.bottom - firstLine.top;
        final sliceHeight = math.min(
          rawHeight + (isLastSlice ? layout.spacingAfter : 0),
          contentSize.height - usedHeight,
        );
        pageSlices.add(
          BlockSlice(
            blockIndex: blockIndex,
            startCharOffset: firstLine.startCharOffset,
            endCharOffset: lastLine.endCharOffset,
            sourceTop: firstLine.top,
            height: sliceHeight,
          ),
        );
        usedHeight += sliceHeight;
        lineIndex += fitCount;

        if (lineIndex < layout.lines.length ||
            usedHeight >= contentSize.height - 0.01) {
          finishPage();
        }
      }
    }
    finishPage();
    return List<LaidOutPage>.unmodifiable(pages);
  }
}

class TextLineLayout {
  final double top;
  final double bottom;
  final int startCharOffset;
  final int endCharOffset;

  const TextLineLayout({
    required this.top,
    required this.bottom,
    required this.startCharOffset,
    required this.endCharOffset,
  });
}

/// A measured block. The renderer calls the same helpers, ensuring its text
/// geometry stays byte-for-byte aligned with the paginator.
class TextBlockLayout {
  final double textHeight;
  final double spacingAfter;
  final double height;
  final List<TextLineLayout> lines;

  const TextBlockLayout({
    required this.textHeight,
    required this.spacingAfter,
    required this.height,
    required this.lines,
  });

  int linesFitting({required int startLine, required double availableHeight}) {
    if (startLine >= lines.length || availableHeight <= 0) return 0;
    final top = lines[startLine].top;
    var count = 0;
    for (var i = startLine; i < lines.length; i++) {
      final includesSpacing = i == lines.length - 1 ? spacingAfter : 0.0;
      if (lines[i].bottom - top + includesSpacing > availableHeight + 0.01) {
        break;
      }
      count++;
    }
    return count;
  }

  static TextBlockLayout measure({
    required ContentBlock block,
    required double width,
    required double pageHeight,
    required ReaderSettings settings,
    Size? imageSize,
  }) {
    final spacing = spacingFor(block, settings);
    if (block.type == BlockType.horizontalRule) {
      return TextBlockLayout(
        textHeight: 2,
        spacingAfter: spacing,
        height: 2 + spacing,
        lines: const [],
      );
    }
    if (block.type == BlockType.image) {
      final size = fittedImageSize(
        imageSize,
        maxWidth: width,
        maxHeight: pageHeight * 0.72,
      );
      return TextBlockLayout(
        textHeight: size.height,
        spacingAfter: spacing,
        height: size.height + spacing,
        lines: const [],
      );
    }

    final prefix = prefixFor(block, settings);
    final painter = TextPainter(
      text: buildTextSpan(block, settings, prefix: prefix),
      textDirection: directionFor(block),
      textAlign: alignmentFor(block, settings),
      textScaler: TextScaler.noScaling,
    )..layout(maxWidth: width);
    final lineMetrics = painter.computeLineMetrics();
    final lines = <TextLineLayout>[];
    for (final metric in lineMetrics) {
      final top = math.max(0.0, metric.baseline - metric.ascent);
      final bottom = math.max(top, metric.baseline + metric.descent);
      final y = metric.baseline - metric.ascent + metric.height / 2;
      final x = (metric.left + metric.width / 2).clamp(0.0, width);
      final position = painter.getPositionForOffset(Offset(x, y));
      final boundary = painter.getLineBoundary(position);
      final displayedText = displayedPlainText(block, settings);
      lines.add(
        TextLineLayout(
          top: top,
          bottom: bottom,
          startCharOffset: _sourceOffsetForDisplay(
            displayedText,
            boundary.start - prefix.length,
          ).clamp(0, block.characterCount),
          endCharOffset: _sourceOffsetForDisplay(
            displayedText,
            boundary.end - prefix.length,
          ).clamp(0, block.characterCount),
        ),
      );
    }
    return TextBlockLayout(
      textHeight: painter.height,
      spacingAfter: spacing,
      height: painter.height + spacing,
      lines: List<TextLineLayout>.unmodifiable(lines),
    );
  }

  static TextSpan buildTextSpan(
    ContentBlock block,
    ReaderSettings settings, {
    String? prefix,
  }) {
    final base = baseStyleFor(block, settings);
    final children = <InlineSpan>[];
    final actualPrefix = prefix ?? prefixFor(block, settings);
    if (actualPrefix.isNotEmpty) children.add(TextSpan(text: actualPrefix));
    for (final run in block.runs) {
      final text = settings.hyphenate
          ? const HyphenationService().hyphenateLatinText(run.text)
          : run.text;
      children.add(
        TextSpan(
          text: text,
          style: base.copyWith(
            fontWeight: run.bold ? FontWeight.bold : null,
            fontStyle: run.italic ? FontStyle.italic : null,
            fontFamily: run.code ? 'Inter' : null,
          ),
        ),
      );
    }
    return TextSpan(style: base, children: children);
  }

  static TextStyle baseStyleFor(ContentBlock block, ReaderSettings settings) {
    final multiplier = switch (block.type) {
      BlockType.heading1 => 1.65,
      BlockType.heading2 => 1.45,
      BlockType.heading3 => 1.3,
      BlockType.heading4 => 1.18,
      BlockType.heading5 => 1.1,
      BlockType.heading6 => 1.05,
      BlockType.preformatted => 0.9,
      _ => 1.0,
    };
    final bold = switch (block.type) {
      BlockType.heading1 ||
      BlockType.heading2 ||
      BlockType.heading3 ||
      BlockType.heading4 ||
      BlockType.heading5 ||
      BlockType.heading6 => FontWeight.bold,
      _ => FontWeight.normal,
    };
    final primary = block.direction == BlockTextDirection.rtl
        ? settings.hebrewFontFamily
        : settings.latinFontFamily;
    final fallback = block.direction == BlockTextDirection.rtl
        ? <String>[settings.latinFontFamily]
        : <String>[settings.hebrewFontFamily];
    return TextStyle(
      color: Colors.black,
      fontFamily: primary,
      fontFamilyFallback: fallback,
      fontSize: settings.fontSize * multiplier,
      height: settings.lineHeight,
      fontWeight: bold,
      decoration: TextDecoration.none,
    );
  }

  static String prefixFor(ContentBlock block, ReaderSettings settings) {
    final listPrefix = block.type == BlockType.listItem
        ? '${'  ' * block.nestingLevel}${block.orderedList ? '1.' : '•'} '
        : '';
    final quotePrefix = block.type == BlockType.blockquote ? '│ ' : '';
    final indent =
        block.type == BlockType.paragraph &&
            settings.paragraphMode == ParagraphMode.firstLineIndent
        ? '\u2003\u2003'
        : '';
    return '$listPrefix$quotePrefix$indent';
  }

  static String displayedPlainText(
    ContentBlock block,
    ReaderSettings settings,
  ) => block.runs
      .map(
        (run) => settings.hyphenate
            ? const HyphenationService().hyphenateLatinText(run.text)
            : run.text,
      )
      .join();

  static int _sourceOffsetForDisplay(String displayedText, int offset) {
    final end = offset.clamp(0, displayedText.length);
    var sourceOffset = 0;
    for (var i = 0; i < end; i++) {
      if (displayedText.codeUnitAt(i) != 0x00ad) sourceOffset++;
    }
    return sourceOffset;
  }

  static double spacingFor(ContentBlock block, ReaderSettings settings) {
    final em = settings.fontSize;
    return switch (block.type) {
      BlockType.heading1 || BlockType.heading2 => em * 0.8,
      BlockType.heading3 ||
      BlockType.heading4 ||
      BlockType.heading5 ||
      BlockType.heading6 => em * 0.55,
      BlockType.paragraph
          when settings.paragraphMode == ParagraphMode.firstLineIndent =>
        em * 0.18,
      BlockType.horizontalRule || BlockType.image => em * 0.65,
      _ => em * 0.55,
    };
  }

  static TextDirection directionFor(ContentBlock block) =>
      block.direction == BlockTextDirection.rtl
      ? TextDirection.rtl
      : TextDirection.ltr;

  static TextAlign alignmentFor(ContentBlock block, ReaderSettings settings) {
    if (settings.justify && block.type == BlockType.paragraph) {
      return TextAlign.justify;
    }
    if (!settings.honorPublisherCss) return TextAlign.start;
    return switch (block.alignment) {
      BlockAlignment.center => TextAlign.center,
      BlockAlignment.end => TextAlign.end,
      BlockAlignment.justify => TextAlign.justify,
      BlockAlignment.start => TextAlign.start,
    };
  }

  static Size fittedImageSize(
    Size? source, {
    required double maxWidth,
    required double maxHeight,
  }) {
    if (source == null || source.width <= 0 || source.height <= 0) {
      return Size(maxWidth, math.min(maxHeight, 160));
    }
    final scale = math.min(maxWidth / source.width, maxHeight / source.height);
    return Size(source.width * scale, source.height * scale);
  }
}

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/content_block.dart';
import '../models/laid_out_page.dart';
import '../models/reader_settings.dart';
import '../services/epub_paginator_service.dart';

class BlockSliceView extends StatelessWidget {
  final ContentBlock block;
  final BlockSlice slice;
  final ReaderSettings settings;
  final double pageHeight;
  final Uint8List? imageBytes;

  const BlockSliceView({
    super.key,
    required this.block,
    required this.slice,
    required this.settings,
    required this.pageHeight,
    this.imageBytes,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: slice.height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final layout = TextBlockLayout.measure(
            block: block,
            width: constraints.maxWidth,
            pageHeight: pageHeight,
            settings: settings,
          );
          return ClipRect(
            child: OverflowBox(
              alignment: Alignment.topCenter,
              minHeight: 0,
              maxHeight: double.infinity,
              child: Transform.translate(
                offset: Offset(0, -slice.sourceTop),
                child: SizedBox(
                  width: constraints.maxWidth,
                  height: layout.height,
                  child: _buildBlock(layout),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBlock(TextBlockLayout layout) {
    if (block.type == BlockType.horizontalRule) {
      return Align(
        alignment: Alignment.topCenter,
        child: Container(height: 2, color: Colors.black),
      );
    }
    if (block.type == BlockType.image) {
      return SizedBox(
        height: layout.textHeight,
        child: imageBytes == null
            ? Center(child: Text(block.alternateText ?? 'Image'))
            : ColorFiltered(
                colorFilter: ColorFilter.matrix(
                  settings.colorEnabled
                      ? const [
                          1,
                          0,
                          0,
                          0,
                          0,
                          0,
                          1,
                          0,
                          0,
                          0,
                          0,
                          0,
                          1,
                          0,
                          0,
                          0,
                          0,
                          0,
                          1,
                          0,
                        ]
                      : const [
                          .299,
                          .587,
                          .114,
                          0,
                          0,
                          .299,
                          .587,
                          .114,
                          0,
                          0,
                          .299,
                          .587,
                          .114,
                          0,
                          0,
                          0,
                          0,
                          0,
                          1,
                          0,
                        ],
                ),
                child: Image.memory(
                  imageBytes!,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.none,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) =>
                      Center(child: Text(block.alternateText ?? 'Image')),
                ),
              ),
      );
    }
    return Semantics(
      label: block.plainText,
      child: CustomPaint(painter: _TextBlockPainter(block, settings)),
    );
  }
}

class _TextBlockPainter extends CustomPainter {
  final ContentBlock block;
  final ReaderSettings settings;
  _TextBlockPainter(this.block, this.settings);

  @override
  void paint(Canvas canvas, Size size) {
    final painter = TextBlockLayout.createPainter(block, settings, size.width);
    painter.paint(canvas, Offset.zero);
    final hyphen = TextPainter(
      text: TextSpan(
        text: '-',
        style: TextBlockLayout.baseStyleFor(block, settings),
      ),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
    )..layout();
    final baseline = hyphen.computeDistanceToActualBaseline(
      TextBaseline.alphabetic,
    );
    for (final offset in TextBlockLayout.hyphenOffsets(
      painter,
      block,
      settings,
    )) {
      hyphen.paint(canvas, offset - Offset(0, baseline));
    }
    hyphen.dispose();
    painter.dispose();
  }

  @override
  bool shouldRepaint(covariant _TextBlockPainter oldDelegate) =>
      oldDelegate.block != block || oldDelegate.settings != settings;
}

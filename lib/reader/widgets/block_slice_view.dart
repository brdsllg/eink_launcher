import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/content_block.dart';
import '../models/laid_out_page.dart';
import '../models/reader_settings.dart';
import '../services/epub_paginator_service.dart';
import '../services/text_word_selection.dart';

class BlockSliceView extends StatefulWidget {
  final ContentBlock block;
  final BlockSlice slice;
  final ReaderSettings settings;
  final double pageHeight;
  final Uint8List? imageBytes;
  final Future<void> Function(String word)? onDefineWord;

  const BlockSliceView({
    super.key,
    required this.block,
    required this.slice,
    required this.settings,
    required this.pageHeight,
    this.imageBytes,
    this.onDefineWord,
  });

  @override
  State<BlockSliceView> createState() => _BlockSliceViewState();
}

class _BlockSliceViewState extends State<BlockSliceView> {
  TextSelection? _selection;
  ContentBlock get block => widget.block;
  BlockSlice get slice => widget.slice;
  ReaderSettings get settings => widget.settings;
  double get pageHeight => widget.pageHeight;
  Uint8List? get imageBytes => widget.imageBytes;

  @override
  void didUpdateWidget(BlockSliceView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.block != block ||
        oldWidget.slice != slice ||
        oldWidget.settings != settings) {
      _selection = null;
    }
  }

  Future<void> _selectWord(Offset offset, double width) async {
    if (_selection != null) return;
    final painter = TextBlockLayout.createPainter(block, settings, width);
    final selected = wordAtOffset(
      painter,
      offset,
      prefixLength: TextBlockLayout.prefixFor(block, settings).length,
    );
    painter.dispose();
    if (selected == null) return;
    setState(() => _selection = selected.selection);
    try {
      await widget.onDefineWord!(selected.word);
    } finally {
      if (mounted) setState(() => _selection = null);
    }
  }

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
                  child: _buildBlock(layout, constraints.maxWidth),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBlock(TextBlockLayout layout, double width) {
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
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPressStart: widget.onDefineWord == null
            ? null
            : (details) => _selectWord(details.localPosition, width),
        child: CustomPaint(
          painter: _TextBlockPainter(block, settings, _selection),
        ),
      ),
    );
  }
}

class _TextBlockPainter extends CustomPainter {
  final ContentBlock block;
  final ReaderSettings settings;
  final TextSelection? selection;
  _TextBlockPainter(this.block, this.settings, this.selection);

  @override
  void paint(Canvas canvas, Size size) {
    final painter = TextBlockLayout.createPainter(block, settings, size.width);
    if (selection != null) {
      for (final box in painter.getBoxesForSelection(selection!)) {
        canvas.drawRect(box.toRect(), Paint()..color = const Color(0xFFD0D0D0));
      }
    }
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
      oldDelegate.block != block ||
      oldDelegate.settings != settings ||
      oldDelegate.selection != selection;
}

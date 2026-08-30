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
            : Image.memory(
                imageBytes!,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.none,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) =>
                    Center(child: Text(block.alternateText ?? 'Image')),
              ),
      );
    }
    return RichText(
      text: TextBlockLayout.buildTextSpan(block, settings),
      textDirection: TextBlockLayout.directionFor(block),
      textAlign: TextBlockLayout.alignmentFor(block, settings),
      textScaler: TextScaler.noScaling,
    );
  }
}

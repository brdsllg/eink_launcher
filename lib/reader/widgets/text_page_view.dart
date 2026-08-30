import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../controllers/text_reader_session.dart';
import 'block_slice_view.dart';

class TextPageView extends StatefulWidget {
  final TextReaderSession session;

  const TextPageView({super.key, required this.session});

  @override
  State<TextPageView> createState() => _TextPageViewState();
}

class _TextPageViewState extends State<TextPageView> {
  Size? _reportedSize;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.white,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final viewport = constraints.biggest;
          if (viewport.isFinite && viewport != _reportedSize) {
            _reportedSize = viewport;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) widget.session.updateViewport(viewport);
            });
          }
          final page = widget.session.currentLaidOutPage;
          final book = widget.session.book;
          if (page == null || book == null) {
            return Center(
              child: Text(
                widget.session.isPaginating
                    ? 'Laying out pages…'
                    : (book?.spine.every((item) => item.blocks.isEmpty) ??
                          false)
                    ? 'No readable text in this document'
                    : 'Preparing document…',
              ),
            );
          }
          final margin = widget.session.settings.horizontalMargin;
          return Padding(
            padding: EdgeInsets.all(margin),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final slice in page.slices)
                  BlockSliceView(
                    block: book
                        .spine[page.start.spineIndex]
                        .blocks[slice.blockIndex],
                    slice: slice,
                    settings: widget.session.settings,
                    pageHeight: viewport.height - margin * 2,
                    imageBytes: _resourceFor(
                      book.resources,
                      book
                          .spine[page.start.spineIndex]
                          .blocks[slice.blockIndex]
                          .resourcePath,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Uint8List? _resourceFor(Map<String, Uint8List> resources, String? path) =>
      path == null ? null : resources[path];
}

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../controllers/text_reader_session.dart';
import '../models/annotation.dart';
import '../models/book_state.dart';
import '../services/book_store_service.dart';
import 'annotation_dialog.dart';
import 'block_slice_view.dart';
import 'dictionary_dialog.dart';

class TextPageView extends StatefulWidget {
  final TextReaderSession session;
  final VoidCallback? onContentReady;

  const TextPageView({super.key, required this.session, this.onContentReady});

  @override
  State<TextPageView> createState() => _TextPageViewState();
}

class _TextPageViewState extends State<TextPageView> {
  Size? _reportedSize;
  bool _contentReported = false;

  Future<void> _addAnnotation(
    int spineIndex,
    int blockIndex,
    TextSelection range,
    String text,
    bool addNote,
  ) async {
    final docId = widget.session.doc.id;
    final chapter = widget.session.book!.spine[spineIndex];
    final blockId = chapter.blocks[blockIndex].id;
    final note = addNote ? await showAnnotationEditor(context) : null;
    if (!mounted ||
        widget.session.doc.id != docId ||
        (addNote && note == null)) {
      return;
    }
    final store = BookStoreService.instance;
    // A freshly opened book has no saved state until its first page turn.
    final session = widget.session;
    final state =
        store.getBookState(docId) ??
        BookState(
          docId: docId,
          lastPath: session.doc.path,
          format: session.doc.format,
          lastRead: DateTime.now(),
          position: session.position,
          percent: session.percent,
          bookmarks: session.bookmarks,
        );
    final annotation = Annotation(
      id: Annotation.generateId(),
      docId: docId,
      createdAt: DateTime.now(),
      spineIndex: spineIndex,
      blockIndex: blockIndex,
      documentPath: chapter.href,
      blockId: blockId,
      startOffset: range.start,
      endOffset: range.end,
      text: text,
      note: note,
    );
    store.saveBookState(
      state.copyWith(annotations: [...state.annotations, annotation]),
    );
    setState(() {});
  }

  Future<void> _openAnnotation(Annotation annotation) async {
    final action = await showAnnotationViewer(context, annotation);
    if (!mounted || action == null) return;
    String? note;
    if (action == AnnotationAction.edit) {
      note = await showAnnotationEditor(context, note: annotation.note);
      if (!mounted || note == null) return;
    }
    if (widget.session.doc.id != annotation.docId) return;
    final store = BookStoreService.instance;
    final state = store.getBookState(annotation.docId);
    if (state == null) return;
    store.saveBookState(
      state.copyWith(
        annotations: [
          for (final item in state.annotations)
            if (item.id != annotation.id)
              item
            else if (action == AnnotationAction.edit)
              item.withNote(note!),
        ],
      ),
    );
    setState(() {});
  }

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
          if (!_contentReported &&
              (page != null ||
                  (book?.spine.every((item) => item.blocks.isEmpty) ??
                      false))) {
            _contentReported = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) widget.onContentReady?.call();
            });
          }
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
          final annotations =
              BookStoreService.instance
                  .getBookState(widget.session.doc.id)
                  ?.annotations ??
              const <Annotation>[];
          return Padding(
            padding: EdgeInsets.all(margin),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final slice in page.slices)
                  BlockSliceView(
                    key: ValueKey(
                      '${widget.session.doc.id}:${page.start.spineIndex}:${slice.blockIndex}:${slice.startCharOffset}',
                    ),
                    annotations: annotations
                        .where(
                          (a) => a.matchesBlock(
                            widget.session.book!.spine[page.start.spineIndex],
                            page.start.spineIndex,
                            slice.blockIndex,
                          ),
                        )
                        .toList(),
                    onOpenAnnotation: _openAnnotation,
                    onAnnotate: (range, text, addNote) => _addAnnotation(
                      page.start.spineIndex,
                      slice.blockIndex,
                      range,
                      text,
                      addNote,
                    ),
                    onOpenLink: (href) {
                      final opened = widget.session.openLink(href);
                      if (!opened) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'This link is not available in the reading text.',
                            ),
                          ),
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            duration: const Duration(seconds: 10),
                            content: const Text('Followed book link'),
                            action: SnackBarAction(
                              label: 'Back',
                              onPressed: widget.session.backFromLink,
                            ),
                          ),
                        );
                      }
                    },
                    onDefineWord: (word) =>
                        showDictionaryDefinition(context, word),
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

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

import '../models/annotation.dart';
import '../models/content_block.dart';
import '../models/laid_out_page.dart';
import '../models/reader_settings.dart';
import '../services/epub_paginator_service.dart';
import '../services/text_word_selection.dart';
import '../services/annotation_text_mapping.dart';
import 'selection_toolbar.dart';
import 'tap_zone_layer.dart';

/// A multi-paragraph range built by repeated **More** presses: the local
/// block keeps its start offset, the range covers through [endBlockIndex],
/// and [combinedText] joins every covered paragraph with blank lines.
class ExtendedSelection {
  final int endBlockIndex;
  final String? endBlockId;
  final int endBlockOffset;
  final String combinedText;

  const ExtendedSelection({
    required this.endBlockIndex,
    required this.endBlockId,
    required this.endBlockOffset,
    required this.combinedText,
  });
}

class BlockSliceView extends StatefulWidget {
  final ContentBlock block;
  final BlockSlice slice;
  final ReaderSettings settings;
  final double pageHeight;
  final Uint8List? imageBytes;
  final Size? imageSize;
  final Future<void> Function(String word)? onDefineWord;
  final Future<void> Function(String href)? onOpenLink;
  final List<Annotation> annotations;
  final void Function(Annotation annotation)? onOpenAnnotation;
  final Future<void> Function(TextSelection range, String text, bool addNote)?
  onAnnotate;
  final Future<ExtendedSelection?> Function(TextSelection sourceRange)?
  onExtendSelection;
  final Future<void> Function(
    TextSelection range,
    ExtendedSelection extended,
    bool addNote,
  )?
  onAnnotateExtended;

  const BlockSliceView({
    super.key,
    required this.block,
    required this.slice,
    required this.settings,
    required this.pageHeight,
    this.imageBytes,
    this.imageSize,
    this.onDefineWord,
    this.onOpenLink,
    this.annotations = const [],
    this.onOpenAnnotation,
    this.onAnnotate,
    this.onExtendSelection,
    this.onAnnotateExtended,
  });

  @override
  State<BlockSliceView> createState() => _BlockSliceViewState();
}

class _BlockSliceViewState extends State<BlockSliceView> {
  // A 48 dp target is usable on the HiBreak's e-ink panel while the small
  // visible marker still points precisely at the selected text boundary.
  static const double _selectionHandleSize = 48;
  TextSelection? _selection;
  final _overlay = OverlayPortalController();
  final _surfaceKey = GlobalKey();
  Offset? _dragPosition;
  bool? _draggingStart;
  // Pending multi-paragraph extension owned by the parent page view: the
  // local handle still shows the first block, while copy/dictionary/note
  // apply to the whole range. Cleared with the selection.
  ExtendedSelection? _extended;
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
      _extended = null;
      // Updates arrive during layout; OverlayPortal cannot be hidden there.
      // The null selection immediately removes its controls from this frame.
      if (_overlay.isShowing) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _selection == null) _overlay.hide();
        });
      }
    }
  }

  void _selectWord(Offset offset, double width) {
    final painter = TextBlockLayout.createPainter(block, settings, width);
    final selected = wordAtOffset(
      painter,
      offset,
      prefixLength: TextBlockLayout.prefixFor(block, settings).length,
    );
    painter.dispose();
    if (selected == null) return;
    setState(() => _selection = selected.selection);
    _overlay.show();
  }

  void _clearSelection() {
    _overlay.hide();
    if (mounted) {
      setState(() {
        _selection = null;
        _extended = null;
      });
    }
  }

  Future<void> _act(String action) async {
    final selection = _selection;
    if (selection == null) return;
    final range = AnnotationTextMapping(block, settings).toSource(selection);
    if (range.isCollapsed) return;
    if (action == 'extend') {
      final extend = widget.onExtendSelection;
      if (extend == null) return;
      final extended = await extend(range);
      if (!mounted || extended == null) return;
      // Keep the toolbar open: the local handle grows to the end of this
      // paragraph so the rest looks selected, while copy/dictionary/note
      // below apply to the whole multi-paragraph range.
      final displayEnd =
          TextBlockLayout.prefixFor(block, settings).length +
          TextBlockLayout.displayedPlainText(block, settings).length;
      final toEnd = TextSelection(
        baseOffset: selection.start,
        extentOffset: displayEnd,
      );
      setState(() {
        _selection = toEnd.start == toEnd.end ? selection : toEnd;
        _extended = extended;
      });
      _overlay.show();
      return;
    }
    final extended = _extended;
    if (extended != null) {
      final combined = extended.combinedText;
      final multi = widget.onAnnotateExtended;
      switch (action) {
        case 'copy':
          await Clipboard.setData(ClipboardData(text: combined));
          _clearSelection();
          return;
        case 'dictionary':
          final word = combined.replaceAll(RegExp('[\u200b\u00ad]'), '');
          _clearSelection();
          await widget.onDefineWord?.call(word);
          return;
        default:
          if (multi != null) {
            _clearSelection();
            await multi(range, extended, action == 'note');
            return;
          }
      }
    }
    final text = block.plainText.substring(range.start, range.end);
    _clearSelection();
    switch (action) {
      case 'copy':
        await Clipboard.setData(ClipboardData(text: text));
      case 'dictionary':
        await widget.onDefineWord?.call(
          text.replaceAll(RegExp('[\u200b\u00ad]'), ''),
        );
      default:
        await widget.onAnnotate?.call(range, text, action == 'note');
    }
  }

  // Logical-offset hysteresis before a cross-flip: caret affinity at a
  // line/word edge can snap 1-2 chars at the exact crossing moment, which
  // used to move the supposed-stationary edge. The dragged edge must pass
  // the anchor by more than this before the handles swap roles.
  static const int _flipHysteresis = 2;

  void _dragHandle(bool start, Offset global, double width) {
    final surface = _surfaceKey.currentContext!.findRenderObject() as RenderBox;
    final painter = TextBlockLayout.createPainter(block, settings, width);
    final local = surface.globalToLocal(global) + Offset(0, slice.sourceTop);
    final offset = painter.getPositionForOffset(local).offset;
    final min = TextBlockLayout.prefixFor(block, settings).length;
    final max = painter.text!.toPlainText().length;
    final selection = _selection!;
    painter.dispose();
    final clamped = offset.clamp(min, max);
    // Bidirectional handles (modern-phone style): either handle drags either
    // direction. When the dragged edge crosses the anchor by more than the
    // hysteresis, flip which edge the finger controls so the handle stays
    // under the finger. The anchor itself is never recomputed, so the
    // stationary handle cannot jump letters on flip.
    final anchor = start ? selection.extentOffset : selection.baseOffset;
    TextSelection next;
    var nextStart = start;
    if (start) {
      if (clamped <= anchor + _flipHysteresis) {
        next = selection.copyWith(
          baseOffset: clamped.clamp(min, anchor),
        );
      } else {
        // Crossed: anchor becomes the new start, finger takes the far edge.
        next = TextSelection(baseOffset: anchor, extentOffset: clamped);
        nextStart = !start;
        _draggingStart = nextStart;
        _dragPosition = global;
      }
    } else {
      if (clamped >= anchor - _flipHysteresis) {
        next = selection.copyWith(
          extentOffset: clamped.clamp(anchor, max),
        );
      } else {
        next = TextSelection(baseOffset: clamped, extentOffset: anchor);
        nextStart = !start;
        _draggingStart = nextStart;
        _dragPosition = global;
      }
    }
    // Any extension across paragraphs is rebuilt by the next More press;
    // a handle drag stays inside this block.
    if (_extended != null) _extended = null;
    // Keep at least one char selected.
    if (next.start == next.end) {
      return;
    }
    setState(() => _selection = next);
  }

  Widget _selectionOverlay(BuildContext context, double width) {
    if (_selection == null) return const SizedBox.shrink();
    final painter = TextBlockLayout.createPainter(block, settings, width);
    final boxes = painter.getBoxesForSelection(_selection!);
    painter.dispose();
    if (boxes.isEmpty) return const SizedBox.shrink();
    final isRtl =
        TextBlockLayout.directionFor(block) == TextDirection.rtl;
    final surface = _surfaceKey.currentContext!.findRenderObject() as RenderBox;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final origin = overlay.globalToLocal(surface.localToGlobal(Offset.zero));
    // Visual edges, not logical start/end: for RTL the logical start sits
    // on the right. Using left/right keeps the 48dp targets from overlapping
    // and stops one handle from grabbing the other.
    double edgeX(TextBox box, bool isStartEdge) {
      if (isRtl) return isStartEdge ? box.right : box.left;
      return isStartEdge ? box.left : box.right;
    }

    Offset anchor(TextBox box, bool start) =>
        origin +
        Offset(
          edgeX(box, start),
          (box.bottom - slice.sourceTop).clamp(0.0, slice.height),
        );
    final first = anchor(boxes.first, true);
    final last = anchor(boxes.last, false);
    // Controls live outside the text clip: even a one-line page slice must
    // have a reachable toolbar and handles. Placement first uses slice bounds.
    final localTop = boxes.first.top - slice.sourceTop;
    final desiredTop = localTop >= 56 || last.dy + 72 > overlay.size.height
        ? origin.dy + localTop - 56
        : last.dy + 24;
    final toolbarWidth = width.clamp(0.0, overlay.size.width);
    final top = desiredTop.clamp(
      0.0,
      (overlay.size.height - 56).clamp(0.0, double.infinity),
    );
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            key: const Key('selection-dismiss'),
            behavior: HitTestBehavior.opaque,
            onTap: _clearSelection,
          ),
        ),
        Positioned(
          left: origin.dx.clamp(0.0, overlay.size.width - toolbarWidth),
          top: top,
          width: toolbarWidth,
          child: SelectionToolbar(
            onCopy: () => _act('copy'),
            onDictionary: () => _act('dictionary'),
            onAddNote: () => _act('note'),
            onUnderline: () => _act('underline'),
            onExtend: widget.onExtendSelection == null
                ? null
                : () => _act('extend'),
          ),
        ),
        for (final start in [true, false])
          Positioned(
            left:
                (start
                        ? (isRtl ? first.dx : first.dx - _selectionHandleSize)
                        : (isRtl
                              ? last.dx - _selectionHandleSize
                              : last.dx))
                    .clamp(
                      0.0,
                      overlay.size.width - _selectionHandleSize,
                    ),
            top: (start ? first.dy : last.dy).clamp(
              0.0,
              overlay.size.height - _selectionHandleSize,
            ),
            child: GestureDetector(
              key: Key(
                start ? 'selection-start-handle' : 'selection-end-handle',
              ),
              behavior: HitTestBehavior.opaque,
              onPanStart: (details) {
                _draggingStart = start;
                // Seed from the finger, not the handle center, so slow e-ink
                // frames cannot accumulate delta drift.
                _dragPosition = details.globalPosition;
              },
              onPanUpdate: (details) {
                _dragPosition = details.globalPosition;
                _dragHandle(_draggingStart ?? start, _dragPosition!, width);
              },
              onPanEnd: (_) {
                _draggingStart = null;
              },
              child: SizedBox(
                width: _selectionHandleSize,
                height: _selectionHandleSize,
                child: Align(
                  alignment: start
                      ? (isRtl ? Alignment.topLeft : Alignment.topRight)
                      : (isRtl ? Alignment.topRight : Alignment.topLeft),
                  child: Container(width: 12, height: 24, color: Colors.black),
                ),
              ),
            ),
          ),
      ],
    );
  }

  List<Widget> _annotationTargets(double width) {
    final painter = TextBlockLayout.createPainter(block, settings, width);
    final mapping = AnnotationTextMapping(block, settings);
    TextSelection? displayFor(Annotation annotation) {
      if (!annotation.isMultiBlock) return mapping.toDisplay(annotation);
      final length = block.plainText.length;
      if (slice.blockIndex == annotation.blockIndex &&
          slice.blockIndex == annotation.resolvedEndBlockIndex) {
        return mapping.toDisplay(
          Annotation(
            id: annotation.id,
            docId: annotation.docId,
            createdAt: annotation.createdAt,
            spineIndex: annotation.spineIndex,
            blockIndex: annotation.blockIndex,
            startOffset: annotation.startOffset,
            endOffset: annotation.resolvedEndBlockOffset,
            text: '',
          ),
        );
      }
      if (slice.blockIndex == annotation.blockIndex) {
        if (annotation.startOffset >= length) return null;
        return mapping.toDisplay(
          Annotation(
            id: annotation.id,
            docId: annotation.docId,
            createdAt: annotation.createdAt,
            spineIndex: annotation.spineIndex,
            blockIndex: annotation.blockIndex,
            startOffset: annotation.startOffset,
            endOffset: length,
            text: '',
          ),
        );
      }
      if (slice.blockIndex == annotation.resolvedEndBlockIndex) {
        final end = annotation.resolvedEndBlockOffset.clamp(0, length);
        if (end <= 0) return null;
        return mapping.toDisplay(
          Annotation(
            id: annotation.id,
            docId: annotation.docId,
            createdAt: annotation.createdAt,
            spineIndex: annotation.spineIndex,
            blockIndex: annotation.blockIndex,
            startOffset: 0,
            endOffset: end,
            text: '',
          ),
        );
      }
      // Middle block: full extent.
      if (length <= 0) return null;
      return mapping.toDisplay(
        Annotation(
          id: annotation.id,
          docId: annotation.docId,
          createdAt: annotation.createdAt,
          spineIndex: annotation.spineIndex,
          blockIndex: annotation.blockIndex,
          startOffset: 0,
          endOffset: length,
          text: '',
        ),
      );
    }

    try {
      return [
        for (final annotation in widget.annotations)
          if (displayFor(annotation) case final range?)
            for (final box in painter.getBoxesForSelection(range))
              Positioned.fromRect(
                rect: box.toRect(),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => widget.onOpenAnnotation?.call(annotation),
                ),
              ),
      ];
    } finally {
      painter.dispose();
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
            imageSize: widget.imageSize,
          );
          return OverlayPortal(
            controller: _overlay,
            overlayChildBuilder: (context) =>
                _selectionOverlay(context, constraints.maxWidth),
            child: ClipRect(
              key: _surfaceKey,
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
        child: Container(height: 1, color: Colors.black),
      );
    }
    if (block.type == BlockType.image) {
      return Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
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
        ),
      );
    }
    if (block.hasSplitLayout) {
      return Semantics(
        label: block.plainText,
        child: CustomPaint(painter: _SplitHeadingPainter(block, settings)),
      );
    }
    return Semantics(
      label: block.plainText,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp:
            widget.onOpenLink != null &&
                block.runs.any((run) => run.href?.isNotEmpty == true)
            ? (details) {
                final href = TextBlockLayout.linkAtOffset(
                  block,
                  settings,
                  width,
                  details.localPosition,
                );
                if (href != null) {
                  unawaited(widget.onOpenLink!(href));
                } else {
                  TapZoneLayer.dispatchMiss(context, details.globalPosition);
                }
              }
            : null,
        onLongPressStart:
            widget.onDefineWord == null && widget.onAnnotate == null
            ? null
            : (details) => _selectWord(details.localPosition, width),
        child: Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(
              painter: _TextBlockPainter(
                block,
                settings,
                _selection,
                widget.annotations,
                slice.blockIndex,
              ),
            ),
            if (widget.onOpenAnnotation != null &&
                widget.annotations.isNotEmpty)
              ..._annotationTargets(width),
          ],
        ),
      ),
    );
  }
}

class _SplitHeadingPainter extends CustomPainter {
  final ContentBlock block;
  final ReaderSettings settings;

  _SplitHeadingPainter(this.block, this.settings);

  @override
  void paint(Canvas canvas, Size size) {
    final painters = TextBlockLayout.createSplitPainters(
      block,
      settings,
      size.width,
    );
    painters.leading.paint(canvas, Offset(0, painters.leadingTop));
    painters.trailing.paint(
      canvas,
      Offset(size.width - painters.trailing.width, painters.trailingTop),
    );
    painters.dispose();
  }

  @override
  bool shouldRepaint(covariant _SplitHeadingPainter oldDelegate) =>
      oldDelegate.block != block || oldDelegate.settings != settings;
}

class _TextBlockPainter extends CustomPainter {
  final ContentBlock block;
  final ReaderSettings settings;
  final TextSelection? selection;
  final List<Annotation> annotations;
  final int sliceBlockIndex;
  _TextBlockPainter(
    this.block,
    this.settings,
    this.selection,
    this.annotations,
    this.sliceBlockIndex,
  );

  TextSelection? _displayFor(Annotation annotation, AnnotationTextMapping mapping) {
    if (!annotation.isMultiBlock) return mapping.toDisplay(annotation);
    final length = block.plainText.length;
    Annotation probe(int start, int end) => Annotation(
      id: annotation.id,
      docId: annotation.docId,
      createdAt: annotation.createdAt,
      spineIndex: annotation.spineIndex,
      blockIndex: annotation.blockIndex,
      startOffset: start,
      endOffset: end,
      text: '',
    );
    if (sliceBlockIndex == annotation.blockIndex &&
        sliceBlockIndex == annotation.resolvedEndBlockIndex) {
      return mapping.toDisplay(
        probe(annotation.startOffset, annotation.resolvedEndBlockOffset),
      );
    }
    if (sliceBlockIndex == annotation.blockIndex) {
      if (annotation.startOffset >= length) return null;
      return mapping.toDisplay(probe(annotation.startOffset, length));
    }
    if (sliceBlockIndex == annotation.resolvedEndBlockIndex) {
      final end = annotation.resolvedEndBlockOffset.clamp(0, length);
      if (end <= 0) return null;
      return mapping.toDisplay(probe(0, end));
    }
    if (length <= 0) return null;
    return mapping.toDisplay(probe(0, length));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final painter = TextBlockLayout.createPainter(block, settings, size.width);
    final mapping = annotations.isEmpty
        ? null
        : AnnotationTextMapping(block, settings);
    final underline = Paint()
      ..color = Colors.black
      ..strokeWidth = 1.5;
    for (final annotation in annotations) {
      final range = _displayFor(annotation, mapping!);
      if (range == null) continue;
      for (final box in painter.getBoxesForSelection(range)) {
        canvas.drawLine(
          Offset(box.left, box.bottom),
          Offset(box.right, box.bottom),
          underline,
        );
      }
    }
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
      oldDelegate.selection != selection ||
      oldDelegate.annotations != annotations ||
      oldDelegate.sliceBlockIndex != sliceBlockIndex;
}

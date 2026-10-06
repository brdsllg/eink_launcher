import 'dart:ui';

import 'parsed_book.dart';

/// Text anchors use page.start.spineIndex and slice.blockIndex in TextPageView.
/// Offsets are ordered boundaries in the block's original plain text, excluding
/// decorative indentation/list prefixes and generated hyphenation characters.
/// PDF anchors additionally store a page index and normalized text-layer boxes.
class Annotation {
  final String id;
  final String docId;
  final DateTime createdAt;
  final int spineIndex;
  final int blockIndex;
  final String? documentPath;
  final String? blockId;
  final int startOffset;
  final int endOffset;
  final String text;
  final String? note;
  final int? pdfPageIndex;
  final List<Rect> pdfRects;

  /// Multi-paragraph range: when [endBlockIndex] is set, the annotation spans
  /// from ([blockIndex], [startOffset]) through ([endBlockIndex],
  /// [endBlockOffset]) within the same chapter/document. Null means single.
  final int? endBlockIndex;
  final String? endBlockId;
  final String? endDocumentPath;
  final int? endBlockOffset;

  const Annotation({
    required this.id,
    required this.docId,
    required this.createdAt,
    required this.spineIndex,
    required this.blockIndex,
    this.documentPath,
    this.blockId,
    required this.startOffset,
    required this.endOffset,
    required this.text,
    this.note,
    this.pdfPageIndex,
    this.pdfRects = const [],
    this.endBlockIndex,
    this.endBlockId,
    this.endDocumentPath,
    this.endBlockOffset,
  });

  bool get isMultiBlock =>
      endBlockIndex != null && endBlockIndex != blockIndex;

  int get resolvedEndBlockIndex => endBlockIndex ?? blockIndex;
  int get resolvedEndBlockOffset => endBlockOffset ?? endOffset;

  bool matchesBlock(ParsedSpineItem chapter, int chapterIndex, int index) {
    if (documentPath != null
        ? documentPath != chapter.href
        : spineIndex != chapterIndex) {
      return false;
    }
    if (!isMultiBlock) {
      final block = chapter.blocks[index];
      if (blockId != null ? blockId != block.id : blockIndex != index) {
        return false;
      }
      return startOffset >= 0 &&
          endOffset > startOffset &&
          endOffset <= block.plainText.length &&
          block.plainText.substring(startOffset, endOffset) == text;
    }
    // Multi-block: match any block index in the inclusive range.
    final start = blockIndex;
    final end = resolvedEndBlockIndex;
    final low = start <= end ? start : end;
    final high = start <= end ? end : start;
    if (index < low || index > high) return false;
    if (index >= chapter.blocks.length) return false;
    // Identity check via block ids when available.
    if (blockId != null || endBlockId != null) {
      final block = chapter.blocks[index];
      final startOk = index == blockIndex
          ? (blockId == null || blockId == block.id)
          : true;
      final endOk = index == resolvedEndBlockIndex
          ? (endBlockId == null || endBlockId == block.id)
          : true;
      if (!startOk || !endOk) return false;
    }
    return true;
  }

  /// Source range of this annotation within the given block of its chapter.
  /// Returns null when the block is outside the annotation or text mismatches
  /// (single-block legacy check). Middle blocks return their full extent.
  RangeInBlock? rangeForBlock(
    ParsedSpineItem chapter,
    int index,
  ) {
    if (!matchesBlock(chapter, spineIndex, index)) return null;
    final block = chapter.blocks[index];
    final length = block.plainText.length;
    if (!isMultiBlock) {
      if (endOffset > length) return null;
      if (block.plainText.substring(startOffset, endOffset) != text) {
        // Legacy single-block text check; allow stored multi-text containing it.
        if (!text.contains(block.plainText.substring(startOffset, endOffset))) {
          return null;
        }
      }
      return RangeInBlock(startOffset, endOffset);
    }
    if (index == blockIndex && index == resolvedEndBlockIndex) {
      return RangeInBlock(startOffset, resolvedEndBlockOffset.clamp(0, length));
    }
    if (index == blockIndex) {
      return RangeInBlock(startOffset.clamp(0, length), length);
    }
    if (index == resolvedEndBlockIndex) {
      return RangeInBlock(0, resolvedEndBlockOffset.clamp(0, length));
    }
    return RangeInBlock(0, length);
  }

  static String generateId() =>
      DateTime.now().microsecondsSinceEpoch.toString();

  Annotation withNote(String note) => Annotation(
    id: id,
    docId: docId,
    createdAt: createdAt,
    spineIndex: spineIndex,
    blockIndex: blockIndex,
    documentPath: documentPath,
    blockId: blockId,
    startOffset: startOffset,
    endOffset: endOffset,
    text: text,
    note: note,
    pdfPageIndex: pdfPageIndex,
    pdfRects: pdfRects,
    endBlockIndex: endBlockIndex,
    endBlockId: endBlockId,
    endDocumentPath: endDocumentPath,
    endBlockOffset: endBlockOffset,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'docId': docId,
    'createdAt': createdAt.toIso8601String(),
    'spineIndex': spineIndex,
    'blockIndex': blockIndex,
    if (documentPath != null) 'documentPath': documentPath,
    if (blockId != null) 'blockId': blockId,
    'startOffset': startOffset,
    'endOffset': endOffset,
    if (endBlockIndex != null) 'endBlockIndex': endBlockIndex,
    if (endBlockId != null) 'endBlockId': endBlockId,
    if (endDocumentPath != null) 'endDocumentPath': endDocumentPath,
    if (endBlockOffset != null) 'endBlockOffset': endBlockOffset,
    'text': text,
    if (note != null) 'note': note,
    if (pdfPageIndex != null) 'pdfPageIndex': pdfPageIndex,
    if (pdfRects.isNotEmpty)
      'pdfRects': [
        for (final rect in pdfRects)
          [rect.left, rect.top, rect.right, rect.bottom],
      ],
  };

  factory Annotation.fromJson(Map<String, dynamic> json) => Annotation(
    id: json['id'] as String,
    docId: json['docId'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    spineIndex: json['spineIndex'] as int,
    blockIndex: json['blockIndex'] as int,
    documentPath: json['documentPath'] as String?,
    blockId: json['blockId'] as String?,
    startOffset: json['startOffset'] as int,
    endOffset: json['endOffset'] as int,
    endBlockIndex: json['endBlockIndex'] as int?,
    endBlockId: json['endBlockId'] as String?,
    endDocumentPath: json['endDocumentPath'] as String?,
    endBlockOffset: json['endBlockOffset'] as int?,
    text: json['text'] as String,
    note: json['note'] as String?,
    pdfPageIndex: json['pdfPageIndex'] as int?,
    pdfRects:
        (json['pdfRects'] as List<dynamic>?)
            ?.map((value) {
              final coordinates = value as List<dynamic>;
              return Rect.fromLTRB(
                (coordinates[0] as num).toDouble(),
                (coordinates[1] as num).toDouble(),
                (coordinates[2] as num).toDouble(),
                (coordinates[3] as num).toDouble(),
              );
            })
            .toList(growable: false) ??
        const [],
  );
}

/// Source character range within one block for painting and hit-testing.
class RangeInBlock {
  final int start;
  final int end;

  const RangeInBlock(this.start, this.end);
}

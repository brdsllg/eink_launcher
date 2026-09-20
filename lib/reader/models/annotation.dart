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
  });

  bool matchesBlock(ParsedSpineItem chapter, int chapterIndex, int index) {
    if (documentPath != null
        ? documentPath != chapter.href
        : spineIndex != chapterIndex) {
      return false;
    }
    final block = chapter.blocks[index];
    if (blockId != null ? blockId != block.id : blockIndex != index) {
      return false;
    }
    return startOffset >= 0 &&
        endOffset > startOffset &&
        endOffset <= block.plainText.length &&
        block.plainText.substring(startOffset, endOffset) == text;
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

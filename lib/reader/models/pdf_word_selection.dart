import 'dart:ui';

class PdfWordSelection {
  final String word;
  final List<Rect> boxes;
  final int? pageIndex;
  final int? startOffset;
  final int? endOffset;

  /// Boxes in normalized, rotated PDF page coordinates. Unlike [boxes], these
  /// remain unchanged as a selection is transformed into viewport coordinates.
  final List<Rect> sourceBoxes;

  const PdfWordSelection(
    this.word,
    this.boxes, {
    this.pageIndex,
    this.startOffset,
    this.endOffset,
    this.sourceBoxes = const [],
  });

  PdfWordSelection transform(Rect Function(Rect) map) => PdfWordSelection(
    word,
    boxes.map(map).toList(growable: false),
    pageIndex: pageIndex,
    startOffset: startOffset,
    endOffset: endOffset,
    sourceBoxes: sourceBoxes,
  );

  PdfWordSelection onPage(int page) => PdfWordSelection(
    word,
    boxes,
    pageIndex: page,
    startOffset: startOffset,
    endOffset: endOffset,
    sourceBoxes: sourceBoxes,
  );
}

/// Text and boxes have matching UTF-16 indices. Coordinates can be page,
/// normalized or viewport coordinates as long as [point] uses the same space.
PdfWordSelection? selectPdfWord(String text, List<Rect> boxes, Offset point) {
  final index = boxes.indexWhere((box) => !box.isEmpty && box.contains(point));
  if (index < 0 || index >= text.length) return null;
  final words = RegExp(
    r"[\p{L}\p{M}]+(?:(?:[\u00ad\u200b'’\-]|-\r?\n)[\p{L}\p{M}]+)*",
    unicode: true,
  );
  for (final match in words.allMatches(text)) {
    if (index < match.start || index >= match.end) continue;
    if (match.end > boxes.length) return null;
    return PdfWordSelection(
      match.group(0)!.replaceAll(RegExp('-\r?\n|[\u00ad\u200b]'), ''),
      boxes
          .sublist(match.start, match.end)
          .where((box) => !box.isEmpty)
          .toList(),
      startOffset: match.start,
      endOffset: match.end,
      sourceBoxes: boxes
          .sublist(match.start, match.end)
          .where((box) => !box.isEmpty)
          .toList(growable: false),
    );
  }
  return null;
}

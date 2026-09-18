import 'dart:ui';

class PdfWordSelection {
  final String word;
  final List<Rect> boxes;
  final int? pageIndex;
  final int? startOffset;
  final int? endOffset;
  final String? pageText;
  final List<Rect> pageBoxes;

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
    this.pageText,
    this.pageBoxes = const [],
  });

  PdfWordSelection transform(Rect Function(Rect) map) => PdfWordSelection(
    word,
    boxes.map(map).toList(growable: false),
    pageIndex: pageIndex,
    startOffset: startOffset,
    endOffset: endOffset,
    sourceBoxes: sourceBoxes,
    pageText: pageText,
    pageBoxes: pageBoxes,
  );

  PdfWordSelection onPage(int page) => PdfWordSelection(
    word,
    boxes,
    pageIndex: page,
    startOffset: startOffset,
    endOffset: endOffset,
    sourceBoxes: sourceBoxes,
    pageText: pageText,
    pageBoxes: pageBoxes,
  );

  /// Moves one selection boundary to the character nearest [point]. [point]
  /// and [pageBoxes] must both use normalized PDF page coordinates.
  PdfWordSelection? moveBoundary(Offset point, {required bool start}) {
    final text = pageText;
    final currentStart = startOffset;
    final currentEnd = endOffset;
    if (text == null ||
        currentStart == null ||
        currentEnd == null ||
        pageBoxes.length < text.length) {
      return null;
    }
    final character = nearestPdfCharacter(pageBoxes, point);
    if (character == null) return null;
    final nextStart = start
        ? character.clamp(0, currentEnd - 1).toInt()
        : currentStart;
    final nextEnd = start
        ? currentEnd
        : (character + 1).clamp(currentStart + 1, text.length).toInt();
    return pdfTextSelection(
      text,
      pageBoxes,
      nextStart,
      nextEnd,
      pageIndex: pageIndex,
    );
  }
}

PdfWordSelection pdfTextSelection(
  String text,
  List<Rect> boxes,
  int start,
  int end, {
  int? pageIndex,
}) {
  final sourceBoxes = boxes
      .sublist(start, end)
      .where((box) => !box.isEmpty)
      .toList(growable: false);
  return PdfWordSelection(
    text.substring(start, end),
    sourceBoxes,
    pageIndex: pageIndex,
    startOffset: start,
    endOffset: end,
    sourceBoxes: sourceBoxes,
    pageText: text,
    pageBoxes: boxes,
  );
}

int? nearestPdfCharacter(List<Rect> boxes, Offset point) {
  int? nearest;
  var nearestDistance = double.infinity;
  for (var index = 0; index < boxes.length; index++) {
    final box = boxes[index];
    if (box.isEmpty) continue;
    if (box.contains(point)) return index;
    final dx = point.dx < box.left
        ? box.left - point.dx
        : point.dx > box.right
        ? point.dx - box.right
        : 0.0;
    final dy = point.dy < box.top
        ? box.top - point.dy
        : point.dy > box.bottom
        ? point.dy - box.bottom
        : 0.0;
    final distance = dx * dx + dy * dy;
    if (distance < nearestDistance) {
      nearestDistance = distance;
      nearest = index;
    }
  }
  return nearest;
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
    final selection = pdfTextSelection(text, boxes, match.start, match.end);
    return PdfWordSelection(
      match.group(0)!.replaceAll(RegExp('-\r?\n|[\u00ad\u200b]'), ''),
      selection.boxes,
      startOffset: selection.startOffset,
      endOffset: selection.endOffset,
      sourceBoxes: selection.sourceBoxes,
      pageText: selection.pageText,
      pageBoxes: selection.pageBoxes,
    );
  }
  return null;
}

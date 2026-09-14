import 'package:flutter/painting.dart';

class SelectedWord {
  final String word;
  final TextSelection selection;

  const SelectedWord(this.word, this.selection);
}

/// Uses the painted text, including inserted break opportunities, so wrapped
/// and hyphenated words keep their full spelling when selected.
SelectedWord? wordAtOffset(
  TextPainter painter,
  Offset offset, {
  int prefixLength = 0,
}) {
  final text = painter.text!.toPlainText();
  final position = painter.getPositionForOffset(offset).offset;
  final words = RegExp(
    r"[\p{L}\p{M}]+(?:[\u200b\u00ad'’\-][\p{L}\p{M}]+)*",
    unicode: true,
  );
  for (final match in words.allMatches(text, prefixLength)) {
    if (position < match.start || position > match.end) continue;
    final selection = TextSelection(
      baseOffset: match.start,
      extentOffset: match.end,
    );
    // TextPainter snaps positions in margins and whitespace to nearby text.
    // Only accept a press inside the actual word's painted boxes.
    if (!painter
        .getBoxesForSelection(selection)
        .any((box) => box.toRect().contains(offset))) {
      continue;
    }
    return SelectedWord(
      match.group(0)!.replaceAll(RegExp('[\u200b\u00ad]'), ''),
      selection,
    );
  }
  return null;
}

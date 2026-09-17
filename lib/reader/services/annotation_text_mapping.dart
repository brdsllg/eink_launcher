import 'package:flutter/painting.dart';

import '../models/annotation.dart';
import '../models/content_block.dart';
import '../models/reader_settings.dart';
import 'epub_paginator_service.dart';

/// Converts between stable source anchors and the text actually painted.
class AnnotationTextMapping {
  final int prefix;
  final List<int> offsets;

  AnnotationTextMapping(ContentBlock block, ReaderSettings settings)
    : prefix = TextBlockLayout.prefixFor(block, settings).length,
      offsets = TextBlockLayout.sourceOffsetsForDisplay(block, settings);

  int sourceOffset(int displayOffset) =>
      offsets[(displayOffset - prefix).clamp(0, offsets.length - 1)];

  TextSelection toSource(TextSelection selection) => TextSelection(
    baseOffset: sourceOffset(selection.start),
    extentOffset: sourceOffset(selection.end),
  );

  TextSelection? toDisplay(Annotation annotation) {
    if (annotation.startOffset < 0 ||
        annotation.endOffset > offsets.last ||
        annotation.startOffset >= annotation.endOffset) {
      return null;
    }
    return TextSelection(
      baseOffset: prefix + offsets.lastIndexOf(annotation.startOffset),
      extentOffset: prefix + offsets.indexOf(annotation.endOffset),
    );
  }
}

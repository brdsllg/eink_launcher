import 'dart:ui';

import 'annotation.dart';

/// One persisted PDF annotation mapped into the current display coordinates.
class PdfAnnotationRegion {
  final Annotation annotation;
  final List<Rect> boxes;

  const PdfAnnotationRegion(this.annotation, this.boxes);

  PdfAnnotationRegion transform(Rect Function(Rect) map) =>
      PdfAnnotationRegion(annotation, boxes.map(map).toList(growable: false));
}

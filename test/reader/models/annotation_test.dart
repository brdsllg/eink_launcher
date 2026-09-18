import 'dart:ui';

import 'package:eink_launcher/reader/models/annotation.dart';
import 'package:eink_launcher/reader/models/book_state.dart';
import 'package:eink_launcher/reader/models/doc_ref.dart';
import 'package:eink_launcher/reader/models/reading_position.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final note in [null, '', 'A note\nשָׁלוֹם']) {
    test('annotation and book state round-trip note: $note', () {
      final annotation = Annotation(
        id: Annotation.generateId(),
        docId: 'book',
        createdAt: DateTime.utc(2026),
        spineIndex: 2,
        blockIndex: 3,
        startOffset: 4,
        endOffset: 9,
        text: 'hello',
        note: note,
      );
      expect(
        Annotation.fromJson(annotation.toJson()).toJson(),
        annotation.toJson(),
      );
      final state = BookState(
        docId: 'book',
        lastPath: '/book.txt',
        format: DocFormat.txt,
        lastRead: DateTime.utc(2026),
        position: const TextReadingPosition(
          spineIndex: 2,
          blockIndex: 3,
          charOffset: 4,
        ),
        annotations: [annotation],
      );
      expect(
        BookState.fromJson(state.toJson()).annotations.single.toJson(),
        annotation.toJson(),
      );
      expect(state.copyWith(percent: .5).annotations.single, same(annotation));
      expect(
        state.copyWith(annotations: []).toJson().containsKey('annotations'),
        isFalse,
      );
      final legacy = state.toJson()..remove('annotations');
      expect(BookState.fromJson(legacy).annotations, isEmpty);
      expect(annotation.withNote('changed').id, annotation.id);
      expect(annotation.withNote('changed').createdAt, annotation.createdAt);
    });
  }

  test('PDF annotation geometry round-trips and survives note edits', () {
    final annotation = Annotation(
      id: 'pdf-annotation',
      docId: 'pdf-book',
      createdAt: DateTime.utc(2026),
      spineIndex: 4,
      blockIndex: -1,
      startOffset: 10,
      endOffset: 15,
      text: 'hello',
      pdfPageIndex: 4,
      pdfRects: const [Rect.fromLTRB(.1, .2, .3, .4)],
    );

    final restored = Annotation.fromJson(annotation.toJson());
    expect(restored.pdfPageIndex, 4);
    expect(restored.pdfRects, annotation.pdfRects);
    expect(restored.withNote('note').pdfRects, annotation.pdfRects);
    expect(restored.withNote('note').pdfPageIndex, 4);
  });
}

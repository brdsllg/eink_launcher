import 'dart:async';

import 'package:eink_launcher/reader/models/annotation.dart';
import 'package:eink_launcher/reader/models/pdf_annotation_region.dart';
import 'package:eink_launcher/reader/models/pdf_word_selection.dart';
import 'package:eink_launcher/reader/services/pdf_document_service.dart';
import 'package:eink_launcher/reader/services/pdf_render_scheduler.dart';
import 'package:eink_launcher/reader/widgets/pdf_dictionary_region.dart';
import 'package:eink_launcher/reader/widgets/tap_zone_layer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final (rotation, point) in [
    (PdfPageRotation.none, const Offset(24 / 200, 45 / 300)),
    (PdfPageRotation.clockwise90, const Offset(255 / 300, 24 / 200)),
    (PdfPageRotation.clockwise180, const Offset(176 / 200, 255 / 300)),
    (PdfPageRotation.clockwise270, const Offset(45 / 300, 176 / 200)),
  ]) {
    test('extracts and selects text at rotation $rotation', () async {
      final doc = _Document(rotation);
      final service = PdfDocumentService(
        'fixture',
        documentOpener: (_, _) async => doc,
      );
      await service.open();
      addTearDown(service.close);
      final selected = await service.wordAt(0, point);
      expect(selected?.word, 'hello');
      expect(selected?.boxes.length, 5);
      expect(await service.wordAt(0, const Offset(.99, .99)), isNull);
    });
  }

  test(
    'empty text layers return no word and stale extraction is cancelled',
    () async {
      final doc = _Document(PdfPageRotation.none);
      final service = PdfDocumentService(
        'fixture',
        documentOpener: (_, _) async => doc,
      );
      await service.open();
      doc.page.pending = Completer<PdfPageRawText?>()..complete(null);
      expect(await service.wordAt(0, const Offset(.12, .15)), isNull);
      doc.page.pending = Completer<PdfPageRawText?>();
      final lookup = service.wordAt(0, const Offset(.12, .15));
      final assertion = expectLater(
        lookup,
        throwsA(isA<PdfRenderCancelledException>()),
      );
      await Future<void>.delayed(Duration.zero);
      await service.close();
      doc.page.pending!.complete(null);
      await assertion;
    },
  );

  test('joins line-end hyphenation and excludes punctuation', () {
    const text = 'extra-\nordinary!';
    final boxes = List.generate(
      text.length,
      (i) => Rect.fromLTWH(i * 10, 0, 8, 10),
    );
    final selection = selectPdfWord(text, boxes, boxes[8].center);
    expect(selection?.word, 'extraordinary');
    expect(selection?.startOffset, 0);
    expect(selection?.endOffset, 15);
    expect(selection?.sourceBoxes.length, 15);
    expect(selectPdfWord(text, boxes, boxes.last.center), isNull);
  });

  test('PDF selection boundaries move to exact characters', () {
    const text = 'alpha beta';
    final boxes = List.generate(
      text.length,
      (index) => index == 5 ? Rect.zero : Rect.fromLTWH(index * 10, 0, 8, 10),
    );
    final word = selectPdfWord(text, boxes, boxes[1].center)!;

    final extended = word.moveBoundary(boxes[8].center, start: false)!;
    expect(extended.word, 'alpha bet');
    expect(extended.startOffset, 0);
    expect(extended.endOffset, 9);

    final trimmed = extended.moveBoundary(boxes[2].center, start: true)!;
    expect(trimmed.word, 'pha bet');
    expect(trimmed.startOffset, 2);
    expect(trimmed.endOffset, 9);
  });

  testWidgets('PDF text-layer ranges can be adjusted, underlined and reopened', (
    tester,
  ) async {
    PdfWordSelection? annotated;
    var opened = false;
    const selection = PdfWordSelection(
      'hello',
      [Rect.fromLTWH(90, 90, 40, 20)],
      pageIndex: 2,
      startOffset: 4,
      endOffset: 9,
      sourceBoxes: [Rect.fromLTRB(.1, .2, .3, .25)],
    );
    const extendedSelection = PdfWordSelection(
      'hello world',
      [Rect.fromLTWH(90, 90, 90, 20)],
      pageIndex: 2,
      startOffset: 4,
      endOffset: 15,
      sourceBoxes: [Rect.fromLTRB(.1, .2, .5, .25)],
    );
    final annotation = Annotation(
      id: 'pdf-note',
      docId: 'pdf',
      createdAt: DateTime(2026),
      spineIndex: 2,
      blockIndex: -1,
      startOffset: 4,
      endOffset: 9,
      text: 'hello',
      pdfPageIndex: 2,
      pdfRects: [Rect.fromLTRB(.1, .2, .3, .25)],
    );

    Widget view({required int identity, bool showAnnotation = false}) =>
        MaterialApp(
          home: Scaffold(
            body: PdfDictionaryRegion(
              identity: identity,
              selectWord: (_) async => selection,
              adjustSelection: (_, start, _) async =>
                  start ? selection : extendedSelection,
              onAnnotate: (value, _) async => annotated = value,
              loadAnnotations: () async => showAnnotation
                  ? [
                      PdfAnnotationRegion(annotation, [
                        const Rect.fromLTWH(90, 90, 40, 20),
                      ]),
                    ]
                  : const [],
              onOpenAnnotation: (_) async => opened = true,
              child: const ColoredBox(color: Colors.white),
            ),
          ),
        );

    await tester.pumpWidget(view(identity: 1));
    await tester.longPressAt(const Offset(100, 100));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('selection-underline')), findsOneWidget);
    expect(find.byKey(const Key('pdf-selection-start-handle')), findsOneWidget);
    expect(find.byKey(const Key('pdf-selection-end-handle')), findsOneWidget);
    await tester.drag(
      find.byKey(const Key('pdf-selection-end-handle')),
      const Offset(60, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('selection-underline')));
    await tester.pumpAndSettle();
    expect(annotated, same(extendedSelection));

    await tester.pumpWidget(view(identity: 2, showAnnotation: true));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(100, 100));
    await tester.pumpAndSettle();
    expect(opened, isTrue);
  });

  testWidgets('PDF long press wins over tap and pan; stale lookup is ignored', (
    tester,
  ) async {
    var turns = 0;
    var defined = 0;
    var pending = Completer<PdfWordSelection?>();
    Widget view(int identity) => MaterialApp(
      home: Scaffold(
        body: TapZoneLayer(
          zoomMode: true,
          onPrevious: () => turns++,
          onNext: () => turns++,
          onMenu: () => turns++,
          child: PdfDictionaryRegion(
            identity: identity,
            selectWord: (_) => pending.future,
            defineWord: (_) async {
              defined++;
            },
            child: GestureDetector(
              onScaleStart: (_) {},
              onScaleUpdate: (_) {},
              onScaleEnd: (_) {},
              child: const ColoredBox(color: Colors.white),
            ),
          ),
        ),
      ),
    );
    await tester.pumpWidget(view(1));
    await tester.longPressAt(const Offset(100, 100));
    pending.complete(
      const PdfWordSelection('hello', [Rect.fromLTWH(90, 90, 40, 20)]),
    );
    await tester.pumpAndSettle();
    expect(defined, 1);
    expect(turns, 0);
    pending = Completer<PdfWordSelection?>();
    await tester.longPressAt(const Offset(100, 100));
    await tester.pumpWidget(view(2));
    pending.complete(const PdfWordSelection('hello', []));
    await tester.pumpAndSettle();
    expect(defined, 1);
    await tester.tapAt(const Offset(100, 100));
    expect(turns, 1);
  });
}

class _Document implements PdfDocument {
  late final _Page page = _Page(this, rotation);
  final PdfPageRotation rotation;
  _Document(this.rotation);
  @override
  List<PdfPage> get pages => [page];
  @override
  Future<void> dispose() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Page implements PdfPage {
  @override
  final PdfDocument document;
  @override
  final PdfPageRotation rotation;
  Completer<PdfPageRawText?>? pending;
  _Page(this.document, this.rotation);
  @override
  double get width => rotation.index.isOdd ? 300 : 200;
  @override
  double get height => rotation.index.isOdd ? 200 : 300;
  @override
  Future<PdfPageRawText?> loadText() async => pending != null
      ? pending!.future
      : PdfPageRawText(
          'hello',
          List.generate(5, (i) => PdfRect(20 + i * 8, 260, 28 + i * 8, 250)),
        );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

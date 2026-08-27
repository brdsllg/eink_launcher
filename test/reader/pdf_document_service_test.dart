import 'dart:io';
import 'dart:typed_data';

import 'package:eink_launcher/reader/models/reading_position.dart';
import 'package:eink_launcher/reader/services/pdf_document_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'opens, renders, loads outline, and closes through the document API',
    () async {
      final document = _FakePdfDocument();
      final service = PdfDocumentService(
        '/books/smoke.pdf',
        documentOpener: (path, passwordProvider) async {
          expect(path, '/books/smoke.pdf');
          return document;
        },
      );

      await service.open();
      expect(service.isOpen, isTrue);
      expect(service.pageCount, 1);
      expect(service.pageInfo(0).width, 200);
      expect(service.pageInfo(0).height, 300);

      final outline = await service.loadOutline();
      expect(outline.single.title, 'Chapter 1');
      expect(outline.single.position, const PdfReadingPosition(pageIndex: 0));

      final image = await service.renderPage(
        pageIndex: 0,
        pixelWidth: 100,
        pixelHeight: 150,
      );
      expect(image.width, 100);
      expect(image.height, 150);
      image.dispose();

      await service.close();
      expect(service.isOpen, isFalse);
      expect(document.wasDisposed, isTrue);
    },
  );

  test('caps render dimensions while preserving aspect ratio', () {
    expect(
      PdfDocumentService.constrainedRenderSize(4000, 2000, maxDimension: 1000),
      (width: 1000, height: 500),
    );
  });

  test(
    'native PDFium smoke: opens a real file and renders page zero',
    () async {
      await pdfrxInitialize(tmpPath: Directory.systemTemp.path);
      final fixturePath = Platform.environment['PDF_SMOKE_FILE']!;
      final service = PdfDocumentService(fixturePath);
      addTearDown(service.close);

      await service.open();
      expect(service.pageCount, greaterThan(0));
      final info = service.pageInfo(0);
      final image = await service.renderPage(
        pageIndex: 0,
        pixelWidth: 200,
        pixelHeight: (200 * info.height / info.width).round(),
      );
      expect(image.width, greaterThan(0));
      expect(image.height, greaterThan(0));
      image.dispose();
    },
    skip:
        Platform.environment['PDFIUM_PATH'] == null ||
            Platform.environment['PDF_SMOKE_FILE'] == null
        ? 'Set PDFIUM_PATH and PDF_SMOKE_FILE to run the native smoke test.'
        : false,
  );
}

class _FakePdfDocument implements PdfDocument {
  late final List<PdfPage> _pages = [_FakePdfPage(this)];
  bool wasDisposed = false;

  @override
  List<PdfPage> get pages => _pages;

  @override
  Future<List<PdfOutlineNode>> loadOutline() async => const [
    PdfOutlineNode(
      title: 'Chapter 1',
      dest: PdfDest(1, PdfDestCommand.fit, null),
      children: [],
    ),
  ];

  @override
  Future<void> dispose() async {
    wasDisposed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePdfPage implements PdfPage {
  @override
  final PdfDocument document;

  _FakePdfPage(this.document);

  @override
  int get pageNumber => 1;

  @override
  double get width => 200;

  @override
  double get height => 300;

  @override
  PdfPageRotation get rotation => PdfPageRotation.none;

  @override
  bool get isLoaded => true;

  @override
  Future<PdfImage?> render({
    int x = 0,
    int y = 0,
    int? width,
    int? height,
    double? fullWidth,
    double? fullHeight,
    int? backgroundColor,
    PdfPageRotation? rotationOverride,
    PdfAnnotationRenderingMode annotationRenderingMode =
        PdfAnnotationRenderingMode.annotationAndForms,
    int flags = PdfPageRenderFlags.none,
    PdfPageRenderCancellationToken? cancellationToken,
  }) async {
    final outputWidth = width ?? fullWidth?.round() ?? this.width.round();
    final outputHeight = height ?? fullHeight?.round() ?? this.height.round();
    final pixels = Uint8List(outputWidth * outputHeight * 4);
    for (var offset = 0; offset < pixels.length; offset += 4) {
      pixels[offset] = 255;
      pixels[offset + 1] = 255;
      pixels[offset + 2] = 255;
      pixels[offset + 3] = 255;
    }
    return PdfImage.createFromBgraData(
      pixels,
      width: outputWidth,
      height: outputHeight,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

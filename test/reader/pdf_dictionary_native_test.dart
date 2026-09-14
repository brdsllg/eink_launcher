import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:eink_launcher/reader/controllers/pdf_reader_session.dart';
import 'package:eink_launcher/reader/models/doc_ref.dart';
import 'package:eink_launcher/reader/models/reader_settings.dart';
import 'package:eink_launcher/reader/models/reading_position.dart';
import 'package:eink_launcher/reader/models/toc_entry.dart';
import 'package:eink_launcher/reader/services/book_store_service.dart';
import 'package:eink_launcher/reader/services/page_bitmap_cache.dart';
import 'package:eink_launcher/reader/services/pdf_crop_service.dart';
import 'package:eink_launcher/reader/services/pdf_render_scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'real PDF text selection in fit height, sliced width and cropped continuous layout',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'dictionary-native-',
      );
      final file = File('${directory.path}/words.pdf');
      await file.writeAsBytes(ascii.encode(_pdf()));
      Pdfrx.cacheDirectoryPath = directory.path;
      await BookStoreService.instance.init(
        customFile: File('${directory.path}/library.json'),
      );
      final session = PdfReaderSession(
        doc: DocRef(
          id: 'dictionary-test',
          path: file.path,
          format: DocFormat.pdf,
          title: 'Words',
          fileSize: await file.length(),
        ),
        bitmapCache: PageBitmapCache(maxBytes: 1024 * 1024),
        cropService: _Crop(),
      );
      try {
        await session.open();
        expect(session.isReady, isTrue, reason: session.error);
        await session.applySettings(
          session.settings.copyWith(
            autoCrop: false,
            fitMode: PdfFitMode.fitHeight,
          ),
        );
        final selected = await session.wordAtFitOffset(
          const Offset(97.333333, 61.333333),
          const Size(400, 400),
          const Size(200, 300),
        );
        expect(selected?.word, 'hello');
        expect(
          await session.wordAtFitOffset(
            const Offset(5, 5),
            const Size(400, 400),
            const Size(200, 300),
          ),
          isNull,
        );

        await session.applySettings(
          session.settings.copyWith(fitMode: PdfFitMode.fitWidth),
        );
        await session.goToToc(
          const TocEntry(
            title: 'Lower slice',
            position: PdfReadingPosition(pageIndex: 0, withinPage: .6),
          ),
        );
        final lower = await session.wordAtFitOffset(
          const Offset(23, 35),
          const Size(200, 100),
          const Size(200, 100),
        );
        expect(lower?.word, 'world');

        await session.applySettings(
          session.settings.copyWith(
            autoCrop: true,
            fitMode: PdfFitMode.fitHeight,
          ),
        );
        final cropped = await session.wordAtFitOffset(
          const Offset(85.925926, 45.925926),
          const Size(400, 400),
          const Size(180, 270),
        );
        expect(cropped?.word, 'hello');

        await session.applySettings(
          session.settings.copyWith(fitMode: PdfFitMode.zoom),
        );
        final layout = await session.continuousLayoutForViewport(
          const Size(400, 400),
        );
        final continuous = await session.wordAtContinuousOffset(
          const Offset(28.888889, 68.888889),
          layout,
        );
        expect(continuous?.word, 'hello');
        expect(
          await session.wordAtContinuousOffset(const Offset(-1, 10), layout),
          isNull,
        );
      } finally {
        session.dispose();
        await BookStoreService.instance.flush();
        BookStoreService.instance.dispose();
        await directory.delete(recursive: true);
      }
    },
    skip: Platform.environment['PDF_NATIVE_STRESS'] == '1'
        ? false
        : 'Set PDF_NATIVE_STRESS=1 to exercise PDFium.',
  );
}

class _Crop extends PdfCropService {
  static const crop = PdfCropRect(left: .05, top: .05, right: .95, bottom: .95);
  @override
  Future<PdfCropRect> detectPageCrop(
    PdfPage page, {
    int sampleWidth = 200,
    int luminanceThreshold = 240,
    int minimumInkRun = 3,
    double paddingFraction = .015,
    PdfRenderRequest? request,
  }) async => crop;
  @override
  Future<PdfCropRect> detectDocumentCrop({
    int maxSamples = 10,
    required int pageCount,
    required PdfPage Function(int) pageAt,
    int sampleWidth = 200,
    int luminanceThreshold = 240,
    int minimumInkRun = 3,
    double paddingFraction = .015,
    PdfRenderRequest? request,
  }) async => crop;
}

String _pdf() {
  const content =
      'BT /F1 12 Tf 20 250 Td (hello) Tj ET\nBT /F1 12 Tf 20 80 Td (world) Tj ET\n';
  final objects = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 300] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    '<< /Length ${content.length} >>\nstream\n${content}endstream',
  ];
  final pdf = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[0];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(pdf.length);
    pdf.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xref = pdf.length;
  pdf.write('xref\n0 ${offsets.length}\n0000000000 65535 f \n');
  for (final offset in offsets.skip(1)) {
    pdf.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  pdf.write(
    'trailer\n<< /Size ${offsets.length} /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n',
  );
  return pdf.toString();
}

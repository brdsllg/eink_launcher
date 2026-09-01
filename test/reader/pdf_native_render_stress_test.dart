import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:eink_launcher/reader/services/pdf_crop_service.dart';
import 'package:eink_launcher/reader/services/pdf_document_service.dart';
import 'package:eink_launcher/reader/services/pdf_render_scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

/// Optional host-native verification, separate from deterministic fake tests.
/// Run with PDF_NATIVE_STRESS=1 and the platform PDFium native asset available.
/// This deliberately generates its own PDF and never needs a user's document.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'native PDFium renders current demand after obsolete queued work is cancelled',
    () async {
      final directory = await Directory.systemTemp.createTemp('pdf-native-');
      final file = File('${directory.path}/render-fixture.pdf');
      await file.writeAsBytes(ascii.encode(_fixturePdf()));
      Pdfrx.cacheDirectoryPath = directory.path;
      final document = PdfDocumentService(file.path);
      try {
        await document.open();
        expect(document.pageCount, 8);

        // Exercise real native render + isolate crop scanning, not white fakes.
        final crop = await PdfCropService().detectPageCrop(document.pageAt(0));
        expect(crop.width, lessThan(1));
        expect(crop.height, lessThan(1));

        final scheduler = PdfRenderScheduler.instance;
        final gate = Completer<void>();
        final blocker = scheduler.schedule(() => gate.future);
        await Future<void>.delayed(Duration.zero);
        final requests = List.generate(8, (_) => PdfRenderRequest());
        final images = <Future<ui.Image>>[];
        final cancellations = <Future<void>>[];
        for (var page = 0; page < 8; page++) {
          final image = document.renderPage(
            pageIndex: page,
            pixelWidth: 320,
            pixelHeight: 480,
            request: requests[page],
          );
          if (page < 6) {
            cancellations.add(
              expectLater(image, throwsA(isA<PdfRenderCancelledException>())),
            );
          } else {
            images.add(image);
          }
        }
        for (final request in requests.take(6)) {
          request.cancel();
        }
        gate.complete();
        await blocker;
        await Future.wait(cancellations);

        final rendered = await Future.wait(images);
        try {
          for (final image in rendered) {
            expect(image.width, 320);
            expect(image.height, 480);
            expect(await _inkPixelCount(image), greaterThan(1000));
          }
        } finally {
          for (final image in rendered) {
            image.dispose();
          }
        }

        // Detail rendering still supplies real pixels after queue cancellation.
        final detail = await document.renderPage(
          pageIndex: 7,
          pixelWidth: 640,
          pixelHeight: 960,
        );
        try {
          expect(await _inkPixelCount(detail), greaterThan(4000));
        } finally {
          detail.dispose();
        }
        expect(scheduler.pendingCount, 0);
      } finally {
        await document.close();
        await directory.delete(recursive: true);
      }
    },
    skip: Platform.environment['PDF_NATIVE_STRESS'] == '1'
        ? false
        : 'Set PDF_NATIVE_STRESS=1 to exercise the native PDFium asset.',
  );
}

Future<int> _inkPixelCount(ui.Image image) async {
  final pixels = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  var ink = 0;
  for (var offset = 0; offset < pixels.lengthInBytes; offset += 4) {
    if (pixels.getUint8(offset) < 128 && pixels.getUint8(offset + 3) > 128) {
      ink++;
    }
  }
  return ink;
}

String _fixturePdf() {
  // ASCII objects make String length exactly match byte offsets in the xref.
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Count 8 /Kids [${List.generate(8, (i) => '${3 + i * 2} 0 R').join(' ')}] >>',
  ];
  for (var page = 0; page < 8; page++) {
    objects.add(
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 300] '
      '/Resources << >> /Contents ${4 + page * 2} 0 R >>',
    );
    final content =
        '0 g\n20 ${30 + page * 10} 160 20 re f\n'
        '20 230 80 20 re f\n';
    objects.add('<< /Length ${content.length} >>\nstream\n${content}endstream');
  }
  final pdf = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[0];
  for (var object = 0; object < objects.length; object++) {
    offsets.add(pdf.length);
    pdf.write('${object + 1} 0 obj\n${objects[object]}\nendobj\n');
  }
  final xref = pdf.length;
  pdf.write('xref\n0 ${offsets.length}\n0000000000 65535 f \n');
  for (final offset in offsets.skip(1)) {
    pdf.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  pdf.write(
    'trailer\n<< /Size ${offsets.length} /Root 1 0 R >>\n'
    'startxref\n$xref\n%%EOF\n',
  );
  return pdf.toString();
}

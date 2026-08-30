import 'dart:io';
import 'dart:typed_data';

import 'package:eink_launcher/reader/controllers/pdf_reader_session.dart';
import 'package:eink_launcher/reader/models/doc_ref.dart';
import 'package:eink_launcher/reader/models/reader_settings.dart';
import 'package:eink_launcher/reader/models/reading_position.dart';
import 'package:eink_launcher/reader/services/book_store_service.dart';
import 'package:eink_launcher/reader/services/pdf_crop_service.dart';
import 'package:eink_launcher/reader/services/pdf_document_service.dart';
import 'package:eink_launcher/reader/widgets/pdf_page_view.dart' as reader;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('pdf_reader_session_test_');
    await BookStoreService.instance.init(
      customFile: File('${tempDir.path}/library.json'),
    );
  });

  tearDown(() async {
    BookStoreService.instance.dispose();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  const doc = DocRef(
    id: 'doc-1',
    path: '/books/doc-1.pdf',
    format: DocFormat.pdf,
    title: 'doc-1',
    fileSize: 1024,
  );

  PdfReaderSession makeSession({
    required _FakePdfDocument fakeDoc,
    DocRef docRef = doc,
  }) {
    return PdfReaderSession(
      doc: docRef,
      documentServiceFactory: (path) =>
          PdfDocumentService(path, documentOpener: (p, pw) async => fakeDoc),
    );
  }

  test('open loads page count and defaults to the first page', () async {
    final session = makeSession(
      fakeDoc: _FakePdfDocument(pageCount: 3, pageWidth: 200, pageHeight: 300),
    );

    await session.open();

    expect(session.isReady, isTrue);
    expect(session.error, isNull);
    expect(session.pageCount, 3);
    expect(session.currentPage, 0);
    expect(session.position, const PdfReadingPosition(pageIndex: 0));
  });

  test('sets an error and stays not-ready when opening fails', () async {
    final session = PdfReaderSession(
      doc: doc,
      documentServiceFactory: (path) => PdfDocumentService(
        path,
        documentOpener: (p, pw) async => throw StateError('boom'),
      ),
    );

    await session.open();

    expect(session.isReady, isFalse);
    expect(session.error, contains('boom'));
  });

  test(
    'goToPage clamps to the valid range and persists the position',
    () async {
      final session = makeSession(
        fakeDoc: _FakePdfDocument(
          pageCount: 3,
          pageWidth: 200,
          pageHeight: 300,
        ),
      );
      await session.open();

      await session.goToPage(1);
      expect(session.currentPage, 1);

      await session.goToPage(99);
      expect(session.currentPage, 2); // clamped to pageCount - 1

      await session.goToPage(-5);
      expect(session.currentPage, 0);

      final saved = BookStoreService.instance.getBookState('doc-1');
      expect(saved, isNotNull);
      expect((saved!.position as PdfReadingPosition).pageIndex, 0);
    },
  );

  test('percent reflects the current page fraction', () async {
    final session = makeSession(
      fakeDoc: _FakePdfDocument(pageCount: 4, pageWidth: 200, pageHeight: 300),
    );
    await session.open();

    await session.goToPage(2);
    expect(session.percent, closeTo(2 / 4, 0.0001));
  });

  test('fit-width nextPage/prevPage step through sub-screens before crossing pages', () async {
    final session = makeSession(
      fakeDoc: _FakePdfDocument(
        pageCount: 3,
        pageWidth: 200,
        pageHeight: 1600, // tall page => several fit-width sub-screens
      ),
    );
    await session.open();
    await session.applySettings(
      session.settings.copyWith(fitMode: PdfFitMode.fitWidth),
    );
    session.updateViewport(const Size(400, 800));

    final seenWithinPage = <double>[0.0];
    for (var i = 0; i < 4; i++) {
      await session.nextPage();
      seenWithinPage.add((session.position as PdfReadingPosition).withinPage);
    }

    // All four taps stay on page 0, walking through strictly increasing
    // sub-screen fractions before the page boundary is reached.
    expect(session.currentPage, 0);
    for (var i = 1; i < seenWithinPage.length; i++) {
      expect(seenWithinPage[i], greaterThan(seenWithinPage[i - 1]));
    }

    await session.nextPage(); // crosses onto page 1
    expect(session.currentPage, 1);
    expect((session.position as PdfReadingPosition).withinPage, 0.0);

    await session.prevPage(); // lands on page 0's last sub-screen
    expect(session.currentPage, 0);
    expect(
      (session.position as PdfReadingPosition).withinPage,
      greaterThan(0.0),
    );
  });

  test(
    'suspend keeps position and page count; resume restores readiness',
    () async {
      final session = makeSession(
        fakeDoc: _FakePdfDocument(
          pageCount: 3,
          pageWidth: 200,
          pageHeight: 300,
        ),
      );
      await session.open();
      await session.goToPage(2);

      session.suspend();
      expect(session.isSuspended, isTrue);
      expect(session.isReady, isFalse);
      expect(session.pageCount, 3);
      expect(session.currentPage, 2);

      await session.resume();
      expect(session.isSuspended, isFalse);
      expect(session.isReady, isTrue);
      expect(session.currentPage, 2);
    },
  );

  test('applySettings persists a per-document override', () async {
    final session = makeSession(
      fakeDoc: _FakePdfDocument(pageCount: 2, pageWidth: 200, pageHeight: 300),
    );
    await session.open();

    await session.applySettings(
      session.settings.copyWith(fitMode: PdfFitMode.fitWidth),
    );

    expect(session.settings.fitMode, PdfFitMode.fitWidth);
    final saved = BookStoreService.instance.getBookState('doc-1');
    expect(saved?.settingsOverride?.fitMode, PdfFitMode.fitWidth);
  });

  test('renderCurrentView caches identical requests and re-renders on viewport change', () async {
    final fakeDoc = _FakePdfDocument(
      pageCount: 2,
      pageWidth: 200,
      pageHeight: 300,
    );
    final session = makeSession(fakeDoc: fakeDoc);
    await session.open();

    final first = await session.renderCurrentView(const Size(200, 300));
    // One render for auto-crop detection, one for the actual page image.
    expect(fakeDoc.renderCallCount, 2);
    expect(first.width, 200);
    expect(first.height, 300);

    final second = await session.renderCurrentView(const Size(200, 300));
    expect(
      fakeDoc.renderCallCount,
      2,
      reason: 'crop is cached and geometry is unchanged: no new render',
    );
    expect(identical(first, second), isTrue);

    final third = await session.renderCurrentView(const Size(100, 150));
    expect(
      fakeDoc.renderCallCount,
      3,
      reason: 'new viewport size means new geometry, crop stays cached',
    );
    expect(third.width, 100);
    expect(third.height, 150);
  });

  test(
    'renders at physical pixels while retaining logical viewport geometry',
    () async {
      final fakeDoc = _FakePdfDocument(
        pageCount: 2,
        pageWidth: 200,
        pageHeight: 300,
      );
      final session = makeSession(fakeDoc: fakeDoc);
      await session.open();

      final image = await session.renderCurrentView(
        const Size(200, 300),
        devicePixelRatio: 2.5,
      );

      expect(image.width, 500);
      expect(image.height, 750);
    },
  );

  test('zoom / scroll never falls back to whole-page bitmap scaling', () async {
    final session = makeSession(
      fakeDoc: _FakePdfDocument(pageCount: 2, pageWidth: 200, pageHeight: 300),
    );
    await session.open();
    await session.applySettings(
      session.settings.copyWith(fitMode: PdfFitMode.zoom),
    );

    await expectLater(
      session.renderCurrentView(const Size(200, 300)),
      throwsStateError,
    );
  });

  test('zoom re-rasterises tiles through PDFium at the requested density', () async {
    final session = makeSession(
      fakeDoc: _FakePdfDocument(pageCount: 2, pageWidth: 200, pageHeight: 300),
    );
    await session.open();
    await session.applySettings(
      session.settings.copyWith(fitMode: PdfFitMode.zoom),
    );
    final layout = await session.continuousLayoutForViewport(
      const Size(200, 300),
    );

    // Unzoomed: one tile covers the whole page at device resolution.
    final base = await session.renderContinuousTile(
      0,
      layout,
      devicePixelRatio: 2,
    );
    expect(base.width, 400);
    expect(base.height, 600);

    // Zoomed 2x: the top half of the page occupies the same screen area but
    // is rendered with twice the pixels, rather than being magnified.
    final zoomed = await session.renderContinuousTile(
      0,
      layout,
      devicePixelRatio: 2,
      renderScale: 2,
      region: const Rect.fromLTRB(0, 0, 1, 0.5),
    );
    expect(zoomed.width, 800);
    expect(zoomed.height, 600);

    // Tiles also subdivide horizontally, so a deep zoom never asks for a
    // full-width strip that the dimension cap would silently shrink.
    final quadrant = await session.renderContinuousTile(
      0,
      layout,
      devicePixelRatio: 2,
      renderScale: 4,
      region: const Rect.fromLTRB(0.5, 0.5, 1.0, 0.75),
    );
    expect(quadrant.width, 800);
    expect(quadrant.height, 600);
  });

  test(
    'continuous scroll maps offsets, dominant pages, and tap jumps',
    () async {
      final session = makeSession(
        fakeDoc: _FakePdfDocument(
          pageCount: 4,
          pageWidth: 200,
          pageHeight: 300,
        ),
      );
      await session.open();
      await session.applySettings(
        session.settings.copyWith(fitMode: PdfFitMode.zoom),
      );
      const viewport = Size(200, 300);
      final layout = await session.continuousLayoutForViewport(viewport);

      expect(layout.pageHeights, [300, 300, 300, 300]);

      // Scrolling is the user's own gesture, so it must not bump the
      // navigation epoch the view uses to decide when to snap its transform.
      final epochBeforeScroll = session.navigationEpoch;
      session.updateContinuousScrollOffset(350, layout, viewport.height);
      expect(session.navigationEpoch, epochBeforeScroll);
      final dragged = session.position as PdfReadingPosition;
      expect(dragged.pageIndex, 1);
      expect(dragged.withinPage, closeTo(1 / 6, 0.0001));
      expect(session.currentPage, 1);

      await session.nextPage();
      expect(session.navigationEpoch, greaterThan(epochBeforeScroll));
      final afterNext = session.continuousOffsetForPosition(
        layout,
        viewport.height,
      );
      expect(afterNext, closeTo(650, 0.0001));
      expect(session.currentPage, 2);

      await session.prevPage();
      expect(
        session.continuousOffsetForPosition(layout, viewport.height),
        closeTo(350, 0.0001),
      );

      // At 2x zoom only half the base canvas height is visible, so tap
      // navigation advances by that transformed viewport rather than by a
      // fixed page or the Fit Width overlap preference.
      session.updateContinuousScrollOffset(350, layout, 150);
      await session.nextPage();
      expect(
        session.continuousOffsetForPosition(layout, 150),
        closeTo(500, 0.0001),
      );
      expect(
        BookStoreService.instance.getBookState('doc-1')?.uniformPdfCrop,
        PdfCropRect.fullPage.toList(),
      );
    },
  );

  testWidgets('zoom / scroll is continuous, zoomable, and has momentum', (
    tester,
  ) async {
    final session = makeSession(
      fakeDoc: _FakePdfDocument(pageCount: 0, pageWidth: 200, pageHeight: 300),
    );
    await session.open();
    await session.applySettings(
      session.settings.copyWith(fitMode: PdfFitMode.zoom),
    );
    await session.continuousLayoutForViewport(const Size(200, 300));

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 200,
            height: 300,
            child: reader.PdfPageView(session: session),
          ),
        ),
      ),
    );
    await tester.pump();

    var viewer = tester.widget<InteractiveViewer>(
      find.byKey(const Key('continuous-pdf-viewer')),
    );
    expect(viewer.scaleEnabled, isTrue);
    expect(viewer.panEnabled, isTrue);
    expect(viewer.maxScale, 5);
    expect(viewer.onInteractionEnd, isNotNull);

    // Momentum: friction must be lower than Flutter's 0.0000135 default,
    // otherwise a fling decays inside a single e-ink refresh.
    expect(viewer.interactionEndFrictionCoefficient, lessThan(0.0000135));

    // Zooming out past the page is on by default, and needs BOTH a sub-1
    // minScale and a boundary margin: InteractiveViewer independently floors
    // the scale at viewport.width / boundaryRect.width.
    expect(viewer.minScale, lessThan(1.0));
    expect(viewer.boundaryMargin.horizontal, greaterThan(0));

    await session.applySettings(
      session.settings.copyWith(allowZoomOutBeyondFit: false),
    );
    await tester.pump();
    viewer = tester.widget<InteractiveViewer>(
      find.byKey(const Key('continuous-pdf-viewer')),
    );
    expect(viewer.minScale, 1.0);
    expect(viewer.boundaryMargin, EdgeInsets.zero);

    await tester.pumpWidget(const SizedBox.shrink());
    session.dispose();
    BookStoreService.instance.dispose();
  });
}

class _FakePdfDocument implements PdfDocument {
  _FakePdfDocument({
    required int pageCount,
    required double pageWidth,
    required double pageHeight,
  }) {
    _pages = List.generate(
      pageCount,
      (_) => _FakePdfPage(
        this,
        width: pageWidth,
        height: pageHeight,
        onRender: () => renderCallCount++,
      ),
    );
  }

  late final List<PdfPage> _pages;
  int renderCallCount = 0;
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
  _FakePdfPage(
    this.document, {
    required this.width,
    required this.height,
    required this.onRender,
  });

  @override
  final PdfDocument document;
  @override
  final double width;
  @override
  final double height;
  final void Function() onRender;

  @override
  int get pageNumber => 1;

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
    onRender();
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

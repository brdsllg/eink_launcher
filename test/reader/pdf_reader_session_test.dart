import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:eink_launcher/reader/controllers/pdf_reader_session.dart';
import 'package:eink_launcher/reader/models/doc_ref.dart';
import 'package:eink_launcher/reader/models/reader_settings.dart';
import 'package:eink_launcher/reader/models/reading_position.dart';
import 'package:eink_launcher/reader/services/book_store_service.dart';
import 'package:eink_launcher/reader/services/page_bitmap_cache.dart';
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
    expect(session.error, contains('Could not read this PDF'));
    expect(session.error, isNot(contains('boom')));
  });

  test('rejects PDFs with no pages and closes the invalid document', () async {
    final empty = _FakePdfDocument(
      pageCount: 0,
      pageWidth: 200,
      pageHeight: 300,
    );
    final session = makeSession(fakeDoc: empty);
    await session.open();
    expect(session.isReady, isFalse);
    expect(empty.wasDisposed, isTrue);
    session.suspend();
    expect(BookStoreService.instance.getBookState(doc.id), isNull);
    session.dispose();
  });

  test(
    'failed resume is contained and preserves the saved PDF position',
    () async {
      var fail = false;
      final session = PdfReaderSession(
        doc: doc,
        documentServiceFactory: (path) => PdfDocumentService(
          path,
          documentOpener: (_, _) async {
            if (fail) {
              throw const FileSystemException(
                'missing',
                '/books/doc-1.pdf',
                OSError('missing', 2),
              );
            }
            return _FakePdfDocument(
              pageCount: 3,
              pageWidth: 200,
              pageHeight: 300,
            );
          },
        ),
      );
      await session.open();
      await session.goToPage(2);
      session.suspend();
      fail = true;
      await session.resume();
      expect(session.error, contains('no longer available'));
      expect(session.isReady, isFalse);
      expect(session.currentPage, 2);
      fail = false;
      await session.resume();
      expect(session.error, isNull);
      expect(session.currentPage, 2);
      session.dispose();
    },
  );

  test(
    'memory pressure prevents a late PDF render from refilling the cache',
    () async {
      final gate = Completer<void>();
      final fake = _FakePdfDocument(
        pageCount: 1,
        pageWidth: 200,
        pageHeight: 300,
        renderGate: gate.future,
      );
      final cache = PageBitmapCache(maxBytes: 1024 * 1024);
      final session = PdfReaderSession(
        doc: doc,
        bitmapCache: cache,
        documentServiceFactory: (path) =>
            PdfDocumentService(path, documentOpener: (_, _) async => fake),
      );
      await session.open();
      await session.applySettings(session.settings.copyWith(autoCrop: false));
      final rendering = session.renderCurrentView(const Size(200, 300));
      final rejected = expectLater(rendering, throwsStateError);
      await Future<void>.delayed(Duration.zero);
      session.handleMemoryPressure();
      gate.complete();
      await rejected;
      expect(cache.isEmpty, isTrue);
      expect(session.isReady, isFalse);
      expect(fake.wasDisposed, isTrue);
      session.dispose();
    },
  );

  test(
    'a document finishing open after disposal is closed without publishing',
    () async {
      final gate = Completer<PdfDocument>();
      final started = Completer<void>();
      final session = PdfReaderSession(
        doc: doc,
        documentServiceFactory: (path) => PdfDocumentService(
          path,
          documentOpener: (_, _) {
            started.complete();
            return gate.future;
          },
        ),
      );
      final opening = session.open();
      await started.future;
      session.dispose();
      final fake = _FakePdfDocument(
        pageCount: 1,
        pageWidth: 200,
        pageHeight: 300,
      );
      gate.complete(fake);
      await opening;
      expect(fake.wasDisposed, isTrue);
      expect(session.isReady, isFalse);
    },
  );

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

  test('bookmarks are added, persisted across sessions, and removed', () async {
    final session = makeSession(
      fakeDoc: _FakePdfDocument(pageCount: 3, pageWidth: 200, pageHeight: 300),
    );
    await session.open();
    await session.goToPage(1);

    await session.addBookmark('Chapter 2');
    expect(session.bookmarks, hasLength(1));
    expect(session.bookmarks.single.label, 'Chapter 2');
    expect(
      session.bookmarks.single.position,
      const PdfReadingPosition(pageIndex: 1),
    );

    final saved = BookStoreService.instance.getBookState('doc-1');
    expect(saved?.bookmarks, hasLength(1));

    // A freshly created session for the same doc (simulating an app
    // restart) restores the bookmark from library.json.
    final reopened = makeSession(
      fakeDoc: _FakePdfDocument(pageCount: 3, pageWidth: 200, pageHeight: 300),
    );
    await reopened.open();
    expect(reopened.bookmarks, hasLength(1));
    expect(reopened.bookmarks.single.label, 'Chapter 2');

    await reopened.removeBookmark(reopened.bookmarks.single.id);
    expect(reopened.bookmarks, isEmpty);
    expect(BookStoreService.instance.getBookState('doc-1')?.bookmarks, isEmpty);
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

  test(
    'zoom re-rasterises tiles through PDFium at the requested density',
    () async {
      final session = makeSession(
        fakeDoc: _FakePdfDocument(
          pageCount: 2,
          pageWidth: 200,
          pageHeight: 300,
        ),
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
    },
  );

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

  testWidgets('fit-mode image remains valid when the cache is cleared', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    final cache = PageBitmapCache(maxBytes: 1024 * 1024);
    final fake = _FakePdfDocument(
      pageCount: 1,
      pageWidth: 200,
      pageHeight: 300,
    );
    final session = PdfReaderSession(
      doc: doc,
      bitmapCache: cache,
      documentServiceFactory: (path) =>
          PdfDocumentService(path, documentOpener: (_, _) async => fake),
    );
    await tester.runAsync(() async {
      await session.open();
      await session.applySettings(session.settings.copyWith(autoCrop: false));
      await session.renderCurrentView(const Size(200, 300));
    });
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
    await tester.pumpAndSettle();
    final image = tester.widget<RawImage>(find.byType(RawImage)).image!;
    cache.clear();
    // Cloning a disposed image throws; this proves the on-screen handle is
    // independent of the one released by the cache.
    image.clone().dispose();
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });

  testWidgets('a fling keeps gliding after the finger lifts', (tester) async {
    final session = makeSession(
      fakeDoc: _FakePdfDocument(pageCount: 6, pageWidth: 200, pageHeight: 300),
    );
    await session.open();
    await session.applySettings(
      session.settings.copyWith(fitMode: PdfFitMode.zoom),
    );
    const viewport = Size(200, 300);
    // Uniform crop detection uses Isolate.run, which must escape the widget
    // test's fake-async zone or its completion message is never delivered.
    final layout = (await tester.runAsync(
      () => session.continuousLayoutForViewport(viewport),
    ))!;

    // The reader shell subscribes to the session, so a rebuild can be
    // triggered mid-gesture exactly as it is in the real app. The fling must
    // survive that.
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: viewport.width,
            height: viewport.height,
            child: ListenableBuilder(
              listenable: session,
              builder: (context, _) => reader.PdfPageView(session: session),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final surface = find.byKey(const Key('continuous-pdf-surface'));
    expect(surface, findsOneWidget);

    // Drag 100 logical pixels upward, releasing fast. Without momentum the
    // offset would stop at ~100; Android's fling curve carries it well past.
    await tester.fling(surface, const Offset(0, -100), 1600);
    final offsetAtRelease = session.continuousOffsetForPosition(
      layout,
      viewport.height,
    );

    for (var frame = 0; frame < 60; frame += 1) {
      await tester.pump(const Duration(milliseconds: 33));
    }
    final offsetAfterGlide = session.continuousOffsetForPosition(
      layout,
      viewport.height,
    );

    expect(
      offsetAfterGlide,
      greaterThan(offsetAtRelease + 50),
      reason: 'the page must keep moving after the finger lifts',
    );
    expect(
      offsetAfterGlide,
      lessThanOrEqualTo(layout.maxScrollOffset(viewport.height) + 0.5),
      reason: 'momentum must still respect the end of the document',
    );

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
    Future<void>? renderGate,
  }) {
    _pages = List.generate(
      pageCount,
      (_) => _FakePdfPage(
        this,
        width: pageWidth,
        height: pageHeight,
        onRender: () => renderCallCount++,
        renderGate: renderGate,
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
    this.renderGate,
  });

  @override
  final PdfDocument document;
  @override
  final double width;
  @override
  final double height;
  final void Function() onRender;
  final Future<void>? renderGate;

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
    await renderGate;
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

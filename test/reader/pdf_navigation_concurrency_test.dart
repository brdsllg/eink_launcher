import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:eink_launcher/reader/controllers/pdf_reader_session.dart';
import 'package:eink_launcher/reader/models/doc_ref.dart';
import 'package:eink_launcher/reader/models/reader_settings.dart';
import 'package:eink_launcher/reader/models/reading_position.dart';
import 'package:eink_launcher/reader/services/book_store_service.dart';
import 'package:eink_launcher/reader/services/page_bitmap_cache.dart';
import 'package:eink_launcher/reader/services/pdf_crop_service.dart';
import 'package:eink_launcher/reader/services/pdf_document_service.dart';
import 'package:eink_launcher/reader/services/pdf_render_scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('pdf_navigation_test_');
    await BookStoreService.instance.init(
      customFile: File('${tempDir.path}/library.json'),
    );
  });

  tearDown(() async {
    BookStoreService.instance.dispose();
    await tempDir.delete(recursive: true);
  });

  Future<PdfReaderSession> openSession(
    _ControlledDocument document, {
    PdfFitMode fitMode = PdfFitMode.fitHeight,
    _GatedCropService? crops,
    PageBitmapCache? cache,
    bool disposeAtTearDown = true,
  }) async {
    final session = PdfReaderSession(
      doc: const DocRef(
        id: 'concurrent-pdf',
        path: '/books/concurrent.pdf',
        format: DocFormat.pdf,
        title: 'Concurrent PDF',
        fileSize: 1234,
      ),
      cropService: crops,
      bitmapCache: cache ?? PageBitmapCache(maxBytes: 1024 * 1024),
      documentServiceFactory: (path) =>
          PdfDocumentService(path, documentOpener: (_, _) async => document),
    );
    addTearDown(() {
      if (disposeAtTearDown) session.dispose();
      document.completeAll();
    });
    await session.open();
    await session.applySettings(
      session.settings.copyWith(
        fitMode: fitMode,
        autoCrop: crops != null,
        splitOverlap: 0,
      ),
    );
    session.updateViewport(const ui.Size(200, 300));
    return session;
  }

  group('ordered fit-width navigation', () {
    test('rapid turns preserve every tap while the first crop is pending', () async {
      final crops = _GatedCropService();
      final session = await openSession(
        _ControlledDocument(pageCount: 4),
        fitMode: PdfFitMode.fitWidth,
        crops: crops,
      );
      final turns = Future.wait(List.generate(5, (_) => session.nextPage()));
      await crops.started.future;
      expect(session.currentPage, 0);
      expect(crops.pages, [0], reason: 'the same pending crop must be shared');
      crops.release();
      await turns;

      // A 600px page in a 300px viewport has exactly two non-overlapping views.
      expect(
        session.position,
        const PdfReadingPosition(pageIndex: 2, withinPage: 0.5),
      );
      expect(crops.pages.toSet(), containsAll([0, 1, 2]));
      expect(crops.pages.where((page) => page == 0), hasLength(1));
    });

    test(
      'reversals at the first page are not incorrectly netted together',
      () async {
        final crops = _GatedCropService();
        final session = await openSession(
          _ControlledDocument(pageCount: 3),
          fitMode: PdfFitMode.fitWidth,
          crops: crops,
        );
        final turns = Future.wait([
          session.prevPage(), // Clamped at the beginning.
          session.nextPage(),
          session.nextPage(), // Page 1, first view.
          session.prevPage(), // Page 0, last view.
        ]);
        await crops.started.future;
        crops.release();
        await turns;
        expect(
          session.position,
          const PdfReadingPosition(pageIndex: 0, withinPage: 0.5),
        );
      },
    );

    test(
      'forward taps at the last sub-screen do not consume a later reversal',
      () async {
        final crops = _GatedCropService()..release();
        final session = await openSession(
          _ControlledDocument(pageCount: 2),
          fitMode: PdfFitMode.fitWidth,
          crops: crops,
        );
        await session.goToPage(1);
        final turns = Future.wait([
          session.nextPage(), // Last page, last view.
          session.nextPage(), // Clamped.
          session.nextPage(), // Clamped.
          session.prevPage(), // Last page, first view.
        ]);
        await turns;
        expect(session.position, const PdfReadingPosition(pageIndex: 1));
      },
    );

    for (final invalidation in [
      'jump',
      'settings',
      'suspend',
      'dispose',
      'exit',
    ]) {
      test(
        '$invalidation prevents an old crop from applying queued turns',
        () async {
          final crops = _GatedCropService();
          final session = await openSession(
            _ControlledDocument(pageCount: 4),
            fitMode: PdfFitMode.fitWidth,
            crops: crops,
            disposeAtTearDown: invalidation != 'dispose',
          );
          final turns = Future.wait([
            session.nextPage(),
            session.nextPage(),
            session.prevPage(),
          ]);
          await crops.started.future;
          switch (invalidation) {
            case 'jump':
              await session.goToPage(3);
            case 'settings':
              await session.applySettings(
                session.settings.copyWith(fitMode: PdfFitMode.fitHeight),
              );
            case 'suspend':
              session.suspend();
            case 'dispose':
              session.dispose();
            case 'exit':
              session.cancelPendingWork();
          }
          final expected = session.position;
          crops.release();
          await turns; // Superseded navigation is a successful no-op, not a UI error.
          expect(session.position, expected);
          if (invalidation == 'jump') {
            expect(session.position, const PdfReadingPosition(pageIndex: 3));
          }
        },
      );
    }
  });

  test(
    'foreground callers share crop and bitmap work and own independent handles',
    () async {
      final document = _ControlledDocument(pageCount: 1);
      final cache = PageBitmapCache(
        maxBytes: 1,
      ); // Exercise uncached ownership too.
      final crops = _GatedCropService();
      final session = await openSession(document, cache: cache, crops: crops);
      final rendering = Future.wait(
        List.generate(
          8,
          (_) => session.renderCurrentView(const ui.Size(200, 300)),
        ),
      );
      await crops.started.future;
      await Future<void>.delayed(Duration.zero);
      expect(crops.pages, [0]);
      crops.release();
      await document.waitForRenders(1);
      await Future<void>.delayed(Duration.zero);
      expect(document.renders, hasLength(1));
      document.renders.single.complete();
      final images = await rendering;
      expect(document.renders, hasLength(1));
      expect(cache.isEmpty, isTrue);
      images.first.dispose();
      for (final image in images.skip(1)) {
        image.clone().dispose();
        final bytes = await image.toByteData();
        expect(
          bytes!.getUint8(0),
          lessThan(255),
          reason: 'fixture is visible content',
        );
        image.dispose();
      }
    },
  );

  test(
    'cancelling one bitmap consumer preserves another consumer of the same job',
    () async {
      final document = _ControlledDocument(pageCount: 1);
      final session = await openSession(document);
      final firstRequest = PdfRenderRequest();
      final secondRequest = PdfRenderRequest();
      final first = _acceptOrCancel(
        session.renderCurrentView(
          const ui.Size(200, 300),
          request: firstRequest,
        ),
      );
      await document.waitForRenders(1);
      final second = session.renderCurrentView(
        const ui.Size(200, 300),
        request: secondRequest,
      );
      await Future<void>.delayed(Duration.zero);
      firstRequest.cancel();
      document.renders.single.complete();
      expect(await first, isFalse);
      final image = await second;
      image.clone().dispose();
      image.dispose();
      expect(document.renders, hasLength(1));
    },
  );

  test('rapid fit-height turns discard intermediate renders before native admission', () async {
    final document = _ControlledDocument(pageCount: 40);
    final session = await openSession(document);
    final results = <Future<bool>>[
      _acceptOrCancel(session.renderCurrentView(const ui.Size(200, 300))),
    ];
    await document.waitForRenders(1);
    for (var page = 1; page <= 30; page++) {
      await session.nextPage();
      results.add(
        _acceptOrCancel(session.renderCurrentView(const ui.Size(200, 300))),
      );
    }
    await Future<void>.delayed(Duration.zero);
    expect(session.currentPage, 30);
    expect(document.renders.map((render) => render.pageIndex), [0]);
    document.renders.first.complete();
    await document.waitForRenders(2);
    expect(document.renders.last.pageIndex, 30);
    document.renders.last.complete();
    final accepted = await Future.wait(results);
    expect(accepted.where((value) => value), hasLength(1));
    expect(accepted.last, isTrue);
    expect(document.maxActive, 1);
    expect(document.renders, hasLength(2));
  });

  test(
    'settings changes reject late images and render the new geometry',
    () async {
      final document = _ControlledDocument(pageCount: 1);
      final cache = PageBitmapCache(maxBytes: 1024);
      final session = await openSession(document, cache: cache);
      final stale = _acceptOrCancel(
        session.renderCurrentView(const ui.Size(200, 300)),
      );
      await document.waitForRenders(1);
      expect(document.renders.single.pixelWidth, 100);
      await session.applySettings(
        session.settings.copyWith(fitMode: PdfFitMode.fitWidth),
      );
      document.renders.single.complete();
      expect(await stale, isFalse);
      expect(cache.isEmpty, isTrue);

      final fresh = session.renderCurrentView(const ui.Size(200, 300));
      await document.waitForRenders(2);
      expect(document.renders.last.pixelWidth, 200);
      document.renders.last.complete();
      (await fresh).dispose();
      expect(cache.isEmpty, isFalse);
    },
  );

  for (final change in ['no-op', 'orientation']) {
    test(
      '$change settings preserve an in-flight fit image with unchanged geometry',
      () async {
        final document = _ControlledDocument(pageCount: 1);
        final session = await openSession(document);
        final rendering = _acceptOrCancel(
          session.renderCurrentView(const ui.Size(200, 300)),
        );
        await document.waitForRenders(1);
        await session.applySettings(
          change == 'no-op'
              ? session.settings
              : session.settings.copyWith(
                  landscape: !session.settings.landscape,
                ),
        );
        document.renders.single.complete();
        expect(await rendering, isTrue);
        expect(document.renders, hasLength(1));
      },
    );
  }

  test(
    'zoom floor settings preserve pending uniform layout and tile work',
    () async {
      final document = _ControlledDocument(pageCount: 1);
      final crops = _GatedCropService();
      final session = await openSession(
        document,
        fitMode: PdfFitMode.zoom,
        crops: crops,
      );
      final preparing = session.continuousLayoutForViewport(
        const ui.Size(200, 300),
      );
      await crops.started.future;
      await session.applySettings(
        session.settings.copyWith(allowZoomOutBeyondFit: false),
      );
      crops.release();
      final layout = await preparing;
      expect(layout.pageCount, 1);
      expect(crops.documentCalls, 1);
      final rendering = _acceptOrCancel(
        session.renderContinuousTile(0, layout),
      );
      await document.waitForRenders(1);
      await session.applySettings(
        session.settings.copyWith(allowZoomOutBeyondFit: true),
      );
      document.renders.single.complete();
      expect(await rendering, isTrue);
    },
  );

  test(
    'suspension prevents queued native work and late cache insertion',
    () async {
      final document = _ControlledDocument(pageCount: 1);
      final cache = PageBitmapCache(maxBytes: 1024);
      final session = await openSession(document, cache: cache);
      final results = <Future<bool>>[
        _acceptOrCancel(session.renderCurrentView(const ui.Size(200, 300))),
      ];
      await document.waitForRenders(1);
      for (var size = 201; size < 210; size++) {
        results.add(
          _acceptOrCancel(
            session.renderCurrentView(ui.Size(size.toDouble(), 300)),
          ),
        );
      }
      session.suspend();
      document.renders.single.complete();
      expect(await Future.wait(results), everyElement(isFalse));
      expect(document.renders, hasLength(1));
      expect(cache.isEmpty, isTrue);
      expect(session.isSuspended, isTrue);
      await session.resume();
      final fresh = session.renderCurrentView(const ui.Size(200, 300));
      await document.waitForRenders(2);
      document.renders.last.complete();
      (await fresh).dispose();
      expect(session.isReady, isTrue);
    },
  );

  test(
    'a prefetched page is reused when it becomes the foreground target',
    () async {
      final document = _ControlledDocument(pageCount: 3);
      final session = await openSession(document);
      final first = session.renderCurrentView(const ui.Size(200, 300));
      await document.waitForRenders(1);
      document.renders.first.complete();
      (await first).dispose();
      // Wait for the real idle prefetch timer, not an arbitrary sleep.
      await document.waitForRenders(2);
      expect(document.renders.last.pageIndex, 1);
      await session.nextPage();
      final foreground = session.renderCurrentView(const ui.Size(200, 300));
      await Future<void>.delayed(Duration.zero);
      document.renders.last.complete();
      (await foreground).dispose();
      expect(
        document.renders.where((render) => render.pageIndex == 1),
        hasLength(1),
      );
      expect(document.maxActive, 1);
    },
  );

  test(
    'leaving the reader cancels idle prefetch but retains reusable content',
    () async {
      final document = _ControlledDocument(pageCount: 3);
      final session = await openSession(document);
      final first = session.renderCurrentView(const ui.Size(200, 300));
      await document.waitForRenders(1);
      document.renders.first.complete();
      (await first).dispose();
      session.cancelPendingWork();
      await Future<void>.delayed(
        PdfReaderSession.prefetchDelay + const Duration(milliseconds: 20),
      );
      expect(document.renders, hasLength(1));
      expect(session.isReady, isTrue);
      (await session.renderCurrentView(const ui.Size(200, 300))).dispose();
      expect(
        document.renders,
        hasLength(1),
        reason: 'cached page survives reader exit',
      );
    },
  );
}

Future<bool> _acceptOrCancel(Future<ui.Image> rendering) async {
  try {
    (await rendering).dispose();
    return true;
  } catch (error) {
    expect(error, anyOf(isA<PdfRenderCancelledException>(), isA<StateError>()));
    return false;
  }
}

class _GatedCropService extends PdfCropService {
  final started = Completer<void>();
  final _gate = Completer<void>();
  final pages = <int>[];
  var documentCalls = 0;

  void release() {
    if (!_gate.isCompleted) _gate.complete();
  }

  @override
  Future<PdfCropRect> detectPageCrop(
    PdfPage page, {
    int sampleWidth = PdfCropService.defaultSampleWidth,
    int luminanceThreshold = 245,
    int minimumInkRun = PdfCropService.defaultMinimumInkRun,
    double paddingFraction = PdfCropService.defaultPaddingFraction,
    PdfRenderRequest? request,
  }) async {
    pages.add(page.pageNumber - 1);
    if (!started.isCompleted) started.complete();
    await _gate.future;
    request?.throwIfCancelled();
    return PdfCropRect.fullPage;
  }

  @override
  Future<PdfCropRect> detectDocumentCrop({
    required int pageCount,
    required PdfPage Function(int pageIndex) pageAt,
    int maxSamples = 10,
    PdfRenderRequest? request,
  }) async {
    documentCalls++;
    if (!started.isCompleted) started.complete();
    await _gate.future;
    request?.throwIfCancelled();
    return PdfCropRect.fullPage;
  }
}

class _ControlledDocument implements PdfDocument {
  _ControlledDocument({required int pageCount}) {
    pages = List.generate(pageCount, (index) => _ControlledPage(this, index));
  }

  @override
  late final List<PdfPage> pages;
  final renders = <_PendingRender>[];
  final _waiters = <int, List<Completer<void>>>{};
  var active = 0;
  var maxActive = 0;
  var _completeImmediately = false;

  Future<void> waitForRenders(int count) {
    if (renders.length >= count) return Future<void>.value();
    final waiter = Completer<void>();
    _waiters.putIfAbsent(count, () => []).add(waiter);
    return waiter.future.timeout(const Duration(seconds: 5));
  }

  Future<PdfImage?> render(int pageIndex, int width, int height) async {
    active++;
    if (active > maxActive) maxActive = active;
    final render = _PendingRender(pageIndex, width, height);
    renders.add(render);
    for (final waiter
        in _waiters.remove(renders.length) ?? <Completer<void>>[]) {
      waiter.complete();
    }
    if (_completeImmediately) render.complete();
    try {
      return await render.result.future;
    } finally {
      active--;
    }
  }

  void completeAll() {
    _completeImmediately = true;
    for (final render in renders) {
      render.complete();
    }
  }

  @override
  Future<List<PdfOutlineNode>> loadOutline() async => const [];

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ControlledPage implements PdfPage {
  _ControlledPage(this.document, this.index);

  @override
  final _ControlledDocument document;
  final int index;
  @override
  double get width => 200;
  @override
  double get height => 600;
  @override
  int get pageNumber => index + 1;
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
  }) => document.render(
    index,
    width ?? this.width.round(),
    height ?? this.height.round(),
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PendingRender {
  _PendingRender(this.pageIndex, this.pixelWidth, this.pixelHeight);

  final int pageIndex;
  final int pixelWidth;
  final int pixelHeight;
  final result = Completer<PdfImage?>();

  void complete() {
    if (result.isCompleted) return;
    // Distinct, non-white page content; deliberately small so scheduling tests
    // exercise ownership and ordering without allocating real screen bitmaps.
    final shade = 16 + pageIndex % 128;
    final pixels = Uint8List.fromList(
      List.generate(16, (i) => i % 4 == 3 ? 255 : shade),
    );
    result.complete(PdfImage.createFromBgraData(pixels, width: 2, height: 2));
  }
}

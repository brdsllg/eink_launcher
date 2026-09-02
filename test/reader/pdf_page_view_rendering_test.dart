import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:eink_launcher/reader/controllers/pdf_reader_session.dart';
import 'package:eink_launcher/reader/models/doc_ref.dart';
import 'package:eink_launcher/reader/models/pdf_continuous_layout.dart';
import 'package:eink_launcher/reader/models/reader_settings.dart';
import 'package:eink_launcher/reader/models/reading_position.dart';
import 'package:eink_launcher/reader/services/pdf_render_scheduler.dart';
import 'package:eink_launcher/reader/widgets/pdf_page_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<_DelayedPdfSession> mount(WidgetTester tester) async {
    final images = await tester.runAsync(() async {
      final colors = [Colors.black, Colors.blue, Colors.green, Colors.purple];
      return Future.wait(
        colors.map((color) async {
          final recorder = ui.PictureRecorder();
          Canvas(
            recorder,
          ).drawRect(const Rect.fromLTWH(0, 0, 16, 16), Paint()..color = color);
          final picture = recorder.endRecording();
          final image = await picture.toImage(16, 16);
          picture.dispose();
          return image;
        }),
      );
    });
    final session = _DelayedPdfSession(images!);
    addTearDown(() {
      session.dispose();
      for (final image in images) {
        image.dispose();
      }
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(devicePixelRatio: 4),
            child: Center(
              child: SizedBox(
                width: 400,
                height: 500,
                child: ListenableBuilder(
                  listenable: session,
                  builder: (context, _) => PdfPageView(session: session),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    _expectNonwhiteCoverage(tester);
    return session;
  }

  testWidgets(
    'zoom keeps visible pixels beyond 500ms and commits a ready batch',
    (tester) async {
      final session = await mount(tester);
      await _pinch(tester, 2);
      await tester.pump(const Duration(milliseconds: 250));
      final pending = session.liveDetails;
      expect(pending.length, greaterThan(1));
      expect(find.byKey(const ValueKey('pdf-fallback-0')), findsOneWidget);

      await tester.pump(const Duration(seconds: 2));
      _expectNonwhiteCoverage(tester);
      expect(find.byKey(const ValueKey('pdf-fallback-0')), findsOneWidget);

      final visible = pending
          .where((tile) => tile.request!.priority == PdfRenderPriority.visible)
          .toList();
      expect(visible.length, greaterThan(1));
      session.complete(visible.first);
      await tester.pump();
      expect(
        _displayedCloneOf(tester, session.images[1]),
        isFalse,
        reason: 'partial high-resolution tiles must not replace the batch',
      );
      for (final tile in visible.skip(1)) {
        session.complete(tile);
      }
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('pdf-fallback-0')), findsNothing);
      expect(_displayedCloneOf(tester, session.images[1]), isTrue);
      _expectNonwhiteCoverage(tester);
      expect(
        session.liveDetails.any(
          (tile) => tile.request!.priority == PdfRenderPriority.prefetch,
        ),
        isTrue,
        reason: 'offscreen work must not gate the handoff',
      );
      await _unmountAndFinish(tester, session);
    },
  );

  testWidgets('a second pinch preserves fallback and ignores obsolete tiles', (
    tester,
  ) async {
    final session = await mount(tester);
    await _pinch(tester, 1.6);
    await tester.pump(const Duration(milliseconds: 250));
    final firstGeneration = session.liveDetails.toList();
    expect(firstGeneration, isNotEmpty);
    await _pinch(tester, 1.5);
    await tester.pump(const Duration(milliseconds: 250));
    expect(firstGeneration.every((tile) => tile.request!.isCancelled), isTrue);
    expect(find.byKey(const ValueKey('pdf-fallback-0')), findsOneWidget);
    for (final tile in firstGeneration) {
      session.complete(tile);
    }
    await tester.pump(const Duration(seconds: 2));
    _expectNonwhiteCoverage(tester);
    expect(_displayedCloneOf(tester, session.images[1]), isFalse);
    expect(find.byKey(const ValueKey('pdf-fallback-0')), findsOneWidget);
    await _unmountAndFinish(tester, session);
  });

  testWidgets('a jump uses the target preview and cancels departed detail', (
    tester,
  ) async {
    final session = await mount(tester);
    await _pinch(tester, 2);
    await tester.pump(const Duration(milliseconds: 250));
    final abandoned = session.liveDetails.toList();
    session.jump(4);
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(abandoned.every((tile) => tile.request!.isCancelled), isTrue);
    expect(find.byKey(const ValueKey('pdf-fallback-0')), findsNothing);
    expect(find.byKey(const ValueKey('pdf-preview-4')), findsOneWidget);
    _expectNonwhiteCoverage(tester);
    for (final tile in abandoned) {
      session.complete(tile);
    }
    await tester.pump();
    expect(_displayedCloneOf(tester, session.images[1]), isFalse);
    await _unmountAndFinish(tester, session);
  });

  testWidgets(
    'explicit navigation interrupts a fling instead of losing target',
    (tester) async {
      final session = await mount(tester);
      final surface = find.byKey(const Key('continuous-pdf-surface'));
      await tester.fling(surface, const Offset(0, -120), 1600);
      await tester.pump(const Duration(milliseconds: 33));
      session.jump(4);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      expect(session.offset, closeTo(session.layout.pageTop(4), 0.5));
      _expectNonwhiteCoverage(tester);
      await _unmountAndFinish(tester, session);
    },
  );

  testWidgets('resting a finger stops momentum immediately', (tester) async {
    final session = await mount(tester);
    final surface = find.byKey(const Key('continuous-pdf-surface'));
    await tester.fling(surface, const Offset(0, -120), 2200);
    final offsetAtRelease = session.offset;
    await tester.pump(const Duration(milliseconds: 33));
    await tester.pump(const Duration(milliseconds: 33));
    expect(session.offset, greaterThan(offsetAtRelease));

    final finger = await tester.startGesture(tester.getCenter(surface));
    await tester.pump();
    final stoppedAt = session.offset;
    await tester.pump(const Duration(milliseconds: 600));
    expect(session.offset, closeTo(stoppedAt, 0.5));

    await finger.up();
    await tester.pump();
    await _unmountAndFinish(tester, session);
  });

  testWidgets('fast flings request coarse previews several screens ahead', (
    tester,
  ) async {
    final session = await mount(tester);
    session.previewRequests.clear();
    final surface = find.byKey(const Key('continuous-pdf-surface'));

    await tester.fling(surface, const Offset(0, -180), 5000);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));

    expect(session.previewRequests, isNotEmpty);
    expect(
      session.previewRequests.reduce(math.max),
      greaterThanOrEqualTo(4),
      reason: 'velocity should expand demand beyond the fixed one-screen range',
    );
    await _unmountAndFinish(tester, session);
  });

  testWidgets('an unchanged navigation target still finishes zoom refinement', (
    tester,
  ) async {
    final session = await mount(tester);
    await _pinch(tester, 2);
    await tester.pump(const Duration(milliseconds: 100));
    expect(session.liveDetails, isEmpty);
    final offset = session.offset;
    // A clamped Next tap advances the navigation epoch without moving the page.
    session.jumpToOffset(offset);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    final visible = session.liveDetails
        .where((tile) => tile.request!.priority == PdfRenderPriority.visible)
        .toList();
    expect(visible, isNotEmpty);
    expect(visible.map((tile) => tile.scale), everyElement(greaterThan(1)));
    expect(session.offset, closeTo(offset, 0.5));
    _expectNonwhiteCoverage(tester);
    for (final tile in visible) {
      session.complete(tile);
    }
    await tester.pump();
    await tester.pump();
    expect(_displayedCloneOf(tester, session.images[1]), isTrue);
    expect(find.byKey(const ValueKey('pdf-fallback-0')), findsNothing);
    await _unmountAndFinish(tester, session);
  });

  testWidgets('evicted current requests retry without showing a reader error', (
    tester,
  ) async {
    final session = await mount(tester);
    await _pinch(tester, 2);
    await tester.pump(const Duration(milliseconds: 250));
    final tile = session.liveDetails.first;
    final count = session.pending.length;
    tile.result.completeError(const PdfRenderCancelledException());
    await tester.pump();
    expect(find.textContaining('Could not render'), findsNothing);
    await tester.pump(const Duration(milliseconds: 150));
    expect(session.pending.length, greaterThan(count));
    _expectNonwhiteCoverage(tester);
    await _unmountAndFinish(tester, session);
  });
  testWidgets('a failed detail can be retried without recreating the reader', (
    tester,
  ) async {
    final session = await mount(tester);
    await _pinch(tester, 2);
    await tester.pump(const Duration(milliseconds: 250));
    final failed = session.liveDetails.first;
    final previousCount = session.pending.length;
    failed.result.completeError(StateError('test render failure'));
    await tester.pump();
    await tester.pump();
    expect(
      find.textContaining('Could not render this PDF page'),
      findsOneWidget,
    );
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(session.pending.length, greaterThan(previousCount));
    expect(find.textContaining('Could not render this PDF page'), findsNothing);
    _expectNonwhiteCoverage(tester);
    await _unmountAndFinish(tester, session);
  });
}

Future<void> _pinch(WidgetTester tester, double factor) async {
  final center = tester.getCenter(
    find.byKey(const Key('continuous-pdf-surface')),
  );
  final left = await tester.startGesture(
    center - const Offset(50, 0),
    pointer: 1,
  );
  final right = await tester.startGesture(
    center + const Offset(50, 0),
    pointer: 2,
  );
  await tester.pump();
  for (var step = 1; step <= 5; step++) {
    final distance = 50 * (1 + (factor - 1) * step / 5);
    await left.moveTo(center - Offset(distance, 0));
    await right.moveTo(center + Offset(distance, 0));
    await tester.pump(const Duration(milliseconds: 25));
  }
  await tester.pump(const Duration(milliseconds: 200));
  await left.moveTo(center - Offset(50 * factor, 0));
  await right.moveTo(center + Offset(50 * factor, 0));
  await left.up();
  await right.up();
  await tester.pump();
}

bool _displayedCloneOf(WidgetTester tester, ui.Image image) => tester
    .widgetList<RawImage>(find.byType(RawImage))
    .any((widget) => widget.image?.isCloneOf(image) ?? false);

void _expectNonwhiteCoverage(WidgetTester tester) {
  final surface = tester.getRect(
    find.byKey(const Key('continuous-pdf-surface')),
  );
  final images = find.byType(RawImage);
  final painted = <Rect>[];
  for (var i = 0; i < images.evaluate().length; i++) {
    if (tester.widget<RawImage>(images.at(i)).image != null) {
      painted.add(tester.getRect(images.at(i)));
    }
  }
  // Every fake bitmap is opaque nonwhite. Checking several points through the
  // transformed viewport catches real gaps, not merely the existence of a tile.
  for (final x in [0.05, 0.5, 0.95]) {
    for (final y in [0.05, 0.5, 0.95]) {
      final point =
          surface.topLeft + Offset(surface.width * x, surface.height * y);
      expect(
        painted.any((rect) => rect.contains(point)),
        isTrue,
        reason: 'visible document point $point lost all rendered coverage',
      );
    }
  }
}

Future<void> _unmountAndFinish(
  WidgetTester tester,
  _DelayedPdfSession session,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  for (final tile in session.pending.where(
    (tile) => !tile.result.isCompleted,
  )) {
    expect(tile.request!.isCancelled, isTrue);
    session.complete(tile);
  }
  await tester.pump();
  await tester.pump();
  for (final image in session.images) {
    expect(
      image.debugGetOpenHandleStackTraces(),
      hasLength(1),
      reason: 'completed, fallback, and stale image handles must be released',
    );
  }
}

class _PendingTile {
  final int page;
  final double scale;
  final PdfRenderRequest? request;
  final result = Completer<ui.Image>();

  _PendingTile(this.page, this.scale, this.request);
}

class _DelayedPdfSession extends PdfReaderSession {
  final List<ui.Image> images;
  final pending = <_PendingTile>[];
  final previewRequests = <int>[];
  int warmupCalls = 0;
  final layout = PdfContinuousLayout.fromPageSizes(
    pageSizes: List.filled(6, const Size(400, 600)),
    viewportWidth: 400,
  );
  double offset = 0;
  int epoch = 0;

  _DelayedPdfSession(this.images)
    : super(
        doc: const DocRef(
          id: 'delayed-widget-pdf',
          path: '/fake.pdf',
          title: 'Fake PDF',
          format: DocFormat.pdf,
          fileSize: 1,
        ),
      );

  Iterable<_PendingTile> get liveDetails => pending.where(
    (tile) => !tile.result.isCompleted && !tile.request!.isCancelled,
  );

  void complete(_PendingTile tile) {
    if (!tile.result.isCompleted) tile.result.complete(images[1].clone());
  }

  void jump(int page) => jumpToOffset(layout.pageTop(page));

  void jumpToOffset(double target) {
    offset = target;
    epoch++;
    notifyListeners();
  }

  @override
  bool get isReady => true;

  @override
  int get navigationEpoch => epoch;

  @override
  int get currentPage => layout.pageAtOffset(offset);

  @override
  ReaderSettings get settings => const ReaderSettings(fitMode: PdfFitMode.zoom);

  @override
  PdfReadingPosition get position => layout.positionForOffset(offset);

  @override
  Future<PdfContinuousLayout> continuousLayoutForViewport(
    Size viewport,
  ) async => layout;

  @override
  double continuousOffsetForPosition(
    PdfContinuousLayout layout,
    double viewportHeight,
  ) => offset;

  @override
  void updateContinuousScrollOffset(
    double offset,
    PdfContinuousLayout layout,
    double viewportHeight,
  ) {
    this.offset = offset;
  }

  @override
  Future<ui.Image> renderContinuousPreview(
    int pageIndex,
    PdfContinuousLayout layout, {
    PdfRenderRequest? request,
  }) async {
    previewRequests.add(pageIndex);
    return images[pageIndex == 4 ? 3 : 2].clone();
  }

  @override
  Future<void> warmContinuousPreviews(
    PdfContinuousLayout layout, {
    required int startPage,
    required PdfRenderRequest request,
  }) async {
    warmupCalls++;
  }

  @override
  Future<ui.Image> renderContinuousTile(
    int pageIndex,
    PdfContinuousLayout layout, {
    double devicePixelRatio = 1,
    double renderScale = 1,
    Rect region = const Rect.fromLTRB(0, 0, 1, 1),
    PdfRenderRequest? request,
  }) async {
    if (renderScale <= 1) return images[0].clone();
    final tile = _PendingTile(pageIndex, renderScale, request);
    pending.add(tile);
    return tile.result.future;
  }
}

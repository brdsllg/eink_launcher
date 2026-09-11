import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:eink_launcher/constants.dart';
import 'package:eink_launcher/reader/controllers/pdf_reader_session.dart';
import 'package:eink_launcher/reader/controllers/reader_session.dart';
import 'package:eink_launcher/reader/controllers/reader_session_registry.dart';
import 'package:eink_launcher/reader/controllers/text_reader_session.dart';
import 'package:eink_launcher/reader/models/content_block.dart';
import 'package:eink_launcher/reader/models/doc_ref.dart';
import 'package:eink_launcher/reader/models/laid_out_page.dart';
import 'package:eink_launcher/reader/models/parsed_book.dart';
import 'package:eink_launcher/reader/screens/reader_screen.dart';
import 'package:eink_launcher/reader/services/book_store_service.dart';
import 'package:eink_launcher/reader/services/pagination_cache_service.dart';
import 'package:eink_launcher/reader/services/pdf_render_scheduler.dart';
import 'package:eink_launcher/reader/widgets/reader_menu_overlay.dart';
import 'package:eink_launcher/reader/widgets/text_page_view.dart';
import 'package:eink_launcher/reader/widgets/tap_zone_layer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const alpha = DocRef(
  id: 'alpha',
  path: '/alpha.txt',
  format: DocFormat.txt,
  title: 'Alpha',
  fileSize: 1,
);
const beta = DocRef(
  id: 'beta',
  path: '/beta.txt',
  format: DocFormat.txt,
  title: 'Beta',
  fileSize: 1,
);
const gamma = DocRef(
  id: 'gamma',
  path: '/gamma.txt',
  format: DocFormat.txt,
  title: 'Gamma',
  fileSize: 1,
);
const pdf = DocRef(
  id: 'pdf',
  path: '/book.pdf',
  format: DocFormat.pdf,
  title: 'PDF book',
  fileSize: 1,
);

ParsedBook book(String title) => ParsedBook(
  title: title,
  spine: [
    ParsedSpineItem(
      id: 'chapter',
      href: '',
      blocks: [
        ContentBlock(
          type: BlockType.paragraph,
          runs: [InlineRun(text: '$title readable content.')],
        ),
      ],
    ),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late ReaderSessionRegistry registry;
  late Map<String, TextReaderSession> sessions;
  late Map<String, Completer<ParsedBook>> pending;
  late Map<String, int> loads;
  ReaderSession? pdfSession;

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('eink_launcher/battery_events'),
          (_) async => null,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
    directory = await Directory.systemTemp.createTemp('reader-tabs-ui-');
    await BookStoreService.instance.init(
      customFile: File('${directory.path}/library.json'),
    );
    sessions = {};
    pending = {};
    loads = {};
    pdfSession = null;
    registry = ReaderSessionRegistry.forTesting(
      sessionFactory: (doc) {
        if (doc.format == DocFormat.pdf) return pdfSession!;
        return sessions[doc.id] = TextReaderSession(
          doc: doc,
          paginationCache: const _NoDiskCache(),
          bookLoader: (doc, _) {
            loads.update(doc.id, (n) => n + 1, ifAbsent: () => 1);
            return pending[doc.id]?.future ?? Future.value(book(doc.title));
          },
        );
      },
    );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('eink_launcher/battery_events'),
          null,
        );
    registry.dispose();
    BookStoreService.instance.dispose();
    await directory.delete(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> mount(
    WidgetTester tester,
    DocRef doc, {
    Future<ui.Image?> Function(String)? preview,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              noTransitionRoute(
                ReaderScreen(
                  doc: doc,
                  registry: registry,
                  openingPreviewLoader: preview ?? (_) async => null,
                ),
              ),
            ),
            child: const Text('Files'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Files'));
    await tester.pumpAndSettle();
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    registry.dispose();
    var flushed = false;
    BookStoreService.instance.flush().then((_) => flushed = true);
    for (var n = 0; n < 200 && !flushed; n++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump();
    }
    expect(flushed, isTrue);
    expect(tester.takeException(), isNull);
  }

  testWidgets('physical page buttons navigate the reader and dismiss its menu', (
    tester,
  ) async {
    pending[alpha.id] = Completer<ParsedBook>()
      ..complete(
        ParsedBook(
          title: alpha.title,
          spine: [
            ParsedSpineItem(
              id: 'chapter',
              href: '',
              blocks: [
                for (var i = 0; i < 100; i++)
                  ContentBlock(
                    type: BlockType.paragraph,
                    runs: [
                      InlineRun(
                        text:
                            'Paragraph $i. The sky tells a story about the stars and the universe.',
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ),
      );
    await mount(tester, alpha);
    final session = sessions[alpha.id]!;
    expect(session.pageCount, greaterThan(1));
    expect(find.byType(ReaderMenuOverlay), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.pumpAndSettle();
    expect(session.currentPage, 1);
    expect(find.byType(ReaderMenuOverlay), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.audioVolumeUp);
    await tester.pumpAndSettle();
    expect(session.currentPage, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
    await tester.pumpAndSettle();
    expect(session.currentPage, 0);

    final disableButtons = session.applySettings(
      session.settings.copyWith(pageButtonsEnabled: false),
    );
    await tester.pumpAndSettle();
    await disableButtons;
    for (final key in [
      LogicalKeyboardKey.pageDown,
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.audioVolumeDown,
    ]) {
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
      expect(session.currentPage, 0);
    }
    final bounds = tester.getRect(find.byType(TapZoneLayer));
    await tester.tapAt(Offset(bounds.right - 20, bounds.center.dy));
    await tester.pumpAndSettle();
    expect(session.currentPage, 1);

    final disableTaps = session.applySettings(
      session.settings.copyWith(
        pageButtonsEnabled: true,
        pageTurnTapZonesEnabled: false,
      ),
    );
    await tester.pumpAndSettle();
    await disableTaps;
    await tester.tapAt(Offset(bounds.left + 20, bounds.center.dy));
    await tester.tapAt(Offset(bounds.right - 20, bounds.center.dy));
    await tester.pumpAndSettle();
    expect(session.currentPage, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
    await tester.pumpAndSettle();
    expect(session.currentPage, 0);
    await tester.tapAt(bounds.center);
    await tester.pumpAndSettle();
    expect(find.byType(ReaderMenuOverlay), findsOneWidget);
    await finish(tester);
  });

  testWidgets(
    'switch and close use one route, preserve positions and choose MRU',
    (tester) async {
      registry.selectTab(alpha);
      registry.selectTab(beta);
      registry.selectTab(gamma);
      await mount(tester, alpha);
      final readerElement = tester.element(find.byType(ReaderScreen));
      await sessions[alpha.id]!.goToPercent(0.5);
      final position = sessions[alpha.id]!.position;
      await tester.tap(find.byKey(const ValueKey('reader-tab-beta')));
      await tester.pumpAndSettle();
      expect(sessions[alpha.id]!.isSuspended, isTrue);
      expect(registry.selectedTabId, beta.id);
      expect(tester.element(find.byType(ReaderScreen)), same(readerElement));
      await tester.tap(find.byKey(const ValueKey('reader-tab-alpha')));
      await tester.pumpAndSettle();
      expect(sessions[alpha.id]!.position, position);
      expect(loads[alpha.id], 1);
      expect(
        tester.widget<TextPageView>(find.byType(TextPageView)).session,
        same(sessions[alpha.id]),
      );
      await tester.tap(find.byKey(const ValueKey('reader-tab-close-alpha')));
      await tester.pumpAndSettle();
      expect(registry.selectedTabId, beta.id);
      expect(registry.sessionFor(alpha.id), isNull);
      expect(tester.element(find.byType(ReaderScreen)), same(readerElement));
      await tester.tap(find.byKey(const ValueKey('reader-tab-close-gamma')));
      await tester.pumpAndSettle();
      expect(registry.selectedTabId, beta.id);
      await tester.tap(find.byKey(const ValueKey('reader-tab-close-beta')));
      await tester.pumpAndSettle();
      expect(find.byType(ReaderScreen), findsNothing);
      expect(find.text('Files'), findsOneWidget);
      expect(registry.tabs, isEmpty);
      await finish(tester);
    },
  );

  testWidgets(
    'Back retains the tab and reopening an active session skips loading',
    (tester) async {
      await mount(tester, alpha);
      final session = sessions[alpha.id]!;
      await tester.tap(find.byKey(const Key('reader-close-button')));
      await tester.pumpAndSettle();
      expect(registry.tabs.single.id, alpha.id);
      expect(session.isReady, isTrue);
      await tester.tap(find.text('Files'));
      await tester.pump();
      expect(find.byKey(const Key('reader-loading-indicator')), findsNothing);
      await tester.pumpAndSettle();
      expect(loads[alpha.id], 1);
      expect(registry.tabs.length, 1);
      await finish(tester);
    },
  );

  testWidgets('closing a loading tab ignores its late completion', (
    tester,
  ) async {
    registry.selectTab(alpha);
    pending[beta.id] = Completer<ParsedBook>();
    await mount(tester, beta);
    expect(find.byKey(const Key('reader-loading-indicator')), findsOneWidget);
    expect(
      tester
          .widget<ReaderMenuOverlay>(find.byType(ReaderMenuOverlay))
          .controlsEnabled,
      isFalse,
    );
    await tester.tap(find.byKey(const ValueKey('reader-tab-close-beta')));
    await tester.pumpAndSettle();
    expect(registry.selectedTabId, alpha.id);
    pending[beta.id]!.complete(book(beta.title));
    await tester.pumpAndSettle();
    expect(registry.sessionFor(beta.id), isNull);
    expect(registry.tabs.single.id, alpha.id);
    expect(
      tester.widget<TextPageView>(find.byType(TextPageView)).session.doc.id,
      alpha.id,
    );
    await finish(tester);
  });

  testWidgets('rapid switches during an open recover the final selected tab', (
    tester,
  ) async {
    registry.selectTab(alpha);
    pending[beta.id] = Completer<ParsedBook>();
    await mount(tester, beta);
    await tester.tap(find.byKey(const ValueKey('reader-tab-alpha')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('reader-tab-beta')));
    await tester.pump();
    pending[beta.id]!.complete(book(beta.title));
    await tester.pumpAndSettle();
    expect(registry.selectedTabId, beta.id);
    expect(sessions[beta.id]!.isReady, isTrue);
    expect(sessions[alpha.id]!.isSuspended, isTrue);
    expect(find.byKey(const Key('reader-loading-indicator')), findsNothing);
    expect(
      tester.widget<TextPageView>(find.byType(TextPageView)).session.doc.id,
      beta.id,
    );
    await finish(tester);
  });

  testWidgets(
    'cached resume clears loading even without an intervening paused frame',
    (tester) async {
      await mount(tester, alpha);
      final screen =
          tester.state(find.byType(ReaderScreen)) as WidgetsBindingObserver;
      screen.didChangeAppLifecycleState(AppLifecycleState.paused);
      screen.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(sessions[alpha.id]!.isReady, isTrue);
      expect(loads[alpha.id], 1);
      expect(find.byKey(const Key('reader-loading-indicator')), findsNothing);
      expect(find.byType(TextPageView), findsOneWidget);
      await finish(tester);
    },
  );

  testWidgets(
    'Back while restoring metadata retains the opening tab without opening a session',
    (tester) async {
      registry.dispose();
      final restoration = Completer<void>();
      var opens = 0;
      registry = _DelayedRestoreRegistry(restoration.future, (doc) {
        opens++;
        return TextReaderSession(doc: doc);
      });
      await mount(tester, alpha);
      expect(find.byKey(const ValueKey('reader-tab-alpha')), findsOneWidget);
      await tester.tap(find.byKey(const Key('reader-close-button')));
      await tester.pumpAndSettle();
      restoration.complete();
      await tester.pumpAndSettle();
      expect(registry.tabs.single.id, alpha.id);
      expect(BookStoreService.instance.tabsState.documents.single.id, alpha.id);
      expect(opens, 0);
      expect(find.byType(ReaderScreen), findsNothing);
      await finish(tester);
    },
  );

  testWidgets(
    'PDF preview remains until first rendered content and releases its image',
    (tester) async {
      final opening = Completer<void>();
      final rendering = Completer<ui.Image>();
      final session = _OpeningPdfSession(opening.future, rendering.future);
      pdfSession = session;
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawColor(Colors.black, BlendMode.src);
      final picture = recorder.endRecording();
      final original = (await tester.runAsync(() => picture.toImage(16, 16)))!;
      picture.dispose();
      final preview = original.clone();
      await mount(tester, pdf, preview: (_) async => preview);
      expect(find.byKey(const Key('reader-opening-preview')), findsOneWidget);
      expect(preview.debugDisposed, isFalse);
      opening.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('reader-loading-indicator')), findsOneWidget);
      rendering.complete(original.clone());
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('reader-loading-indicator')), findsNothing);
      expect(preview.debugDisposed, isTrue);
      await finish(tester);
      original.dispose();
    },
  );

  testWidgets(
    'late PDF preview is disposed after Back without reopening reader',
    (tester) async {
      final opening = Completer<void>();
      pdfSession = _OpeningPdfSession(
        opening.future,
        Completer<ui.Image>().future,
      );
      final preview = Completer<ui.Image?>();
      await mount(tester, pdf, preview: (_) => preview.future);
      await tester.tap(find.byKey(const Key('reader-close-button')));
      await tester.pumpAndSettle();
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawColor(Colors.white, BlendMode.src);
      final picture = recorder.endRecording();
      final image = (await tester.runAsync(() => picture.toImage(8, 8)))!;
      picture.dispose();
      preview.complete(image);
      opening.complete();
      await tester.pumpAndSettle();
      expect(image.debugDisposed, isTrue);
      expect(find.byType(ReaderScreen), findsNothing);
      expect(registry.tabs.single.id, pdf.id);
      await finish(tester);
    },
  );
}

class _NoDiskCache extends PaginationCacheService {
  const _NoDiskCache();
  @override
  Future<List<LaidOutPage>?> load(String key) async => null;
  @override
  Future<void> save(String key, List<LaidOutPage> pages) async {}
}

class _DelayedRestoreRegistry extends ReaderSessionRegistry {
  final Future<void> restoration;
  _DelayedRestoreRegistry(this.restoration, ReaderSessionFactory factory)
    : super.forTesting(sessionFactory: factory);
  @override
  Future<void> restoreTabs() async {
    await restoration;
    await super.restoreTabs();
  }
}

class _OpeningPdfSession extends PdfReaderSession {
  final Future<void> opening;
  final Future<ui.Image> rendering;
  bool ready = false;
  bool suspended = false;
  _OpeningPdfSession(this.opening, this.rendering) : super(doc: pdf);
  @override
  bool get isReady => ready;
  @override
  bool get isSuspended => suspended;
  @override
  int get pageCount => 1;
  @override
  Future<void> open() async {
    await opening;
    ready = true;
  }

  @override
  void suspend() {
    ready = false;
    suspended = true;
  }

  @override
  Future<ui.Image> renderCurrentView(
    Size viewport, {
    double devicePixelRatio = 1,
    PdfRenderRequest? request,
  }) => rendering;
}

import 'dart:io';

import 'package:eink_launcher/constants.dart';
import 'package:eink_launcher/main.dart';
import 'package:eink_launcher/reader/controllers/reader_session_registry.dart';
import 'package:eink_launcher/reader/controllers/text_reader_session.dart';
import 'package:eink_launcher/reader/models/content_block.dart';
import 'package:eink_launcher/reader/models/doc_ref.dart';
import 'package:eink_launcher/reader/models/laid_out_page.dart';
import 'package:eink_launcher/reader/models/parsed_book.dart';
import 'package:eink_launcher/reader/models/reader_exception.dart';
import 'package:eink_launcher/reader/screens/reader_screen.dart';
import 'package:eink_launcher/reader/services/book_store_service.dart';
import 'package:eink_launcher/reader/services/pagination_cache_service.dart';
import 'package:eink_launcher/reader/widgets/text_page_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late ReaderSessionRegistry registry;
  late TextReaderSession session;
  Object? loadFailure;
  var loads = 0;
  const doc = DocRef(
    id: 'error-ui',
    path: '/books/book.epub',
    format: DocFormat.epub,
    title: 'Book',
    fileSize: 1,
  );

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
    directory = await Directory.systemTemp.createTemp('reader-errors-');
    await BookStoreService.instance.init(
      customFile: File('${directory.path}/library.json'),
    );
    loadFailure = null;
    loads = 0;
    session = TextReaderSession(
      doc: doc,
      paginationCache: const _NoDiskCache(),
      bookLoader: (_, _) async {
        loads++;
        if (loadFailure != null) throw loadFailure!;
        return ParsedBook(
          title: 'Book',
          spine: [
            ParsedSpineItem(
              id: 'chapter',
              href: '',
              blocks: const [
                ContentBlock(
                  type: BlockType.paragraph,
                  runs: [InlineRun(text: 'A readable page.')],
                ),
              ],
            ),
          ],
        );
      },
    );
    registry = ReaderSessionRegistry.forTesting(sessionFactory: (_) => session);
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    registry.dispose();
    BookStoreService.instance.dispose();
    await directory.delete(recursive: true);
  });

  Future<void> openReader(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              noTransitionRoute(ReaderScreen(doc: doc, registry: registry)),
            ),
            child: const Text('Files'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Files'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'a failed open offers Retry and clears the old error after recovery',
    (tester) async {
      loadFailure = const FormatException('internal parser detail');
      await openReader(tester);
      expect(find.textContaining('Could not read this EPUB'), findsOneWidget);
      expect(find.textContaining('internal parser detail'), findsNothing);
      expect(find.text('Back to files'), findsOneWidget);
      loadFailure = null;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(loads, 2);
      expect(find.byType(TextPageView), findsOneWidget);
      expect(find.textContaining('Could not read this EPUB'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      registry.dispose();
      await _drainWrites(tester);
    },
  );

  testWidgets(
    'encrypted books show a clear message and allow returning to files',
    (tester) async {
      loadFailure = const EncryptedEpubException(
        resourcePath: 'chapter',
        algorithm: 'encrypted',
      );
      await openReader(tester);
      expect(
        find.textContaining('DRM-protected or encrypted content'),
        findsOneWidget,
      );
      await tester.tap(find.text('Back to files'));
      await tester.pumpAndSettle();
      expect(find.text('Files'), findsOneWidget);
      expect(find.byType(ReaderScreen), findsNothing);
      registry.dispose();
      await _drainWrites(tester);
    },
  );

  testWidgets(
    'memory pressure drops text data and waits for explicit continuation',
    (tester) async {
      final observer = ReaderMemoryPressureObserver(registry: registry);
      tester.binding.addObserver(observer);
      addTearDown(() => tester.binding.removeObserver(observer));
      await openReader(tester);
      final position = session.position;
      tester.binding.handleMemoryPressure();
      await tester.pumpAndSettle();
      expect(session.book, isNull);
      expect(session.isSuspended, isTrue);
      expect(find.text('Continue reading'), findsOneWidget);
      expect(loads, 1);
      await tester.tap(find.text('Continue reading'));
      await tester.pumpAndSettle();
      expect(loads, 2);
      expect(session.position, position);
      expect(session.isReady, isTrue);
      expect(find.byType(TextPageView), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      registry.dispose();
      await _drainWrites(tester);
    },
  );
}

// File IO completes on real time; pump fake microtasks between IO turns so
// lifecycle flushes finish before the fixture directory is removed on Windows.
Future<void> _drainWrites(WidgetTester tester) async {
  var complete = false;
  BookStoreService.instance.flush().then((_) => complete = true);
  for (var attempt = 0; attempt < 200 && !complete; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump();
  }
  expect(
    complete,
    isTrue,
    reason: 'Position writes should finish before cleanup.',
  );
}

class _NoDiskCache extends PaginationCacheService {
  const _NoDiskCache();

  @override
  Future<List<LaidOutPage>?> load(String key) async => null;

  @override
  Future<void> save(String key, List<LaidOutPage> pages) async {}
}

import 'dart:async';
import 'dart:io';

import 'package:eink_launcher/reader/controllers/reader_session.dart';
import 'package:eink_launcher/reader/controllers/reader_session_registry.dart';
import 'package:eink_launcher/reader/models/book_state.dart';
import 'package:eink_launcher/reader/models/bookmark.dart';
import 'package:eink_launcher/reader/models/doc_ref.dart';
import 'package:eink_launcher/reader/models/reader_settings.dart';
import 'package:eink_launcher/reader/models/reader_tabs_state.dart';
import 'package:eink_launcher/reader/models/reading_position.dart';
import 'package:eink_launcher/reader/models/toc_entry.dart';
import 'package:eink_launcher/reader/services/book_store_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  DocRef docFor(String id) => DocRef(
    id: id,
    path: '/books/$id.pdf',
    format: DocFormat.pdf,
    title: id,
    fileSize: 10,
  );

  test('reuses an existing session instead of creating a duplicate', () async {
    var createCount = 0;
    final registry = ReaderSessionRegistry.forTesting(
      sessionFactory: (doc) {
        createCount++;
        return _FakeSession(doc);
      },
    );

    final doc = docFor('a');
    final first = await registry.obtain(doc);
    final second = await registry.obtain(doc);

    expect(identical(first, second), isTrue);
    expect(createCount, 1);
    expect((first as _FakeSession).openCalls, 1);
  });

  test('resumes a suspended session instead of reopening it', () async {
    final registry = ReaderSessionRegistry.forTesting(
      sessionFactory: (doc) => _FakeSession(doc),
    );
    final doc = docFor('a');

    final session = await registry.obtain(doc) as _FakeSession;
    session.suspend();
    expect(session.isSuspended, isTrue);

    final resumed = await registry.obtain(doc);

    expect(identical(session, resumed), isTrue);
    expect(session.resumeCalls, 1);
    expect(session.openCalls, 1);
    expect(session.isSuspended, isFalse);
  });

  test('retries a cached session whose first open was not ready', () async {
    final registry = ReaderSessionRegistry.forTesting(
      sessionFactory: (doc) => _FakeSession(doc),
    );
    addTearDown(registry.dispose);
    final session = await registry.obtain(docFor('retry')) as _FakeSession;
    session._isReady = false;
    final retried = await registry.obtain(docFor('retry'));
    expect(retried, same(session));
    expect(session.openCalls, 2);
    expect(session.isReady, isTrue);
  });

  test(
    'suspends the least-recently-used session past the active cap',
    () async {
      final sessions = <String, _FakeSession>{};
      final registry = ReaderSessionRegistry.forTesting(
        sessionFactory: (doc) {
          final s = _FakeSession(doc);
          sessions[doc.id] = s;
          return s;
        },
      );

      for (final id in ['a', 'b', 'c', 'd']) {
        await registry.obtain(docFor(id));
      }
      expect(registry.activeSessionCount, 4);
      expect(sessions.values.every((s) => !s.isSuspended), isTrue);

      await registry.obtain(docFor('e'));

      expect(registry.activeSessionCount, 4);
      expect(
        sessions['a']!.isSuspended,
        isTrue,
        reason: 'a was least recently used',
      );
      expect(sessions['b']!.isSuspended, isFalse);
      expect(sessions['e']!.isSuspended, isFalse);
    },
  );

  test('evict suspends, disposes, and drops a session so a fresh one is created next', () async {
    var createCount = 0;
    final registry = ReaderSessionRegistry.forTesting(
      sessionFactory: (doc) {
        createCount++;
        return _FakeSession(doc);
      },
    );
    final doc = docFor('a');

    final first = await registry.obtain(doc) as _FakeSession;
    registry.evict(doc.id);

    expect(first.suspendCalls, 1);
    expect(first.disposeCalls, 1);

    final second = await registry.obtain(doc) as _FakeSession;
    expect(identical(first, second), isFalse);
    expect(createCount, 2);
  });

  test('dispose suspends and disposes every session', () async {
    final registry = ReaderSessionRegistry.forTesting(
      sessionFactory: (doc) => _FakeSession(doc),
    );
    final a = await registry.obtain(docFor('a')) as _FakeSession;
    final b = await registry.obtain(docFor('b')) as _FakeSession;

    registry.dispose();

    expect(a.suspendCalls, 1);
    expect(a.disposeCalls, 1);
    expect(b.suspendCalls, 1);
    expect(b.disposeCalls, 1);
  });

  test('concurrent requests share one in-flight document open', () async {
    final gate = Completer<void>();
    final registry = ReaderSessionRegistry.forTesting(
      sessionFactory: (doc) => _FakeSession(doc, openGate: gate),
    );
    addTearDown(registry.dispose);
    final first = registry.obtain(docFor('a'));
    final second = registry.obtain(docFor('a'));
    expect((registry.sessionFor('a') as _FakeSession).openCalls, 1);
    gate.complete();
    expect(await first, same(await second));
  });

  test('background suspension survives a late open completion', () async {
    final gate = Completer<void>();
    final registry = ReaderSessionRegistry.forTesting(
      sessionFactory: (doc) => _FakeSession(doc, openGate: gate),
    );
    addTearDown(registry.dispose);
    final opening = registry.obtain(docFor('a'));
    registry.suspendAll();
    gate.complete();
    final session = await opening;
    expect(session.isSuspended, isTrue);
    expect(registry.activeSessionCount, 0);
  });

  test(
    'resuming reserves capacity before opening another native handle',
    () async {
      final gate = Completer<void>();
      final registry = ReaderSessionRegistry.forTesting(
        sessionFactory: (doc) =>
            _FakeSession(doc, resumeGate: doc.id == 'resume' ? gate : null),
      );
      addTearDown(registry.dispose);
      final suspended = await registry.obtain(docFor('resume'));
      suspended.suspend();
      for (final id in ['a', 'b', 'c', 'd']) {
        await registry.obtain(docFor(id));
      }
      final resuming = registry.obtain(docFor('resume'));
      expect(registry.sessionFor('a')?.isSuspended, isTrue);
      gate.complete();
      await resuming;
      expect(
        registry.activeSessionCount,
        ReaderSessionRegistry.maxActiveSessions,
      );
    },
  );

  group('tabs', () {
    late Directory directory;
    late File library;
    late BookStoreService store;
    final registries = <ReaderSessionRegistry>[];

    ReaderSessionRegistry makeRegistry({ReaderSessionFactory? factory}) {
      final registry = ReaderSessionRegistry.forTesting(
        store: store,
        sessionFactory: factory ?? (doc) => _FakeSession(doc),
      );
      registries.add(registry);
      return registry;
    }

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('reader_tabs_');
      library = File('${directory.path}/library.json');
      store = BookStoreService.instance;
      await store.init(customFile: library);
    });

    tearDown(() async {
      for (final registry in registries) {
        registry.dispose();
      }
      registries.clear();
      await store.flush();
      store.dispose();
      await directory.delete(recursive: true);
    });

    test(
      'restart restores ordered metadata and recency without opening',
      () async {
        final registry = makeRegistry();
        await registry.restoreTabs();
        for (final id in ['a', 'b', 'c', 'a']) {
          registry.selectTab(docFor(id));
        }
        await store.flush();
        registry.dispose();
        store.dispose();
        store = BookStoreService.instance;
        await store.init(customFile: library);
        final restored = makeRegistry(
          factory: (_) =>
              throw StateError('Restoration must not open a document'),
        );

        await Future.wait([restored.restoreTabs(), restored.restoreTabs()]);

        expect(restored.tabs.map((doc) => doc.id), ['a', 'b', 'c']);
        expect(restored.tabs.first.title, 'a');
        expect(restored.selectedTabId, 'a');
        expect(restored.mostRecentlyReadTab?.id, 'a');
        expect(restored.activeSessionCount, 0);
        expect(restored.sessionFor('a'), isNull);
        expect(restored.closeTab('a')?.id, 'c');
        expect(restored.closeTab('c')?.id, 'b');
        expect(restored.closeTab('b'), isNull);
        expect(restored.selectedTabId, isNull);
      },
    );

    test('missing recency falls back to stored reading timestamps', () async {
      store.saveTabsState(
        ReaderTabsState(documents: [docFor('a'), docFor('b')]),
      );
      for (final entry in {'a': 3, 'b': 1}.entries) {
        store.saveBookState(
          BookState(
            docId: entry.key,
            lastPath: docFor(entry.key).path,
            format: DocFormat.pdf,
            lastRead: DateTime.utc(2026, 1, entry.value),
            position: PdfReadingPosition(pageIndex: entry.value),
            percent: 0.25,
          ),
        );
      }
      final registry = makeRegistry();
      await registry.restoreTabs();
      expect(registry.mostRecentlyReadTab?.id, 'a');
      expect(registry.selectedTabId, 'a');
      expect(store.getBookState('a')?.percent, 0.25);
      expect(registry.activeSessionCount, 0);
    });

    test(
      'selection deduplicates tabs, updates a moved path and notifies',
      () async {
        final registry = makeRegistry();
        await registry.restoreTabs();
        var changes = 0;
        registry.addListener(() => changes++);
        registry.selectTab(docFor('a'));
        final oldSession = await registry.obtain(docFor('a')) as _FakeSession;
        registry.selectTab(docFor('b'));
        const moved = DocRef(
          id: 'a',
          path: '/renamed/a.pdf',
          format: DocFormat.pdf,
          title: 'Renamed book',
          fileSize: 10,
        );
        registry.selectTab(moved);
        final newSession = await registry.obtain(moved);
        expect(registry.tabs.map((doc) => doc.id), ['a', 'b']);
        expect(registry.tabs.first.path, moved.path);
        expect(registry.tabs.first.title, moved.title);
        expect(oldSession.disposeCalls, 1);
        expect(newSession.doc.path, moved.path);
        expect(registry.selectedTabId, 'a');
        expect(changes, 3);
        expect(() => registry.tabs.clear(), throwsUnsupportedError);
      },
    );

    test(
      'switch suspends hidden tabs while close evicts only its target',
      () async {
        final registry = makeRegistry();
        await registry.restoreTabs();
        registry.selectTab(docFor('a'));
        final a = await registry.obtain(docFor('a')) as _FakeSession;
        registry.selectTab(docFor('b'));
        final b = await registry.obtain(docFor('b')) as _FakeSession;
        expect(a.isSuspended, isTrue);
        expect(b.isReady, isTrue);
        expect(registry.sessionFor('a'), same(a));
        expect(registry.activeSessionCount, 1);
        expect(registry.closeTab('a')?.id, 'b');
        expect(a.disposeCalls, 1);
        expect(b.disposeCalls, 0);
        expect(b.isReady, isTrue);
        expect(registry.sessionFor('a'), isNull);
        expect(registry.selectedTabId, 'b');
      },
    );

    test('a closed in-flight tab cannot replace a reopened session', () async {
      final gate = Completer<void>();
      var creations = 0;
      final registry = makeRegistry(
        factory: (doc) =>
            _FakeSession(doc, openGate: creations++ == 0 ? gate : null),
      );
      await registry.restoreTabs();
      registry.selectTab(docFor('a'));
      final opening = registry.obtain(docFor('a'));
      final old = registry.sessionFor('a') as _FakeSession;
      expect(registry.closeTab('a'), isNull);
      registry.selectTab(docFor('a'));
      final reopened = await registry.obtain(docFor('a'));
      gate.complete();
      await opening;
      expect(old.disposeCalls, 1);
      expect(registry.sessionFor('a'), same(reopened));
      expect(reopened.isReady, isTrue);
      expect(registry.tabs.map((doc) => doc.id), ['a']);
      expect(registry.selectedTabId, 'a');
    });

    test(
      'late hidden open stays suspended and does not change recency',
      () async {
        final gate = Completer<void>();
        final registry = makeRegistry(
          factory: (doc) =>
              _FakeSession(doc, openGate: doc.id == 'a' ? gate : null),
        );
        await registry.restoreTabs();
        registry.selectTab(docFor('a'));
        final opening = registry.obtain(docFor('a'));
        registry.selectTab(docFor('b'));
        await registry.obtain(docFor('b'));
        gate.complete();
        final a = await opening;
        expect(a.isSuspended, isTrue);
        expect(registry.selectedTabId, 'b');
        expect(registry.mostRecentlyReadTab?.id, 'b');
        expect(registry.activeSessionCount, 1);
      },
    );

    test('quick return waits for cancelled open before resuming', () async {
      final gate = Completer<void>();
      final registry = makeRegistry(
        factory: (doc) =>
            _FakeSession(doc, openGate: gate, honorSuspension: true),
      );
      await registry.restoreTabs();
      registry.selectTab(docFor('a'));
      final firstOpen = registry.obtain(docFor('a'));
      registry.selectTab(docFor('b'));
      registry.selectTab(docFor('a'));
      final returnOpen = registry.obtain(docFor('a'));
      gate.complete();
      await firstOpen;
      final a = await returnOpen as _FakeSession;
      expect(a.isReady, isTrue);
      expect(a.openCalls, 1);
      expect(a.resumeCalls, 1);
      expect(registry.selectedTabId, 'a');
    });

    test(
      'selection and close during restore preserve current intent',
      () async {
        store.saveTabsState(
          ReaderTabsState(
            documents: [docFor('a'), docFor('b')],
            selectedTabId: 'a',
          ),
        );
        final registry = makeRegistry();
        final restoring = registry.restoreTabs();
        registry.closeTab('a');
        registry.selectTab(docFor('c'));
        await restoring;
        expect(registry.tabs.map((doc) => doc.id), ['b', 'c']);
        expect(registry.selectedTabId, 'c');
        expect(store.tabsState.documents.map((doc) => doc.id), ['b', 'c']);
        expect(store.tabsState.selectedTabId, 'c');
      },
    );
  });
}

/// Minimal [ReaderSession] double for exercising registry pooling/LRU/cap
/// logic without paying for a real PDFium handle.
class _FakeSession extends ReaderSession {
  _FakeSession(
    this.doc, {
    this.openGate,
    this.resumeGate,
    this.honorSuspension = false,
  });

  final Completer<void>? openGate;
  final Completer<void>? resumeGate;
  final bool honorSuspension;

  @override
  final DocRef doc;

  bool _isReady = false;
  bool _isSuspended = false;
  int openCalls = 0;
  int suspendCalls = 0;
  int resumeCalls = 0;
  int disposeCalls = 0;

  @override
  bool get isReady => _isReady;

  @override
  bool get isSuspended => _isSuspended;

  @override
  String? get error => null;

  @override
  int get pageCount => 1;

  @override
  int get currentPage => 0;

  @override
  double get percent => 0;

  @override
  ReadingPosition get position => const PdfReadingPosition(pageIndex: 0);

  @override
  List<TocEntry> get toc => const [];

  @override
  ReaderSettings get settings => const ReaderSettings();

  @override
  List<Bookmark> get bookmarks => const [];

  @override
  Future<void> open() async {
    openCalls++;
    final suspensionAtStart = suspendCalls;
    if (openGate != null) await openGate!.future;
    if (disposeCalls > 0 ||
        (honorSuspension && suspensionAtStart != suspendCalls)) {
      return;
    }
    _isReady = true;
    _isSuspended = false;
  }

  @override
  Future<void> nextPage() async {}

  @override
  Future<void> prevPage() async {}

  @override
  Future<void> goToPage(int pageIndex) async {}

  @override
  Future<void> goToToc(TocEntry entry) async {}

  @override
  Future<void> goToPercent(double pct) async {}

  @override
  Future<void> applySettings(ReaderSettings settings) async {}

  @override
  Future<void> addBookmark(String label) async {}

  @override
  Future<void> removeBookmark(String id) async {}

  @override
  void suspend() {
    suspendCalls++;
    _isSuspended = true;
    _isReady = false;
  }

  @override
  Future<void> resume() async {
    resumeCalls++;
    if (resumeGate != null) await resumeGate!.future;
    _isSuspended = false;
    _isReady = true;
  }

  @override
  void dispose() {
    disposeCalls++;
    super.dispose();
  }
}

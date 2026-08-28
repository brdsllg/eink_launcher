import 'package:eink_launcher/reader/controllers/reader_session.dart';
import 'package:eink_launcher/reader/controllers/reader_session_registry.dart';
import 'package:eink_launcher/reader/models/doc_ref.dart';
import 'package:eink_launcher/reader/models/reader_settings.dart';
import 'package:eink_launcher/reader/models/reading_position.dart';
import 'package:eink_launcher/reader/models/toc_entry.dart';
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

  test('suspends the least-recently-used session past the active cap', () async {
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
  });

  test(
    'evict suspends, disposes, and drops a session so a fresh one is created next',
    () async {
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
    },
  );

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
}

/// Minimal [ReaderSession] double for exercising registry pooling/LRU/cap
/// logic without paying for a real PDFium handle.
class _FakeSession extends ReaderSession {
  _FakeSession(this.doc);

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
  Future<void> open() async {
    openCalls++;
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
  void suspend() {
    suspendCalls++;
    _isSuspended = true;
    _isReady = false;
  }

  @override
  Future<void> resume() async {
    resumeCalls++;
    _isSuspended = false;
    _isReady = true;
  }

  @override
  void dispose() {
    disposeCalls++;
    super.dispose();
  }
}

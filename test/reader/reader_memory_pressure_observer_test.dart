import 'package:eink_launcher/main.dart';
import 'package:eink_launcher/reader/controllers/reader_session.dart';
import 'package:eink_launcher/reader/controllers/reader_session_registry.dart';
import 'package:eink_launcher/reader/models/bookmark.dart';
import 'package:eink_launcher/reader/models/doc_ref.dart';
import 'package:eink_launcher/reader/models/reader_settings.dart';
import 'package:eink_launcher/reader/models/reading_position.dart';
import 'package:eink_launcher/reader/models/toc_entry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'forwards the OS memory-pressure signal to every open reader session',
    () async {
      final registry = ReaderSessionRegistry.forTesting(
        sessionFactory: (doc) => _FakeSession(doc),
      );
      addTearDown(registry.dispose);

      const doc = DocRef(
        id: 'memory-pressure-test',
        path: '/books/memory-pressure-test.epub',
        format: DocFormat.epub,
        title: 'Memory pressure test',
        fileSize: 10,
      );
      final session = await registry.obtain(doc) as _FakeSession;
      expect(session.isSuspended, isFalse);

      // Not the singleton: proves the observer talks to whatever registry
      // it was given rather than always reaching for
      // ReaderSessionRegistry.instance.
      ReaderMemoryPressureObserver(registry: registry).didHaveMemoryPressure();

      expect(
        session.isSuspended,
        isTrue,
        reason:
            'ReaderSession.handleMemoryPressure defaults to suspend(), '
            'which this session does not override',
      );
    },
  );
}

/// Minimal [ReaderSession] double that tracks suspension through the base
/// class's default `handleMemoryPressure` implementation, rather than
/// overriding it, so the test exercises that default rather than a fake's
/// own bookkeeping.
class _FakeSession extends ReaderSession {
  _FakeSession(this.doc);

  @override
  final DocRef doc;

  bool _suspended = false;

  @override
  bool get isReady => !_suspended;

  @override
  bool get isSuspended => _suspended;

  @override
  String? get error => null;

  @override
  int get pageCount => 1;

  @override
  int get currentPage => 0;

  @override
  double get percent => 0;

  @override
  ReadingPosition get position =>
      const TextReadingPosition(spineIndex: 0, blockIndex: 0, charOffset: 0);

  @override
  List<TocEntry> get toc => const [];

  @override
  ReaderSettings get settings => const ReaderSettings();

  @override
  List<Bookmark> get bookmarks => const [];

  @override
  Future<void> open() async {
    _suspended = false;
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
    _suspended = true;
  }

  @override
  Future<void> resume() async {
    _suspended = false;
  }
}

import '../models/doc_ref.dart';
import 'pdf_reader_session.dart';
import 'reader_session.dart';

typedef ReaderSessionFactory = ReaderSession Function(DocRef doc);

/// Singleton pool of live [ReaderSession]s, keyed by [DocRef.id].
///
/// This is what makes tabs (a future feature — READER_PLAN.md §1.A) safe to
/// add later: sessions live here, not inside a [Navigator] route, so a
/// session backed by a hidden tab keeps its position, TOC, and pagination
/// instead of being torn down on pop.
///
/// At most [maxActiveSessions] sessions hold native handles / bitmaps at
/// once. Requesting one more suspends the least-recently-used active
/// session rather than opening a new native handle unbounded — four open
/// PDFs is enough to OOM the device (READER_PLAN.md §1.A).
class ReaderSessionRegistry {
  static ReaderSessionRegistry? _instance;
  static ReaderSessionRegistry get instance =>
      _instance ??= ReaderSessionRegistry._();

  ReaderSessionRegistry._() : _sessionFactory = _defaultFactory;

  static const int maxActiveSessions = 4;

  final ReaderSessionFactory _sessionFactory;
  final Map<String, ReaderSession> _sessions = {};
  final List<String> _lruOrder = []; // least-recent first

  ReaderSessionRegistry.forTesting({ReaderSessionFactory? sessionFactory})
    : _sessionFactory = sessionFactory ?? _defaultFactory;

  static ReaderSession _defaultFactory(DocRef doc) {
    switch (doc.format) {
      case DocFormat.pdf:
        return PdfReaderSession(doc: doc);
      case DocFormat.epub:
      case DocFormat.txt:
      case DocFormat.markdown:
        throw UnimplementedError(
          '${doc.format.name} reader sessions arrive in a later phase.',
        );
    }
  }

  /// Returns the live session for [doc], creating and opening one if none
  /// exists yet, or resuming it first if it was suspended. Callers must
  /// ensure `BookStoreService.instance.init()` has completed before this is
  /// called, since sessions read/write persisted state on open.
  Future<ReaderSession> obtain(DocRef doc) async {
    var session = _sessions[doc.id];
    if (session == null) {
      session = _sessionFactory(doc);
      _sessions[doc.id] = session;
      await session.open();
    } else if (session.isSuspended) {
      await session.resume();
    }
    _touch(doc.id);
    _enforceCap();
    return session;
  }

  /// Suspends every active session, e.g. when the app is backgrounded.
  /// Sessions remain in the pool and can be resumed via [obtain].
  void suspendAll() {
    for (final session in _sessions.values) {
      session.suspend();
    }
  }

  /// Drops a session entirely (e.g. its file was deleted), suspending and
  /// disposing it first.
  void evict(String docId) {
    final session = _sessions.remove(docId);
    _lruOrder.remove(docId);
    if (session == null) return;
    session.suspend();
    session.dispose();
  }

  /// Suspends and disposes every session and resets the registry. Intended
  /// for app shutdown and test teardown.
  void dispose() {
    for (final session in _sessions.values) {
      session.suspend();
      session.dispose();
    }
    _sessions.clear();
    _lruOrder.clear();
    _instance = null;
  }

  int get activeSessionCount =>
      _sessions.values.where((s) => !s.isSuspended).length;

  void _touch(String docId) {
    _lruOrder.remove(docId);
    _lruOrder.add(docId);
  }

  void _enforceCap() {
    final active = _lruOrder
        .where((id) => !(_sessions[id]?.isSuspended ?? true))
        .toList();
    var excess = active.length - maxActiveSessions;
    var i = 0;
    while (excess > 0 && i < active.length) {
      _sessions[active[i]]?.suspend();
      excess -= 1;
      i += 1;
    }
  }
}

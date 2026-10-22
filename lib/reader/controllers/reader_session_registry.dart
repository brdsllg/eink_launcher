import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/doc_ref.dart';
import '../models/reader_tabs_state.dart';
import '../services/book_store_service.dart';
import 'pdf_reader_session.dart';
import 'reader_session.dart';
import 'text_reader_session.dart';

typedef ReaderSessionFactory = ReaderSession Function(DocRef doc);

/// Owns tab metadata and document sessions independently of reader routes.
///
/// Selecting a tab suspends hidden sessions. Back navigation retains the tab
/// and its session; closing a tab evicts it. The active-session cap also protects
/// callers that use the session pool without selecting a reader tab.
class ReaderSessionRegistry extends ChangeNotifier {
  static ReaderSessionRegistry? _instance;
  static ReaderSessionRegistry get instance =>
      _instance ??= ReaderSessionRegistry._();

  ReaderSessionRegistry._() : _sessionFactory = _defaultFactory, _store = null;

  static const int maxActiveSessions = 4;

  /// How many closed tabs are remembered for "reopen".
  static const int maxRecentlyClosed = 10;

  final ReaderSessionFactory _sessionFactory;
  final BookStoreService? _store;
  final Map<String, ReaderSession> _sessions = {};
  final Map<ReaderSession, Future<void>> _pending = {};
  final Set<ReaderSession> _requestedActive = {};
  final List<String> _lruOrder = []; // least-recent first
  final List<DocRef> _tabs = [];
  final List<DocRef> _recentlyClosed = []; // most recently closed first
  final Set<String> _closedBeforeRestore = {};
  String? _selectedTabId;
  Future<void>? _restoration;
  bool _tabsRestored = false;
  bool _disposed = false;

  ReaderSessionRegistry.forTesting({
    ReaderSessionFactory? sessionFactory,
    this._store,
  }) : _sessionFactory = sessionFactory ?? _defaultFactory;

  BookStoreService get _bookStore => _store ?? BookStoreService.instance;

  List<DocRef> get tabs => List.unmodifiable(_tabs);
  List<DocRef> get recentlyClosedTabs => List.unmodifiable(_recentlyClosed);
  String? get selectedTabId => _selectedTabId;

  DocRef? get mostRecentlyReadTab {
    for (final id in _lruOrder.reversed) {
      final index = _tabs.indexWhere((doc) => doc.id == id);
      if (index >= 0) return _tabs[index];
    }
    return _tabs.isEmpty ? null : _tabs.last;
  }

  ReaderSession? sessionFor(String id) => _sessions[id];

  /// Loads persisted metadata without invoking the session factory or opening
  /// any document. Safe to call concurrently.
  Future<void> restoreTabs() => _restoration ??= _restoreTabs();

  Future<void> _restoreTabs() async {
    await _bookStore.init();
    if (_disposed) return;
    final saved = _bookStore.tabsState;
    final localTabs = List<DocRef>.of(_tabs);
    final localRecency = List<String>.of(_lruOrder);
    final hadLocalChanges =
        localTabs.isNotEmpty || _closedBeforeRestore.isNotEmpty;
    final byId = <String, DocRef>{
      for (final doc in saved.documents)
        if (!_closedBeforeRestore.contains(doc.id)) doc.id: doc,
      for (final doc in localTabs) doc.id: doc,
    };
    _tabs
      ..clear()
      ..addAll(byId.values);
    final seenClosed = <String>{};
    final mergedClosed = [
      for (final doc in [
        ...List<DocRef>.of(_recentlyClosed),
        ...saved.recentlyClosed,
      ])
        if (!byId.containsKey(doc.id) && seenClosed.add(doc.id)) doc,
    ];
    _recentlyClosed
      ..clear()
      ..addAll(mergedClosed.take(maxRecentlyClosed));

    // Older state may omit recency. BookState supplies reading timestamps,
    // while DocRef supplies the title (BookState intentionally has no title).
    final fallback = List<DocRef>.of(_tabs);
    fallback.sort((a, b) {
      final aRead = _bookStore.getBookState(a.id)?.lastRead;
      final bRead = _bookStore.getBookState(b.id)?.lastRead;
      final comparison = (aRead?.millisecondsSinceEpoch ?? 0).compareTo(
        bRead?.millisecondsSinceEpoch ?? 0,
      );
      return comparison != 0
          ? comparison
          : _tabs.indexOf(a).compareTo(_tabs.indexOf(b));
    });
    _lruOrder.clear();
    for (final id in [
      ...fallback.map((doc) => doc.id),
      ...saved.recency,
      ...localRecency,
    ]) {
      if (byId.containsKey(id) || _sessions.containsKey(id)) _touch(id);
    }
    _selectedTabId ??= byId.containsKey(saved.selectedTabId)
        ? saved.selectedTabId
        : mostRecentlyReadTab?.id;
    if (_selectedTabId != null) _touch(_selectedTabId!);
    _tabsRestored = true;
    _closedBeforeRestore.clear();
    if (hadLocalChanges) _persistTabs();
    notifyListeners();
  }

  /// Registers or selects a document immediately. Matching identities update
  /// the existing tab's path/title and never create duplicates.
  void selectTab(DocRef doc) {
    if (_disposed) return;
    _closedBeforeRestore.remove(doc.id);
    _recentlyClosed.removeWhere((closed) => closed.id == doc.id);
    final index = _tabs.indexWhere((tab) => tab.id == doc.id);
    if (index < 0) {
      _tabs.add(doc);
    } else {
      _tabs[index] = doc;
    }
    final existing = _sessions[doc.id];
    if (existing != null && existing.doc.path != doc.path) evict(doc.id);
    _selectedTabId = doc.id;
    _touch(doc.id);
    _suspendHiddenSessions();
    _persistTabs();
    notifyListeners();
  }

  /// Removes one tab and returns the tab the reader should display next.
  /// Closing the selection chooses the most-recently-read remaining document.
  DocRef? closeTab(String id) {
    if (_disposed) return null;
    if (!_tabsRestored) _closedBeforeRestore.add(id);
    final closedIndex = _tabs.indexWhere((doc) => doc.id == id);
    if (closedIndex >= 0) {
      _recentlyClosed
        ..removeWhere((closed) => closed.id == id)
        ..insert(0, _tabs[closedIndex]);
      if (_recentlyClosed.length > maxRecentlyClosed) {
        _recentlyClosed.removeRange(maxRecentlyClosed, _recentlyClosed.length);
      }
    }
    _tabs.removeWhere((doc) => doc.id == id);
    evict(id);
    if (_selectedTabId == id || !_tabs.any((doc) => doc.id == _selectedTabId)) {
      _selectedTabId = mostRecentlyReadTab?.id;
      if (_selectedTabId != null) _touch(_selectedTabId!);
      _suspendHiddenSessions();
    }
    _persistTabs();
    notifyListeners();
    for (final doc in _tabs) {
      if (doc.id == _selectedTabId) return doc;
    }
    return null;
  }

  /// Moves one open tab [offset] places (negative = toward the start),
  /// stopping at either end. Returns whether the order changed.
  bool moveTab(String id, int offset) {
    if (_disposed || offset == 0) return false;
    final from = _tabs.indexWhere((doc) => doc.id == id);
    if (from < 0) return false;
    final to = (from + offset).clamp(0, _tabs.length - 1).toInt();
    if (to == from) return false;
    _tabs.insert(to, _tabs.removeAt(from));
    _persistTabs();
    notifyListeners();
    return true;
  }

  /// Puts a recently closed tab back at the end of the open tabs. The current
  /// selection is left alone. Returns null if [id] is not in the closed list.
  DocRef? reopenClosedTab(String id) {
    if (_disposed) return null;
    final index = _recentlyClosed.indexWhere((doc) => doc.id == id);
    if (index < 0) return null;
    final doc = _recentlyClosed.removeAt(index);
    _closedBeforeRestore.remove(doc.id);
    if (!_tabs.any((tab) => tab.id == doc.id)) _tabs.add(doc);
    _persistTabs();
    notifyListeners();
    return doc;
  }

  /// Drops one entry from the recently closed list without reopening it.
  void forgetClosedTab(String id) {
    if (_disposed) return;
    final before = _recentlyClosed.length;
    _recentlyClosed.removeWhere((doc) => doc.id == id);
    if (_recentlyClosed.length == before) return;
    _persistTabs();
    notifyListeners();
  }

  static ReaderSession _defaultFactory(DocRef doc) {
    switch (doc.format) {
      case DocFormat.pdf:
        return PdfReaderSession(doc: doc);
      case DocFormat.epub:
      case DocFormat.txt:
      case DocFormat.markdown:
        return TextReaderSession(doc: doc);
    }
  }

  /// Creates, opens or resumes a pooled session. Concurrent requests share the
  /// underlying open. A late completion cannot revive an evicted/hidden tab or
  /// alter the selected tab or reading recency.
  Future<ReaderSession> obtain(DocRef doc) async {
    if (_disposed) throw StateError('The reader session registry is disposed.');
    var session = _sessions[doc.id];
    if (session != null && session.doc.path != doc.path) {
      evict(doc.id);
      session = null;
    }
    session ??= _sessionFactory(doc);
    _sessions[doc.id] = session;
    _touch(doc.id);
    if (_selectedTabId == null || _selectedTabId == doc.id) {
      _requestedActive.add(session);
    } else {
      _requestedActive.remove(session);
      session.suspend();
    }
    _enforceCap();

    final pending = _pending[session];
    if (pending != null) await pending;
    if (!_owns(session) || !_requestedActive.contains(session)) return session;

    if (session.isSuspended || !session.isReady) {
      // A previous open may have been cancelled by a tab switch. Wait for its
      // cleanup before resuming the same session when it is selected again.
      final operation = _pending[session] ??= _activate(session);
      await operation;
    }
    if (_owns(session)) _enforceCap();
    return session;
  }

  Future<void> _activate(ReaderSession session) async {
    try {
      if (session.isSuspended) {
        await session.resume();
      } else {
        await session.open();
      }
    } finally {
      _pending.remove(session);
      if (_owns(session) && !_requestedActive.contains(session)) {
        session.suspend();
      }
    }
  }

  bool _owns(ReaderSession session) =>
      !_disposed && identical(_sessions[session.doc.id], session);

  void _suspendHiddenSessions() {
    for (final session in _sessions.values) {
      if (session.doc.id == _selectedTabId) {
        _requestedActive.add(session);
      } else {
        _requestedActive.remove(session);
        session.suspend();
      }
    }
  }

  void suspendAll() {
    _requestedActive.clear();
    for (final session in _sessions.values) {
      session.suspend();
    }
  }

  void handleMemoryPressure() {
    _requestedActive.clear();
    for (final session in _sessions.values) {
      session.handleMemoryPressure();
    }
  }

  /// Removes a session only; [closeTab] also removes persisted tab metadata.
  void evict(String docId) {
    final session = _sessions.remove(docId);
    _lruOrder.remove(docId);
    if (session == null) return;
    _requestedActive.remove(session);
    session.suspend();
    session.dispose();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _requestedActive.clear();
    for (final session in _sessions.values) {
      session.suspend();
      session.dispose();
    }
    _sessions.clear();
    _lruOrder.clear();
    _tabs.clear();
    _recentlyClosed.clear();
    if (identical(_instance, this)) _instance = null;
    super.dispose();
  }

  int get activeSessionCount =>
      _sessions.values.where((session) => !session.isSuspended).length;

  void _touch(String docId) {
    _lruOrder.remove(docId);
    _lruOrder.add(docId);
  }

  void _enforceCap() {
    final active = _lruOrder.where((id) {
      final session = _sessions[id];
      return session != null &&
          (_requestedActive.contains(session) || !session.isSuspended);
    }).toList();
    final excess = active.length - maxActiveSessions;
    for (final id in active.take(excess > 0 ? excess : 0)) {
      final session = _sessions[id]!;
      _requestedActive.remove(session);
      session.suspend();
    }
  }

  void _persistTabs() {
    if (!_tabsRestored) {
      unawaited(restoreTabs());
      return;
    }
    _bookStore.saveTabsState(
      ReaderTabsState(
        documents: _tabs,
        selectedTabId: _selectedTabId,
        recency: _lruOrder,
        recentlyClosed: _recentlyClosed,
      ),
    );
    // Explicit tab actions should survive an immediate process restart;
    // ordinary reading-position saves retain the store's debounce behavior.
    unawaited(_bookStore.flush());
  }
}

import 'dart:async';

/// What a navigation needs before it can show a chapter's page.
enum PageNeed {
  /// At least one page exists (crossing forward into a chapter).
  any,

  /// The pages cover the position the reader is going to (turning a page, or
  /// jumping to a TOC entry, search match, or bookmark).
  position,

  /// The chapter is finished. Crossing backwards needs its last page, and page
  /// breaks are only known once the whole chapter has been measured.
  complete,
}

/// Layout work for one spine item within one pagination generation.
///
/// Both the background pass and page turns ask for chapters through this
/// object, so a chapter is laid out once and every waiter is woken by the same
/// publication. [done] completes even when the work is abandoned (suspension,
/// memory pressure, or a newer layout), which keeps pending navigations from
/// waiting forever.
class ChapterLayout {
  ChapterLayout(this.spineIndex);

  final int spineIndex;
  final Completer<void> _done = Completer<void>();
  final List<Completer<void>> _publications = [];
  bool _finished = false;
  Object? _error;

  /// Set when the chapter was laid out but the layout failed.
  Object? get error => _error;

  Future<void> get done => _done.future;

  /// Resolves when more pages become available, or immediately when no more
  /// will (the chapter finished or the work was abandoned).
  Future<void> nextPublication() {
    if (_finished) return Future<void>.value();
    final completer = Completer<void>();
    _publications.add(completer);
    return completer.future;
  }

  void published() => _releaseWaiters();

  void fail(Object error) {
    _error = error;
    _finish();
  }

  /// Releases waiters and lets the background pass move on, whatever the
  /// outcome. Safe to call more than once.
  void finish() => _finish();

  void _finish() {
    _finished = true;
    if (!_done.isCompleted) _done.complete();
    _releaseWaiters();
  }

  void _releaseWaiters() {
    for (final waiter in _publications) {
      if (!waiter.isCompleted) waiter.complete();
    }
    _publications.clear();
  }
}

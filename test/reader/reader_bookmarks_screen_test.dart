import 'package:eink_launcher/reader/controllers/reader_session.dart';
import 'package:eink_launcher/reader/models/bookmark.dart';
import 'package:eink_launcher/reader/models/doc_ref.dart';
import 'package:eink_launcher/reader/models/reader_settings.dart';
import 'package:eink_launcher/reader/models/reading_position.dart';
import 'package:eink_launcher/reader/models/toc_entry.dart';
import 'package:eink_launcher/reader/screens/reader_bookmarks_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('adds, lists, navigates to, and deletes bookmarks', (
    tester,
  ) async {
    final session = _FakeSession();
    addTearDown(session.dispose);

    Bookmark? popped;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              popped = await Navigator.of(context).push<Bookmark>(
                MaterialPageRoute(
                  builder: (_) => ReaderBookmarksScreen(session: session),
                ),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('No bookmarks yet'), findsOneWidget);

    // Add a bookmark, accepting the pre-filled default label.
    await tester.tap(find.byKey(const Key('reader-add-bookmark-button')));
    await tester.pumpAndSettle();
    expect(find.text('Add bookmark'), findsOneWidget);
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect(session.bookmarks, hasLength(1));
    expect(find.text('Page 3'), findsOneWidget);
    expect(find.text('No bookmarks yet'), findsNothing);

    // Tapping the row pops the screen with that bookmark.
    await tester.tap(find.text('Page 3'));
    await tester.pumpAndSettle();
    expect(popped, isNotNull);
    expect(popped!.label, 'Page 3');
    expect(popped!.position, session.position);

    // Reopen and delete it.
    popped = null;
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final bookmarkId = session.bookmarks.first.id;
    await tester.tap(find.byKey(Key('bookmark-delete-$bookmarkId')));
    await tester.pumpAndSettle();
    expect(find.text('Delete bookmark'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(session.bookmarks, isEmpty);
    expect(find.text('No bookmarks yet'), findsOneWidget);
    expect(popped, isNull, reason: 'deleting must not pop the screen');
  });
}

/// Minimal [ReaderSession] double, same pattern as
/// `reader_session_registry_test.dart`'s `_FakeSession`, extended with a
/// mutable, notifying bookmark list.
class _FakeSession extends ReaderSession {
  List<Bookmark> _bookmarks = const [];

  @override
  final DocRef doc = const DocRef(
    id: 'bookmarks-test',
    path: '/books/bookmarks-test.epub',
    format: DocFormat.epub,
    title: 'Bookmarks test',
    fileSize: 10,
  );

  @override
  bool get isReady => true;

  @override
  bool get isSuspended => false;

  @override
  String? get error => null;

  @override
  int get pageCount => 10;

  @override
  int get currentPage => 2;

  @override
  double get percent => 0.3;

  @override
  ReadingPosition get position =>
      const TextReadingPosition(spineIndex: 0, blockIndex: 2, charOffset: 0);

  @override
  List<TocEntry> get toc => const [];

  @override
  ReaderSettings get settings => const ReaderSettings();

  @override
  List<Bookmark> get bookmarks => _bookmarks;

  @override
  Future<void> open() async {}

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
  Future<void> addBookmark(String label) async {
    _bookmarks = List<Bookmark>.unmodifiable([
      ..._bookmarks,
      Bookmark(
        id: Bookmark.generateId(),
        docId: doc.id,
        createdAt: DateTime.now(),
        label: label,
        position: position,
      ),
    ]);
    notifyListeners();
  }

  @override
  Future<void> removeBookmark(String id) async {
    _bookmarks = List<Bookmark>.unmodifiable(
      _bookmarks.where((b) => b.id != id),
    );
    notifyListeners();
  }

  @override
  void suspend() {}

  @override
  Future<void> resume() async {}
}

import 'package:flutter/material.dart';

import '../../constants.dart';
import '../../widgets/paginated_list.dart';
import '../controllers/reader_session.dart';
import '../models/bookmark.dart';

/// Bookmark management for the current document.
///
/// Reads and mutates bookmarks directly through [session] (rather than a
/// static list handed in by the caller) so additions and deletions are
/// reflected immediately via the session's own [ChangeNotifier] — the same
/// pattern [ReaderScreen] already uses to react to session state.
///
/// Tapping a bookmark pops the screen with that [Bookmark]; the caller is
/// expected to navigate to its [Bookmark.position] (see
/// `ReaderScreen._openBookmarks`).
class ReaderBookmarksScreen extends StatefulWidget {
  final ReaderSession session;

  const ReaderBookmarksScreen({super.key, required this.session});

  @override
  State<ReaderBookmarksScreen> createState() => _ReaderBookmarksScreenState();
}

class _ReaderBookmarksScreenState extends State<ReaderBookmarksScreen> {
  int _page = 0;

  Future<void> _addBookmark() async {
    final session = widget.session;
    final defaultLabel = session.pageCount == 0
        ? 'Bookmark'
        : 'Page ${session.currentPage + 1}';
    final controller = TextEditingController(text: defaultLabel);
    final label = await showDialog<String>(
      context: context,
      animationStyle: AnimationStyle.noAnimation,
      builder: (context) => AlertDialog(
        title: const Text('Add bookmark'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Label',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!mounted) return;
    final trimmed = label?.trim();
    if (trimmed == null || trimmed.isEmpty) return;
    await session.addBookmark(trimmed);
  }

  Future<void> _confirmRemove(Bookmark bookmark) async {
    final confirmed = await showDialog<bool>(
      context: context,
      animationStyle: AnimationStyle.noAnimation,
      builder: (context) => AlertDialog(
        title: const Text('Delete bookmark'),
        content: Text('Delete "${bookmark.label}"?\n\nThis can\'t be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) await widget.session.removeBookmark(bookmark.id);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.session,
      builder: (context, _) {
        // Newest first, so a bookmark just added is on the first page.
        final bookmarks = List<Bookmark>.of(widget.session.bookmarks)
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return Scaffold(
          appBar: AppBar(
            title: const Text('Bookmarks'),
            centerTitle: true,
            shape: const Border(
              bottom: BorderSide(color: Colors.black, width: 1.5),
            ),
            actions: [
              IconButton(
                key: const Key('reader-add-bookmark-button'),
                icon: const Icon(Icons.bookmark_add_outlined),
                tooltip: 'Add bookmark',
                onPressed: _addBookmark,
              ),
            ],
          ),
          body: bookmarks.isEmpty
              ? const Center(child: Text('No bookmarks yet'))
              : PaginatedList<Bookmark>(
                  items: bookmarks,
                  currentPage: _page,
                  onPageChanged: (page) => setState(() => _page = page),
                  rowHeight: kRowHeight,
                  itemBuilder: (context, bookmark) => SizedBox(
                    height: kRowHeight,
                    child: InkWell(
                      key: ValueKey('bookmark-${bookmark.id}'),
                      onTap: () => Navigator.of(context).pop(bookmark),
                      child: Container(
                        padding: const EdgeInsetsDirectional.only(
                          start: 16,
                        ),
                        decoration: const BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: Colors.black, width: 1),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                bookmark.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 16),
                              ),
                            ),
                            IconButton(
                              key: ValueKey('bookmark-delete-${bookmark.id}'),
                              icon: const Icon(Icons.delete_outline),
                              tooltip: 'Delete bookmark',
                              onPressed: () => _confirmRemove(bookmark),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
        );
      },
    );
  }
}

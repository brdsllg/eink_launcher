import 'dart:io';

import 'package:flutter/material.dart';

import '../../constants.dart';
import '../../widgets/adaptive_grid.dart';
import '../../widgets/control_bar_row.dart';
import '../../widgets/inverting_ink_well.dart';
import '../../widgets/paginated_list.dart';
import '../controllers/reader_session_registry.dart';
import '../models/doc_ref.dart';

/// What the reader should do when the tabs screen closes.
class ReaderTabsResult {
  /// Switch to this tab.
  final DocRef? tabToOpen;

  /// The tab being read was closed from the list. The reader closes it itself
  /// so it can show the next tab, or leave if none remain.
  final bool closesCurrentTab;

  const ReaderTabsResult.openTab(DocRef doc)
    : tabToOpen = doc,
      closesCurrentTab = false;

  const ReaderTabsResult.closeCurrentTab()
    : tabToOpen = null,
      closesCurrentTab = true;
}

/// All open tabs and recently closed tabs in one paged list.
///
/// Open tabs: tap to go to the tab, ▲/▼ to move it one place, X to close.
/// Recently closed: tap to put the tab back in the open list (this screen
/// stays up, so several can be restored in a row).
///
/// Reordering, closing other tabs and reopening act on [registry] directly.
/// Going to a tab, or closing the tab being read, pops with a
/// [ReaderTabsResult] because only the reader can switch what it shows.
class ReaderTabsScreen extends StatefulWidget {
  final ReaderSessionRegistry registry;
  final String currentTabId;

  const ReaderTabsScreen({
    super.key,
    required this.registry,
    required this.currentTabId,
  });

  @override
  State<ReaderTabsScreen> createState() => _ReaderTabsScreenState();
}

sealed class _TabsRow {
  const _TabsRow();
}

class _HeaderRow extends _TabsRow {
  const _HeaderRow(this.label);
  final String label;
}

class _NoteRow extends _TabsRow {
  const _NoteRow(this.message);
  final String message;
}

class _OpenRow extends _TabsRow {
  const _OpenRow(this.doc, this.index, this.count);
  final DocRef doc;
  final int index;
  final int count;
}

class _ClosedRow extends _TabsRow {
  const _ClosedRow(this.doc);
  final DocRef doc;
}

class _ReaderTabsScreenState extends State<ReaderTabsScreen> {
  int _page = 0;

  void _goTo(DocRef doc) =>
      Navigator.of(context).pop(ReaderTabsResult.openTab(doc));

  void _close(DocRef doc) {
    if (doc.id == widget.currentTabId) {
      Navigator.of(context).pop(const ReaderTabsResult.closeCurrentTab());
    } else {
      widget.registry.closeTab(doc.id);
    }
  }

  Future<void> _reopen(DocRef doc) async {
    final exists = await File(doc.path).exists();
    if (!mounted) return;
    if (exists) {
      widget.registry.reopenClosedTab(doc.id);
      return;
    }
    final remove = await showDialog<bool>(
      context: context,
      animationStyle: AnimationStyle.noAnimation,
      builder: (context) => GridDialog(
        title: const Text('File not found'),
        content: Text(
          '"${doc.title}" has been moved or deleted, so it can\'t be reopened.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (remove == true) widget.registry.forgetClosedTab(doc.id);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.registry,
      builder: (context, _) {
        final open = widget.registry.tabs;
        final closed = widget.registry.recentlyClosedTabs;
        final rows = <_TabsRow>[
          _HeaderRow('Open tabs (${open.length})'),
          if (open.isEmpty)
            const _NoteRow('No open tabs')
          else
            for (var i = 0; i < open.length; i++)
              _OpenRow(open[i], i, open.length),
          _HeaderRow('Recently closed (${closed.length})'),
          if (closed.isEmpty)
            const _NoteRow('Nothing closed recently')
          else
            for (final doc in closed) _ClosedRow(doc),
        ];
        final actionWidth = readerHeaderActionWidth(
          MediaQuery.sizeOf(context).width,
        );
        return Scaffold(
          appBar: const GridAppBar(title: Text('Tabs')),
          body: PaginatedList<_TabsRow>(
            items: rows,
            currentPage: _page,
            onPageChanged: (page) => setState(() => _page = page),
            rowHeight: kReaderChromeRowHeight,
            boxedNavigation: true,
            itemBuilder: (context, row) => _frame(switch (row) {
              _HeaderRow(:final label) => _header(label),
              _NoteRow(:final message) => _note(message),
              _OpenRow(:final doc, :final index, :final count) => _openRow(
                doc,
                index,
                count,
                actionWidth,
              ),
              _ClosedRow(:final doc) => _closedRow(doc, actionWidth),
            }),
          ),
        );
      },
    );
  }

  Widget _frame(Widget child) => SizedBox(
    height: kReaderChromeRowHeight,
    child: DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.black)),
      ),
      child: child,
    ),
  );

  Widget _header(String label) => ColoredBox(
    color: Colors.black,
    child: Align(
      alignment: AlignmentDirectional.centerStart,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ),
  );

  Widget _note(String message) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Text(
        message,
        style: const TextStyle(fontSize: 16, fontStyle: FontStyle.italic),
      ),
    ),
  );

  Widget _openRow(DocRef doc, int index, int count, double actionWidth) {
    final selected = doc.id == widget.currentTabId;
    final foreground = selected ? Colors.white : Colors.black;
    final background = selected ? Colors.black : Colors.white;
    return Material(
      color: background,
      child: ControlBarRow(
        children: [
          Expanded(
            child: Semantics(
              button: true,
              selected: selected,
              label: 'Open ${doc.title}',
              excludeSemantics: true,
              child: InvertingInkWell(
                key: ValueKey('reader-tabs-open-${doc.id}'),
                onTap: () => _goTo(doc),
                invertOnPress: !selected,
                color: background,
                child: Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 32,
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(color: foreground, fontSize: 16),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          doc.title,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: foreground,
                            fontSize: 17,
                            fontWeight: selected
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          _action(
            key: ValueKey('reader-tabs-up-${doc.id}'),
            icon: Icons.keyboard_arrow_up,
            tooltip: 'Move ${doc.title} up',
            onPressed: index == 0
                ? null
                : () => widget.registry.moveTab(doc.id, -1),
            foreground: foreground,
            background: background,
            width: actionWidth,
          ),
          _action(
            key: ValueKey('reader-tabs-down-${doc.id}'),
            icon: Icons.keyboard_arrow_down,
            tooltip: 'Move ${doc.title} down',
            onPressed: index == count - 1
                ? null
                : () => widget.registry.moveTab(doc.id, 1),
            foreground: foreground,
            background: background,
            width: actionWidth,
          ),
          _action(
            key: ValueKey('reader-tabs-close-${doc.id}'),
            icon: Icons.close,
            tooltip: 'Close ${doc.title}',
            onPressed: () => _close(doc),
            foreground: foreground,
            background: background,
            width: actionWidth,
          ),
        ],
      ),
    );
  }

  Widget _closedRow(DocRef doc, double actionWidth) {
    return Material(
      color: Colors.white,
      child: ControlBarRow(
        children: [
          Expanded(
            child: Semantics(
              button: true,
              label: 'Reopen ${doc.title}',
              excludeSemantics: true,
              child: InvertingInkWell(
                key: ValueKey('reader-tabs-closed-${doc.id}'),
                onTap: () => _reopen(doc),
                child: Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      doc.title,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 17),
                    ),
                  ),
                ),
              ),
            ),
          ),
          _action(
            key: ValueKey('reader-tabs-reopen-${doc.id}'),
            icon: Icons.restore,
            tooltip: 'Reopen ${doc.title}',
            onPressed: () => _reopen(doc),
            foreground: Colors.black,
            background: Colors.white,
            width: actionWidth,
          ),
        ],
      ),
    );
  }

  Widget _action({
    required Key key,
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
    required Color foreground,
    required Color background,
    required double width,
  }) {
    return SizedBox(
      width: width,
      child: InvertingPressListener(
        color: background,
        child: IconButton(
          key: key,
          tooltip: tooltip,
          onPressed: onPressed,
          style: ButtonStyle(
            foregroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.disabled)
                  ? Colors.grey
                  : foreground,
            ),
            backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
            overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          ),
          padding: EdgeInsets.zero,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          icon: Icon(icon, size: 28),
        ),
      ),
    );
  }
}

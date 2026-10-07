import 'package:flutter/material.dart';

import '../../constants.dart';
import '../../widgets/adaptive_grid.dart';
import '../../widgets/inverting_ink_well.dart';
import '../../widgets/paginated_list.dart';
import '../models/toc_entry.dart';

class ReaderTocScreen extends StatefulWidget {
  final List<TocEntry> entries;

  const ReaderTocScreen({super.key, required this.entries});

  @override
  State<ReaderTocScreen> createState() => _ReaderTocScreenState();
}

class _VisibleEntry {
  final TocEntry entry;
  final String path;

  const _VisibleEntry({required this.entry, required this.path});
}

class _ReaderTocScreenState extends State<ReaderTocScreen> {
  int _page = 0;

  /// Index-paths (e.g. "0", "0/2") of expanded parents. Collapsed by default
  /// so Parshiyot and Tehillim days page as short parent lists on e-ink.
  final Set<String> _expanded = {};

  List<_VisibleEntry> get _visibleEntries {
    final visible = <_VisibleEntry>[];
    void collect(List<TocEntry> entries, String prefix) {
      for (var i = 0; i < entries.length; i++) {
        final path = prefix.isEmpty ? '$i' : '$prefix/$i';
        final entry = entries[i];
        visible.add(_VisibleEntry(entry: entry, path: path));
        if (entry.children.isNotEmpty && _expanded.contains(path)) {
          collect(entry.children, path);
        }
      }
    }

    collect(widget.entries, '');
    return visible;
  }

  void _toggle(String path) {
    setState(() {
      if (_expanded.contains(path)) {
        _expanded.remove(path);
        // Collapse descendants too, so re-expanding starts clean.
        _expanded.removeWhere((p) => p.startsWith('$path/'));
      } else {
        _expanded.add(path);
      }
      _page = _page; // Clamped by PaginatedList; kept explicit for e-ink.
    });
  }

  @override
  Widget build(BuildContext context) {
    final entries = _visibleEntries;
    return Scaffold(
      appBar: const GridAppBar(title: Text('Table of contents')),
      body: entries.isEmpty
          ? const Center(child: Text('No table of contents'))
          : PaginatedList<_VisibleEntry>(
              items: entries,
              currentPage: _page,
              onPageChanged: (page) => setState(() => _page = page),
              rowHeight: kRowHeight,
              boxedNavigation: true,
              itemBuilder: (context, visible) {
                final entry = visible.entry;
                final hasChildren = entry.children.isNotEmpty;
                final expanded = _expanded.contains(visible.path);
                final affordance = hasChildren
                    ? (expanded ? '[-] ' : '[+] ')
                    : '';
                return SizedBox(
                  height: kRowHeight,
                  child: InvertingInkWell(
                    key: ValueKey('toc-${entry.title}'),
                    onTap: hasChildren
                        ? () => _toggle(visible.path)
                        : entry.position == null
                        ? null
                        : () => Navigator.of(context).pop(entry),
                    child: Container(
                      padding: EdgeInsetsDirectional.only(
                        start: 16 + entry.level.clamp(0, 4) * 20,
                        end: 16,
                      ),
                      alignment: AlignmentDirectional.centerStart,
                      decoration: const BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: Colors.black, width: 1),
                        ),
                      ),
                      child: Text(
                        '$affordance${entry.title}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: entry.level == 0 ? 17 : 15,
                          fontWeight: entry.level == 0
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

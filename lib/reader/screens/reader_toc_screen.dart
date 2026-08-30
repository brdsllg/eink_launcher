import 'package:flutter/material.dart';

import '../../constants.dart';
import '../../widgets/paginated_list.dart';
import '../models/toc_entry.dart';

class ReaderTocScreen extends StatefulWidget {
  final List<TocEntry> entries;

  const ReaderTocScreen({super.key, required this.entries});

  @override
  State<ReaderTocScreen> createState() => _ReaderTocScreenState();
}

class _ReaderTocScreenState extends State<ReaderTocScreen> {
  int _page = 0;

  List<TocEntry> get _flatEntries =>
      List<TocEntry>.unmodifiable(widget.entries.expand(_flatten));

  Iterable<TocEntry> _flatten(TocEntry entry) sync* {
    yield entry;
    for (final child in entry.children) {
      yield* _flatten(child);
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = _flatEntries;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Table of contents'),
        centerTitle: true,
        shape: const Border(
          bottom: BorderSide(color: Colors.black, width: 1.5),
        ),
      ),
      body: entries.isEmpty
          ? const Center(child: Text('No table of contents'))
          : PaginatedList<TocEntry>(
              items: entries,
              currentPage: _page,
              onPageChanged: (page) => setState(() => _page = page),
              rowHeight: kRowHeight,
              itemBuilder: (context, entry) => SizedBox(
                height: kRowHeight,
                child: InkWell(
                  key: ValueKey('toc-${entry.title}'),
                  onTap: entry.position == null
                      ? null
                      : () => Navigator.of(context).pop(entry),
                  child: Container(
                    padding: EdgeInsetsDirectional.only(
                      start: 16 + entry.level * 20,
                      end: 16,
                    ),
                    alignment: AlignmentDirectional.centerStart,
                    decoration: const BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: Colors.black, width: 1),
                      ),
                    ),
                    child: Text(
                      entry.title,
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
              ),
            ),
    );
  }
}

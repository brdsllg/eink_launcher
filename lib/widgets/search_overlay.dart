import 'package:flutter/material.dart';

import '../constants.dart';
import '../models/file_entry.dart';
import '../services/search_service.dart';
import 'control_bar_row.dart';

class SearchOverlay extends StatefulWidget {
  final String initialPath;
  final VoidCallback onClose;
  final ValueChanged<FileEntry> onEntrySelected;

  const SearchOverlay({
    super.key,
    required this.initialPath,
    required this.onClose,
    required this.onEntrySelected,
  });

  @override
  State<SearchOverlay> createState() => _SearchOverlayState();
}

class _SearchOverlayState extends State<SearchOverlay> {
  final TextEditingController _controller = TextEditingController();
  final StreamingSearchService _searchService = StreamingSearchService();
  bool _wholeDevice = false;
  List<FileEntry> _results = [];
  String _status = '';
  int _searchToken = 0;

  @override
  void dispose() {
    _controller.dispose();
    _searchService.dispose();
    super.dispose();
  }

  Future<void> _runSearch() async {
    final query = _controller.text.trim();
    final token = ++_searchToken;

    if (query.isEmpty) {
      await _searchService.cancel();
      if (!mounted) return;
      setState(() {
        _results = [];
        _status = '';
      });
      return;
    }

    setState(() {
      _results = [];
      _status = 'Searching…';
    });

    final root = _wholeDevice ? kStorageRoot : widget.initialPath;

    await _searchService.search(
      params: SearchParams(root, query),
      onResult: (entry) {
        if (!mounted || token != _searchToken) return;
        setState(() {
          _results.add(entry);
          _status =
              '${_results.length} match${_results.length == 1 ? '' : 'es'} so far…';
        });
      },
      onDone: () {
        if (!mounted || token != _searchToken) return;
        setState(() {
          if (_results.isEmpty) {
            _status = 'No matches';
          } else if (_results.length >= 200) {
            _status = '200+ matches (showing first 200)';
          } else {
            _status =
                '${_results.length} match${_results.length == 1 ? '' : 'es'}';
          }
        });
      },
    );
  }

  void _selectScope(bool wholeDevice) {
    if (_wholeDevice == wholeDevice) return;
    setState(() => _wholeDevice = wholeDevice);
    if (_controller.text.trim().isNotEmpty) _runSearch();
  }

  Widget _scopeButton({required bool wholeDevice, required String label}) {
    final selected = _wholeDevice == wholeDevice;
    return Semantics(
      selected: selected,
      child: TextButton(
        key: ValueKey('search-scope-$wholeDevice'),
        onPressed: () => _selectScope(wholeDevice),
        style: TextButton.styleFrom(
          backgroundColor: selected ? Colors.black : Colors.white,
          foregroundColor: selected ? Colors.white : Colors.black,
          shape: const RoundedRectangleBorder(),
        ),
        child: Text(label, textAlign: TextAlign.center),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(border: Border.all(color: Colors.black)),
            child: Material(
              color: Colors.white,
              // One bounded viewport lets the controls scroll into view even
              // when a landscape keyboard leaves less than two rows of space.
              child: CustomScrollView(
                key: const Key('file-search-panel'),
                shrinkWrap: true,
                slivers: [
                  SliverToBoxAdapter(
                    child: ControlBarRow(
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Center(
                              child: TextField(
                                controller: _controller,
                                autofocus: true,
                                textInputAction: TextInputAction.search,
                                decoration: const InputDecoration(
                                  hintText: 'Search filenames…',
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  contentPadding: EdgeInsets.zero,
                                  isDense: true,
                                ),
                                onSubmitted: (_) => _runSearch(),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: kReaderChromeRowHeight,
                          child: IconButton(
                            tooltip: 'Search',
                            icon: const Icon(Icons.search),
                            onPressed: _runSearch,
                          ),
                        ),
                        SizedBox(
                          width: kReaderChromeRowHeight,
                          child: IconButton(
                            tooltip: 'Close search',
                            icon: const Icon(Icons.close),
                            onPressed: widget.onClose,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SliverToBoxAdapter(
                    child: Divider(
                      height: 1,
                      thickness: 1,
                      color: Colors.black,
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: ControlBarRow(
                      spans: const [1, 1],
                      children: [
                        _scopeButton(wholeDevice: false, label: 'This folder'),
                        _scopeButton(wholeDevice: true, label: 'Whole device'),
                      ],
                    ),
                  ),
                  if (_status.isNotEmpty)
                    SliverToBoxAdapter(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: const BoxDecoration(
                          border: Border(top: BorderSide(color: Colors.black)),
                        ),
                        child: Text(_status),
                      ),
                    ),
                  SliverList.builder(
                    itemCount: _results.length,
                    itemBuilder: (context, index) {
                      final entry = _results[index];
                      return DecoratedBox(
                        position: DecorationPosition.foreground,
                        decoration: const BoxDecoration(
                          border: Border(top: BorderSide(color: Colors.black)),
                        ),
                        child: ListTile(
                          minTileHeight: kReaderChromeRowHeight,
                          leading: SizedBox(
                            width: 24,
                            child: Icon(
                              entry.isDirectory
                                  ? Icons.folder_outlined
                                  : Icons.insert_drive_file_outlined,
                            ),
                          ),
                          title: Text(
                            entry.isDirectory ? '${entry.name}/' : entry.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            entry.path,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => widget.onEntrySelected(entry),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

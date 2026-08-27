import 'package:flutter/material.dart';
import '../constants.dart';
import '../models/file_entry.dart';
import '../services/search_service.dart';

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
  bool _searching = false;
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
        _searching = false;
        _results = [];
        _status = '';
      });
      return;
    }

    setState(() {
      _searching = true;
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
          _status = '${_results.length} match${_results.length == 1 ? '' : 'es'} so far…';
        });
      },
      onDone: () {
        if (!mounted || token != _searchToken) return;
        setState(() {
          _searching = false;
          if (_results.isEmpty) {
            _status = 'No matches';
          } else if (_results.length >= 200) {
            _status = '200+ matches (showing first 200)';
          } else {
            _status = '${_results.length} match${_results.length == 1 ? '' : 'es'}';
          }
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    autofocus: true,
                    textInputAction: TextInputAction.search,
                    decoration: const InputDecoration(
                      hintText: 'Search filenames…',
                      border: InputBorder.none,
                      isDense: true,
                    ),
                    onSubmitted: (_) => _runSearch(),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: _runSearch,
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: widget.onClose,
                ),
              ],
            ),
            Row(
              children: [
                const Text('Scope: '),
                OutlinedButton(
                  onPressed: () {
                    setState(() => _wholeDevice = !_wholeDevice);
                    if (_controller.text.trim().isNotEmpty) _runSearch();
                  },
                  child: Text(_wholeDevice ? 'Whole device' : 'This folder'),
                ),
              ],
            ),
            if (_searching) const LinearProgressIndicator(),
            if (_status.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(_status),
                ),
              ),
            if (_results.isNotEmpty)
              SizedBox(
                height: MediaQuery.sizeOf(context).height * 0.55,
                child: ListView.builder(
                  itemCount: _results.length,
                  itemBuilder: (context, index) {
                    final entry = _results[index];
                    return ListTile(
                      dense: true,
                      title: Text(entry.isDirectory ? '${entry.name}/' : entry.name),
                      subtitle: Text(
                        entry.path,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => widget.onEntrySelected(entry),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}


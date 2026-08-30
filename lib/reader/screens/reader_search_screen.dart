import 'dart:async';

import 'package:flutter/material.dart';

import '../../widgets/paginated_list.dart';
import '../models/content_block.dart';
import '../models/parsed_book.dart';
import '../services/text_search_service.dart';

class ReaderSearchScreen extends StatefulWidget {
  final List<ParsedSpineItem> spine;
  final TextSearchService searchService;

  const ReaderSearchScreen({
    super.key,
    required this.spine,
    this.searchService = const TextSearchService(),
  });

  @override
  State<ReaderSearchScreen> createState() => _ReaderSearchScreenState();
}

class _ReaderSearchScreenState extends State<ReaderSearchScreen> {
  final _query = TextEditingController();
  TextSearchResults? _results;
  String? _error;
  String? _pendingQuery;
  int _generation = 0;
  int _page = 0;
  bool _searching = false;
  bool _workerRunning = false;

  @override
  void dispose() {
    _generation++;
    _pendingQuery = null;
    _query.dispose();
    super.dispose();
  }

  void _queryChanged(String _) {
    // An old result must never be shown or selected for a newly edited query.
    _generation++;
    _pendingQuery = null;
    setState(() {
      _results = null;
      _error = null;
      _searching = false;
      _page = 0;
    });
  }

  void _submit() {
    final query = _query.text.trim();
    if (query.isEmpty) return;
    FocusScope.of(context).unfocus();
    _generation++;
    _pendingQuery = query;
    setState(() {
      _results = null;
      _error = null;
      _searching = true;
      _page = 0;
    });
    unawaited(_runSearches());
  }

  Future<void> _runSearches() async {
    if (_workerRunning) return;
    _workerRunning = true;
    try {
      // At most one worker per screen. Rapid submissions replace the queued
      // query instead of copying a large book into several concurrent isolates.
      while (mounted && _pendingQuery != null) {
        final query = _pendingQuery!;
        final generation = _generation;
        _pendingQuery = null;
        try {
          final results = await widget.searchService.search(
            widget.spine,
            query,
          );
          if (!mounted || generation != _generation) continue;
          setState(() {
            _results = results;
            _searching = false;
          });
        } catch (_) {
          if (!mounted || generation != _generation) continue;
          setState(() {
            _error = 'Could not search this book. Please try again.';
            _searching = false;
          });
        }
      }
    } finally {
      _workerRunning = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Search in book'),
        centerTitle: true,
        shape: const Border(
          bottom: BorderSide(color: Colors.black, width: 1.5),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('reader-search-query'),
                      controller: _query,
                      textInputAction: TextInputAction.search,
                      onChanged: _queryChanged,
                      onSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: 'Search text',
                        border: const OutlineInputBorder(),
                        suffixIcon: _query.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Clear search',
                                onPressed: () {
                                  _query.clear();
                                  _queryChanged('');
                                },
                                icon: const Icon(Icons.clear),
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    key: const Key('reader-search-submit'),
                    onPressed: _query.text.trim().isEmpty || _searching
                        ? null
                        : _submit,
                    child: const Text('Search'),
                  ),
                ],
              ),
            ),
            if (results != null && results.matches.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8, left: 12, right: 12),
                child: Text(
                  results.truncated
                      ? 'First ${results.matches.length} matches — refine your search for more.'
                      : '${results.matches.length} ${results.matches.length == 1 ? 'match' : 'matches'}',
                ),
              ),
            Expanded(
              child: results != null && results.matches.isNotEmpty
                  ? PaginatedList<TextSearchMatch>(
                      items: results.matches,
                      currentPage: _page,
                      onPageChanged: (page) => setState(() => _page = page),
                      rowHeight: 96,
                      itemBuilder: (context, match) =>
                          _SearchResultRow(match: match),
                    )
                  : Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          _error ??
                              (_searching
                                  ? 'Searching…'
                                  : results != null
                                  ? 'No matches'
                                  : 'Enter text to search. Hebrew vowel points are ignored.'),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchResultRow extends StatelessWidget {
  final TextSearchMatch match;

  const _SearchResultRow({required this.match});

  @override
  Widget build(BuildContext context) {
    final position = match.position;
    return SizedBox(
      height: 96,
      child: InkWell(
        key: ValueKey(
          'search-${position.spineIndex}-${position.blockIndex}-${position.charOffset}',
        ),
        onTap: () => Navigator.of(context).pop(match),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Colors.black)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                match.chapterTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                match.snippet,
                textDirection: match.direction == BlockTextDirection.rtl
                    ? TextDirection.rtl
                    : TextDirection.ltr,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 16),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

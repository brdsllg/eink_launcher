import 'dart:isolate';

import 'package:sqlite3/sqlite3.dart';

import '../models/parsed_book.dart';
import '../models/reader_settings.dart';
import '../models/reading_position.dart';
import 'tanach_sqlite_cache_service.dart';
import 'text_search_service.dart';

class TanachSqliteSearchService extends TextSearchService {
  final String databasePath;
  final ReaderSettings settings;
  final Future<void> Function()? ensureDatabase;

  const TanachSqliteSearchService({
    required this.databasePath,
    required this.settings,
    this.ensureDatabase,
  });

  @override
  Future<TextSearchResults> search(
    List<ParsedSpineItem> spine,
    String query, {
    int maxResults = 1000,
  }) async {
    if (maxResults < 1) throw ArgumentError.value(maxResults, 'maxResults');
    await ensureDatabase?.call();
    return _runSearch(databasePath, settings, spine, query, maxResults);
  }
}

// Keep the UI recovery callback outside the isolate closure.
Future<TextSearchResults> _runSearch(
  String path,
  ReaderSettings settings,
  List<ParsedSpineItem> spine,
  String query,
  int limit,
) => Isolate.run(() => _searchDatabase(path, settings, spine, query, limit));

TextSearchResults _searchDatabase(
  String path,
  ReaderSettings settings,
  List<ParsedSpineItem> spine,
  String query,
  int limit,
) {
  final needle = normalizeTanachSearchText(query)
      .replaceAll(RegExp(r'\s+'), '');
  if (needle.isEmpty) return const TextSearchResults();
  final database = sqlite3.open(path, mode: OpenMode.readOnly);
  try {
    // instr preserves literal substring semantics, including %, _, and infixes.
    // Candidate selection ignores filters; projection applies the exact same
    // language fallback and edition selection as the visible reader.
    final candidates = database
        .select('SELECT path FROM documents WHERE instr(search_text, ?) > 0', [
          needle,
        ])
        .map((row) => row['path'] as String)
        .toSet();
    final matches = <TextSearchMatch>[];
    for (var index = 0; index < spine.length; index++) {
      final item = spine[index];
      if (item.isLazy &&
          !TanachSqliteCacheService.relatedDocuments(
            database,
            item.href,
          ).any(candidates.contains)) {
        continue;
      }
      final chapter = TanachSqliteCacheService.projectChapter(
        database,
        item,
        settings,
      );
      final result = searchTextSpine(
        [chapter],
        query,
        limit + 1 - matches.length,
      );
      for (final match in result.matches) {
        if (matches.length == limit) {
          return TextSearchResults(
            matches: List.unmodifiable(matches),
            truncated: true,
          );
        }
        matches.add(
          TextSearchMatch(
            position: TextReadingPosition(
              spineIndex: index,
              blockIndex: match.position.blockIndex,
              charOffset: match.position.charOffset,
              documentPath: item.href,
              blockId: match.position.blockId,
            ),
            endCharOffset: match.endCharOffset,
            chapterTitle: item.title ?? 'Chapter ${index + 1}',
            snippet: match.snippet,
            direction: match.direction,
          ),
        );
      }
    }
    return TextSearchResults(matches: List.unmodifiable(matches));
  } finally {
    database.close();
  }
}

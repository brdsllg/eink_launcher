import 'dart:convert';
import 'dart:io';

import 'package:eink_launcher/reader/models/doc_ref.dart';
import 'package:eink_launcher/reader/models/reader_settings.dart';
import 'package:eink_launcher/reader/services/parsed_epub_cache_service.dart';
import 'package:eink_launcher/reader/services/tanach_sqlite_cache_service.dart';
import 'package:eink_launcher/reader/services/tanach_sqlite_search_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final booksDirectory = Platform.environment['TANACH_FULL_BOOKS_DIR'];
  if (booksDirectory == null) return;

  test(
    'all 39 full Tanach EPUBs import, reopen, load chapters, and search',
    () async {
      final files =
          Directory(booksDirectory)
              .listSync()
              .whereType<File>()
              .where((file) => file.path.toLowerCase().endsWith('.epub'))
              .toList()
            ..sort((a, b) => a.path.compareTo(b.path));
      expect(files, hasLength(39));

      final cacheDirectory = await Directory.systemTemp.createTemp(
        'tanach-full-sqlite-',
      );
      final parsedCache = ParsedEpubCacheService(
        cacheDirectory: cacheDirectory,
      );
      final chapterCache = TanachSqliteCacheService(
        cacheDirectory: Directory('${cacheDirectory.path}/tanach_sqlite'),
      );
      var totalDatabaseBytes = 0;
      try {
        for (final file in files) {
          final watch = Stopwatch()..start();
          final stat = await file.stat();
          final doc = DocRef(
            id: file.uri.pathSegments.last,
            path: file.path,
            title: file.uri.pathSegments.last.replaceAll('.epub', ''),
            format: DocFormat.epub,
            fileSize: stat.size,
          );
          final book = await parsedCache.load(doc, true);
          expect(book.hasLazyTanachContent, isTrue, reason: file.path);
          expect(book.studyTranslations, isNotEmpty, reason: file.path);
          expect(book.spine, isNotEmpty, reason: file.path);
          final lazy = [
            for (var i = 0; i < book.spine.length; i++)
              if (book.spine[i].isLazy) i,
          ];
          expect(lazy, isNotEmpty, reason: file.path);

          final first = await chapterCache.loadChapter(
            book,
            lazy.first,
            const ReaderSettings(),
          );
          final last = await chapterCache.loadChapter(
            book,
            lazy.last,
            ReaderSettings(commentarySources: book.studySources),
          );
          expect(first.blocks, isNotEmpty, reason: file.path);
          expect(last.blocks, isNotEmpty, reason: file.path);

          final search = await TanachSqliteSearchService(
            databasePath: book.tanachDatabasePath!,
            settings: const ReaderSettings(),
          ).search(book.spine, 'Verse', maxResults: 1);
          expect(search.matches, isNotEmpty, reason: file.path);

          final reopened = await parsedCache.load(doc, true);
          expect(reopened.hasLazyTanachContent, isTrue, reason: file.path);
          expect(
            reopened.spine.every((item) => !item.isLazy || !item.isLoaded),
            isTrue,
            reason: file.path,
          );
          watch.stop();
          final databaseBytes = File(book.tanachDatabasePath!).lengthSync();
          totalDatabaseBytes += databaseBytes;
          // ignore: avoid_print
          print(
            jsonEncode({
              'book': file.uri.pathSegments.last,
              'milliseconds': watch.elapsedMilliseconds,
              'chapters': lazy.length,
              'databaseBytes': databaseBytes,
            }),
          );
        }
        // ignore: avoid_print
        print(jsonEncode({'totalDatabaseBytes': totalDatabaseBytes}));
      } finally {
        if (await cacheDirectory.exists()) {
          await cacheDirectory.delete(recursive: true);
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 30)),
  );
}

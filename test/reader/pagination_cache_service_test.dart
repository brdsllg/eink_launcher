import 'dart:convert';
import 'dart:io';

import 'package:eink_launcher/reader/models/laid_out_page.dart';
import 'package:eink_launcher/reader/models/reader_settings.dart';
import 'package:eink_launcher/reader/models/reading_position.dart';
import 'package:eink_launcher/reader/services/pagination_cache_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'evicts least recently read entries and removes abandoned temp files',
    () async {
      final directory = await Directory.systemTemp.createTemp('bounded-pages-');
      addTearDown(() => directory.delete(recursive: true));
      final initial = PaginationCacheService(cacheDirectory: directory);
      await initial.save('a', []);
      final length = await File('${directory.path}/a.json').length();
      final cache = PaginationCacheService(
        cacheDirectory: directory,
        maxBytes: length * 2,
      );
      await cache.save('b', []);
      await File('${directory.path}/a.json').setLastModified(DateTime(2000));
      await File('${directory.path}/b.json').setLastModified(DateTime(2001));
      await cache.load('a');
      final orphan = File('${directory.path}/abandoned.tmp');
      await orphan.writeAsString('partial');
      await orphan.setLastModified(DateTime(2000));
      await cache.save('c', []);
      expect(await cache.load('a'), isNotNull);
      expect(await cache.load('b'), isNull);
      expect(await cache.load('c'), isNotNull);
      expect(await orphan.exists(), isFalse);
      await Future.wait([for (var i = 0; i < 10; i++) cache.save('key$i', [])]);
      final bytes = directory.listSync().whereType<File>().fold<int>(
        0,
        (n, f) => n + f.lengthSync(),
      );
      expect(bytes, lessThanOrEqualTo(length * 2));
      final tiny = PaginationCacheService(
        cacheDirectory: directory,
        maxBytes: 1,
      );
      await tiny.save('oversized', []);
      expect(await File('${directory.path}/oversized.json').exists(), isFalse);
    },
  );
  test('round-trips pages and varies keys with typography', () async {
    final directory = await Directory.systemTemp.createTemp('page-cache-');
    addTearDown(() => directory.delete(recursive: true));
    final cache = PaginationCacheService(cacheDirectory: directory);
    final normalKey = cache.keyFor(
      docId: 'book',
      spineIndex: 1,
      width: 400,
      height: 600,
      settings: const ReaderSettings(),
    );
    final largeKey = cache.keyFor(
      docId: 'book',
      spineIndex: 1,
      width: 400,
      height: 600,
      settings: const ReaderSettings(fontSizeStep: 5),
    );
    expect(normalKey, isNot(largeKey));
    final fractionalKey = cache.keyFor(
      docId: 'book',
      spineIndex: 1,
      width: 400.4,
      height: 600,
      settings: const ReaderSettings(),
    );
    expect(fractionalKey, isNot(normalKey));

    const page = LaidOutPage(
      pageIndex: 0,
      slices: [
        BlockSlice(
          blockIndex: 3,
          startCharOffset: 5,
          endCharOffset: 20,
          sourceTop: 12.5,
          height: 100,
        ),
      ],
      start: TextReadingPosition(spineIndex: 1, blockIndex: 3, charOffset: 5),
      end: TextReadingPosition(spineIndex: 1, blockIndex: 3, charOffset: 20),
    );
    await cache.save(normalKey, const [page]);
    final restored = await cache.load(normalKey);

    expect(restored, hasLength(1));
    expect(restored!.single.start, page.start);
    expect(restored.single.end, page.end);
    expect(restored.single.slices.single.sourceTop, 12.5);

    // A later save replaces the complete entry without leaving shared temp
    // files behind.
    await cache.save(normalKey, const []);
    expect(await cache.load(normalKey), isEmpty);
    expect(
      directory.listSync().whereType<File>().where(
        (file) => file.path.endsWith('.tmp'),
      ),
      isEmpty,
    );

    await File('${directory.path}/$normalKey.json')
        .writeAsString(jsonEncode({'version': 1, 'pages': const []}));
    expect(await cache.load(normalKey), isNull);
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:eink_launcher/reader/models/laid_out_page.dart';
import 'package:eink_launcher/reader/models/reader_settings.dart';
import 'package:eink_launcher/reader/models/reading_position.dart';
import 'package:eink_launcher/reader/services/pagination_cache_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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

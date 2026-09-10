import 'dart:io';
import 'dart:typed_data';

import 'package:eink_launcher/reader/models/content_block.dart';
import 'package:eink_launcher/reader/models/doc_ref.dart';
import 'package:eink_launcher/reader/models/parsed_book.dart';
import 'package:eink_launcher/reader/models/reading_position.dart';
import 'package:eink_launcher/reader/models/toc_entry.dart';
import 'package:eink_launcher/reader/services/parsed_epub_cache_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'reopen skips parser, preserves resources, and invalidates changed inputs',
    () async {
      final dir = await Directory.systemTemp.createTemp('parsed-epub-test');
      addTearDown(() => dir.delete(recursive: true));
      final source = File('${dir.path}/book.epub')
        ..writeAsStringSync('original');
      final cacheDir = Directory('${dir.path}/cache');
      final cache = ParsedEpubCacheService(cacheDirectory: cacheDir);
      final doc = DocRef(
        id: 'book',
        path: source.path,
        format: DocFormat.epub,
        title: 'Book',
        fileSize: 8,
      );
      var calls = 0;
      Future<ParsedBook> parse() async {
        calls++;
        return ParsedBook(
          title: 'Book',
          author: 'Writer',
          language: 'en',
          spine: [
            ParsedSpineItem(
              id: 'one',
              href: 'one.xhtml',
              anchors: {'anchor': 0},
              blocks: const [
                ContentBlock(
                  type: BlockType.paragraph,
                  id: 'anchor',
                  direction: BlockTextDirection.rtl,
                  alignment: BlockAlignment.center,
                  nestingLevel: 2,
                  orderedList: true,
                  runs: [
                    InlineRun(
                      text: 'Text',
                      bold: true,
                      italic: true,
                      code: true,
                      href: 'link',
                      language: 'he',
                    ),
                  ],
                ),
                ContentBlock(
                  type: BlockType.image,
                  resourcePath: 'pic.png',
                  alternateText: 'Picture',
                ),
              ],
            ),
          ],
          resources: {
            'pic.png': Uint8List.fromList([1, 2, 3]),
          },
          tableOfContents: const [
            TocEntry(
              title: 'Chapter',
              targetHref: 'one.xhtml#anchor',
              position: TextReadingPosition(
                spineIndex: 0,
                blockIndex: 0,
                charOffset: 0,
              ),
            ),
          ],
        );
      }

      await cache.load(doc, true, parser: parse);
      final book = await cache.load(doc, true, parser: parse);
      expect(calls, 1);
      expect(book.resources['pic.png'], [1, 2, 3]);
      expect(book.spine.single.anchors, {'anchor': 0});
      final block = book.spine.single.blocks.first;
      expect(block.direction, BlockTextDirection.rtl);
      expect(block.runs.single.bold, isTrue);
      expect(block.runs.single.language, 'he');
      expect(book.tableOfContents.single.targetHref, 'one.xhtml#anchor');
      await cache.load(doc, false, parser: parse);
      expect(calls, 2);
      source.writeAsStringSync('changed source');
      await cache.load(doc, true, parser: parse);
      expect(calls, 3);
      for (final file in cacheDir.listSync().whereType<File>()) {
        file.writeAsStringSync('{broken');
      }
      await cache.load(doc, true, parser: parse);
      expect(calls, 4);
    },
  );
}

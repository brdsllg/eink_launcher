import 'dart:convert';
import 'dart:typed_data';

import 'package:eink_launcher/reader/models/content_block.dart';
import 'package:eink_launcher/reader/models/doc_ref.dart';
import 'package:eink_launcher/reader/models/parsed_book.dart';
import 'package:eink_launcher/reader/services/html_block_parser.dart';
import 'package:eink_launcher/reader/services/text_block_parser.dart';
import 'package:eink_launcher/reader/services/text_search_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = TextSearchService();

  test(
    'finds pointed and unpointed Hebrew with original UTF-16 offsets',
    () async {
      const source = '😀 prefix שָׁלוֹם֑ and שלום';
      final spine = _spine(source);
      for (final query in ['שלום', 'שָׁלוֹם']) {
        final results = await service.search(spine, query);
        expect(results.matches, hasLength(2));
        expect(results.matches.first.position.charOffset, source.indexOf('ש'));
        expect(
          results.matches.last.position.charOffset,
          source.lastIndexOf('ש'),
        );
        expect(
          source.substring(
            results.matches.first.position.charOffset,
            results.matches.first.endCharOffset,
          ),
          'שָׁלוֹם֑',
        );
        expect(results.matches.first.snippet, source);
      }
    },
  );

  test(
    'matches case, inline boundaries, whitespace, and soft hyphens',
    () async {
      final spine = [
        ParsedSpineItem(
          id: 'one',
          href: 'one.xhtml',
          title: 'Opening',
          blocks: const [
            ContentBlock(
              type: BlockType.paragraph,
              runs: [
                InlineRun(text: '😀 HY'),
                InlineRun(text: 'phen\u00adation\n\t works', bold: true),
              ],
            ),
          ],
        ),
      ];
      final results = await service.search(spine, 'hyphenation works');
      final match = results.matches.single;
      expect(match.position.charOffset, 3);
      expect(match.endCharOffset, spine.single.blocks.single.plainText.length);
      expect(match.chapterTitle, 'Opening');
      expect(match.snippet, '😀 HYphen\u00adation works');
    },
  );

  test('keeps Hebrew punctuation and treats queries as literal text', () async {
    final spine = _spine('אב־גד אב׀גד אב׃גד a.b axb');
    expect((await service.search(spine, 'אבגד')).matches, isEmpty);
    for (final query in ['אב־גד', 'אב׀גד', 'אב׃גד', 'a.b']) {
      expect((await service.search(spine, query)).matches, hasLength(1));
    }
  });

  test('empty and marks-only queries return no matches', () async {
    for (final query in ['', '  \n ', '\u05b0\u05c1', '\u00ad']) {
      expect(
        (await service.search(_spine('hello שלום'), query)).matches,
        isEmpty,
      );
    }
    expect((await service.search(const [], 'word')).matches, isEmpty);
    expect(
      () => service.search(const [], 'word', maxResults: 0),
      throwsArgumentError,
    );
  });

  test(
    'bounds results in reading order and reports only actual truncation',
    () async {
      final spine = [
        ..._spine('word word'),
        ParsedSpineItem(
          id: 'two',
          href: 'two',
          blocks: const [
            ContentBlock(type: BlockType.horizontalRule),
            ContentBlock(
              type: BlockType.paragraph,
              runs: [InlineRun(text: 'word')],
            ),
          ],
        ),
      ];
      final capped = await service.search(spine, 'word', maxResults: 2);
      expect(capped.matches.map((m) => m.position.charOffset), [0, 5]);
      expect(capped.truncated, isTrue);
      final exact = await service.search(spine, 'word', maxResults: 3);
      expect(exact.truncated, isFalse);
      expect(exact.matches.last.position.spineIndex, 1);
      expect(exact.matches.last.position.blockIndex, 1);
      expect(exact.matches.last.chapterTitle, 'Chapter 2');
      expect(() => exact.matches.clear(), throwsUnsupportedError);
    },
  );

  test(
    'searches EPUB XHTML, TXT, and Markdown through the same blocks',
    () async {
      final epubBlocks = await const HtmlBlockParser().parse(
        '<h1>Title</h1><p>שָׁלוֹם <b>עולם</b></p>',
      );
      final spines = <List<ParsedSpineItem>>[
        [
          ParsedSpineItem(
            id: 'epub',
            href: 'chapter.xhtml',
            blocks: epubBlocks,
          ),
        ],
      ];
      for (final format in [DocFormat.txt, DocFormat.markdown]) {
        final book = await const TextBlockParser().parseBytes(
          Uint8List.fromList(
            utf8.encode(
              format == DocFormat.txt
                  ? 'Title\n\nשָׁלוֹם עולם'
                  : '# Title\n\nשָׁלוֹם **עולם**',
            ),
          ),
          format: format,
          title: 'Notes',
        );
        spines.add(book.spine);
      }
      for (final spine in spines) {
        final match = (await service.search(spine, 'שלום עולם')).matches.single;
        expect(match.position.blockIndex, 1);
        expect(match.position.charOffset, 0);
        expect(match.direction, BlockTextDirection.rtl);
      }
    },
  );

  test(
    'does not join separate paragraphs and keeps previews bounded',
    () async {
      final spine = [
        ParsedSpineItem(
          id: 'one',
          href: '',
          blocks: [
            const ContentBlock(
              type: BlockType.paragraph,
              runs: [InlineRun(text: 'hello')],
            ),
            const ContentBlock(
              type: BlockType.paragraph,
              runs: [InlineRun(text: 'world')],
            ),
            ContentBlock(
              type: BlockType.paragraph,
              runs: [InlineRun(text: '${'😀' * 100}needle${'😀' * 100}')],
            ),
          ],
        ),
      ];
      expect((await service.search(spine, 'hello world')).matches, isEmpty);
      final match = (await service.search(spine, 'needle')).matches.single;
      expect(match.position.charOffset, 200);
      expect(match.snippet.length, lessThanOrEqualTo(164));
      expect(match.snippet, startsWith('…'));
      expect(match.snippet, endsWith('…'));
      expect(match.snippet.runes, isNot(contains(0xfffd)));
    },
  );
}

List<ParsedSpineItem> _spine(String text) => [
  ParsedSpineItem(
    id: 'one',
    href: '',
    blocks: [
      ContentBlock(
        type: BlockType.paragraph,
        runs: [InlineRun(text: text)],
      ),
    ],
  ),
];

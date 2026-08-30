import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:markdown/markdown.dart' as markdown;

import '../models/content_block.dart';
import '../models/doc_ref.dart';
import '../models/parsed_book.dart';
import '../models/reading_position.dart';
import '../models/toc_entry.dart';
import 'bidi_service.dart';
import 'html_block_parser.dart';

class TextBlockParser {
  const TextBlockParser();

  Future<ParsedBook> parseFile(
    String path, {
    required DocFormat format,
    required String title,
    bool honorPublisherCss = true,
  }) async {
    final bytes = await File(path).readAsBytes();
    return parseBytes(
      bytes,
      format: format,
      title: title,
      honorPublisherCss: honorPublisherCss,
    );
  }

  Future<ParsedBook> parseBytes(
    Uint8List bytes, {
    required DocFormat format,
    required String title,
    bool honorPublisherCss = true,
  }) => Isolate.run(
    () => parseBytesSync(
      bytes,
      format: format,
      title: title,
      honorPublisherCss: honorPublisherCss,
    ),
  );

  static ParsedBook parseBytesSync(
    Uint8List bytes, {
    required DocFormat format,
    required String title,
    bool honorPublisherCss = true,
  }) {
    if (format != DocFormat.txt && format != DocFormat.markdown) {
      throw ArgumentError('TextBlockParser does not parse ${format.name}.');
    }
    final source = decodeText(bytes);
    final blocks = format == DocFormat.markdown
        ? HtmlBlockParser.parseSync(
            markdown.markdownToHtml(source),
            honorPublisherCss: honorPublisherCss,
          )
        : _plainTextBlocks(source);
    final spine = ParsedSpineItem(
      id: 'document',
      href: '',
      title: title,
      blocks: blocks,
    );
    return ParsedBook(
      title: title,
      spine: [spine],
      tableOfContents: _headingToc(blocks),
    );
  }

  static String decodeText(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xef &&
        bytes[1] == 0xbb &&
        bytes[2] == 0xbf) {
      return utf8.decode(bytes.sublist(3), allowMalformed: true);
    }
    if (bytes.length >= 2 && bytes[0] == 0xff && bytes[1] == 0xfe) {
      return _decodeUtf16(bytes, littleEndian: true, offset: 2);
    }
    if (bytes.length >= 2 && bytes[0] == 0xfe && bytes[1] == 0xff) {
      return _decodeUtf16(bytes, littleEndian: false, offset: 2);
    }
    try {
      return utf8.decode(bytes, allowMalformed: false);
    } on FormatException {
      return _decodeWindows1255(bytes);
    }
  }

  static String _decodeUtf16(
    Uint8List bytes, {
    required bool littleEndian,
    required int offset,
  }) {
    final units = <int>[];
    for (var i = offset; i + 1 < bytes.length; i += 2) {
      units.add(
        littleEndian
            ? bytes[i] | (bytes[i + 1] << 8)
            : (bytes[i] << 8) | bytes[i + 1],
      );
    }
    return String.fromCharCodes(units);
  }

  static String _decodeWindows1255(Uint8List bytes) {
    const punctuation = <int, int>{
      0x80: 0x20ac,
      0x82: 0x201a,
      0x83: 0x0192,
      0x84: 0x201e,
      0x85: 0x2026,
      0x86: 0x2020,
      0x87: 0x2021,
      0x89: 0x2030,
      0x8b: 0x2039,
      0x91: 0x2018,
      0x92: 0x2019,
      0x93: 0x201c,
      0x94: 0x201d,
      0x95: 0x2022,
      0x96: 0x2013,
      0x97: 0x2014,
      0x99: 0x2122,
      0x9b: 0x203a,
    };
    return String.fromCharCodes(
      bytes.map((byte) {
        if (byte < 0x80) return byte;
        if (byte >= 0xe0 && byte <= 0xfa) return 0x05d0 + byte - 0xe0;
        return punctuation[byte] ?? byte;
      }),
    );
  }

  static List<ContentBlock> _plainTextBlocks(String source) {
    final bidi = const BidiService();
    final normalized = source.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    return List<ContentBlock>.unmodifiable(
      normalized
          .split(RegExp(r'\n[\t ]*\n+'))
          .map(
            (paragraph) =>
                paragraph.replaceAll(RegExp(r'[\t ]*\n[\t ]*'), ' ').trim(),
          )
          .where((paragraph) => paragraph.isNotEmpty)
          .map(
            (paragraph) => ContentBlock(
              type: BlockType.paragraph,
              runs: [InlineRun(text: paragraph)],
              direction: bidi.directionFor(paragraph),
            ),
          ),
    );
  }

  static List<TocEntry> _headingToc(List<ContentBlock> blocks) {
    final toc = <TocEntry>[];
    for (var index = 0; index < blocks.length; index++) {
      final level = switch (blocks[index].type) {
        BlockType.heading1 => 0,
        BlockType.heading2 => 1,
        BlockType.heading3 => 2,
        BlockType.heading4 => 3,
        BlockType.heading5 => 4,
        BlockType.heading6 => 5,
        _ => -1,
      };
      if (level >= 0 && blocks[index].plainText.trim().isNotEmpty) {
        toc.add(
          TocEntry(
            title: blocks[index].plainText.trim(),
            level: level,
            position: TextReadingPosition(
              spineIndex: 0,
              blockIndex: index,
              charOffset: 0,
            ),
          ),
        );
      }
    }
    return List<TocEntry>.unmodifiable(toc);
  }
}

import 'dart:typed_data';

import 'content_block.dart';
import 'toc_entry.dart';

class ParsedSpineItem {
  final String id;
  final String href;
  final String? title;
  final List<ContentBlock> blocks;
  final Map<String, int> anchors;
  final int characterCount;

  ParsedSpineItem({
    required this.id,
    required this.href,
    this.title,
    required this.blocks,
    this.anchors = const {},
  }) : characterCount = blocks.fold(
         0,
         (total, block) => total + block.characterCount,
       );
}

class ParsedBook {
  final String title;
  final String? author;
  final String? language;
  final List<ParsedSpineItem> spine;
  final Map<String, Uint8List> resources;
  final List<TocEntry> tableOfContents;
  final List<int> cumulativeCharacterCounts;

  ParsedBook({
    required this.title,
    this.author,
    this.language,
    required this.spine,
    this.resources = const {},
    this.tableOfContents = const [],
  }) : cumulativeCharacterCounts = _buildCumulativeCounts(spine);

  int get characterCount =>
      cumulativeCharacterCounts.isEmpty ? 0 : cumulativeCharacterCounts.last;

  static List<int> _buildCumulativeCounts(List<ParsedSpineItem> spine) {
    var total = 0;
    return List<int>.unmodifiable([
      for (final item in spine) total += item.characterCount,
    ]);
  }
}

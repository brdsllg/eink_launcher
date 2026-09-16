import 'dart:typed_data';

import 'content_block.dart';
import 'toc_entry.dart';

class StudyTranslationOption {
  final String id;
  final String label;

  const StudyTranslationOption({required this.id, required this.label});
}

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
  final Map<String, String> studyDocuments;
  final List<String> studySources;
  final List<StudyTranslationOption> studyTranslations;
  final String? primaryStudyTranslationId;
  final String? studyProjectionKey;
  final String contentFingerprint;
  final bool rightToLeft;
  final String title;
  final String? author;
  final String? language;
  final List<ParsedSpineItem> spine;
  final Map<String, Uint8List> resources;
  final List<TocEntry> tableOfContents;
  final List<int> cumulativeCharacterCounts;

  ParsedBook({
    this.studyDocuments = const {},
    this.studySources = const [],
    this.studyTranslations = const [],
    this.primaryStudyTranslationId,
    this.studyProjectionKey,
    this.contentFingerprint = '',
    this.rightToLeft = false,
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

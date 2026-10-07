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
  final bool isLoaded;
  final bool isLazy;

  ParsedSpineItem({
    required this.id,
    required this.href,
    this.title,
    required this.blocks,
    this.anchors = const {},
    int? characterCount,
    this.isLoaded = true,
    this.isLazy = false,
  }) : characterCount =
           characterCount ??
           blocks.fold(0, (total, block) => total + block.characterCount);
}

class ParsedBook {
  final Map<String, String> studyDocuments;
  final List<String> studySources;
  final List<StudyTranslationOption> studyTranslations;
  final String? primaryStudyTranslationId;
  final String? studyProjectionKey;
  final String contentFingerprint;

  /// The unit a recognized study book is divided into: `'verse'` for the Tanach
  /// `section.verse` dialect, `'segment'` for the Talmud `section.segment`
  /// dialect. Null for books that are not study text. Used only to label the
  /// reader's study controls, so it never affects layout.
  final String? studyUnit;
  final bool rightToLeft;
  final String title;
  final String? author;
  final String? language;
  final List<ParsedSpineItem> spine;
  final Map<String, Uint8List> resources;
  final List<TocEntry> tableOfContents;

  /// The alternate Parshah/Aliyah navigation of the five books of the Torah.
  ///
  /// Empty for every other book, which is what lets the reader show the
  /// toggle only where the publication actually carries one.
  final List<TocEntry> parshaTableOfContents;

  /// The alternate 30-day Tehillim navigation of Psalms.
  ///
  /// Empty for every other book, which is what lets the reader show the
  /// toggle only where the publication actually carries one (or where the
  /// reader can synthesize it for a 150-chapter Psalms).
  final List<TocEntry> tehillimDailyTableOfContents;
  final List<int> cumulativeCharacterCounts;

  /// Path to a disposable, fingerprinted Tanach content cache. When present,
  /// [spine] may contain unloaded chapter placeholders; the reader fetches
  /// their blocks on demand instead of retaining the complete EPUB DOM.
  final String? tanachDatabasePath;

  ParsedBook({
    this.studyDocuments = const {},
    this.studySources = const [],
    this.studyTranslations = const [],
    this.primaryStudyTranslationId,
    this.studyProjectionKey,
    this.contentFingerprint = '',
    this.studyUnit,
    this.rightToLeft = false,
    required this.title,
    this.author,
    this.language,
    required this.spine,
    this.resources = const {},
    this.tableOfContents = const [],
    this.parshaTableOfContents = const [],
    this.tehillimDailyTableOfContents = const [],
    this.tanachDatabasePath,
  }) : cumulativeCharacterCounts = _buildCumulativeCounts(spine);

  bool get hasLazyTanachContent => tanachDatabasePath != null;

  bool get hasParshaToc => parshaTableOfContents.isNotEmpty;

  bool get hasTehillimToc => tehillimDailyTableOfContents.isNotEmpty;

  int get characterCount =>
      cumulativeCharacterCounts.isEmpty ? 0 : cumulativeCharacterCounts.last;

  static List<int> _buildCumulativeCounts(List<ParsedSpineItem> spine) {
    var total = 0;
    return List<int>.unmodifiable([
      for (final item in spine) total += item.characterCount,
    ]);
  }
}

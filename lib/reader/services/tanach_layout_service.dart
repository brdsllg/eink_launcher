import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

import '../models/content_block.dart';
import '../models/parsed_book.dart';
import '../models/reading_position.dart';
import '../models/toc_entry.dart';
import 'html_block_parser.dart';

/// Minimal projection inputs for study layout, so laptop-side tooling can reuse
/// this service without importing the Flutter-dependent ReaderSettings model.
/// ReaderSettings implements this interface; behavior is unchanged.
abstract class StudyProjectionSettings {
  List<String> get commentarySources;
  String get commentaryLanguage;
  String get verseLanguage;
  String get studyTranslation;
  bool get honorPublisherCss;
  bool get showParshaAliyot;
  bool get hideVowelPoints;
  bool get studyContinuous;
}

/// Projects recognized verse/index/footnote relationships into reading order.
/// The original XHTML stays in the parsed book, so filters never delete notes.
class TanachLayoutService {
  /// The projected study sections. Tanach books mark verses with
  /// `section.verse`; the Talmud dialect marks them with `section.segment`.
  /// Both carry `data-ref`, so one selector recognizes either product.
  static const String _studySectionSelector =
      'section.verse[data-ref], section.segment[data-ref]';

  static bool recognizes(String source) =>
      source.contains('data-ref') &&
      html.parse(source).querySelector(_studySectionSelector) != null;

  /// True when a recognized study book uses the Talmud `section.segment`
  /// dialect rather than the Tanach `section.verse` dialect. The reader uses
  /// this only to label its study controls ("Talmud language", "each segment").
  static bool usesSegments(String source) =>
      html.parse(source).querySelector('section.segment[data-ref]') != null;

  static bool _hasType(Element element, String token) {
    for (final entry in element.attributes.entries) {
      final key = entry.key.toString();
      if (!key.endsWith(':type')) continue;
      final prefix = key.split(':').first;
      Element? ancestor = element;
      String? namespace;
      while (ancestor != null && namespace == null) {
        namespace = ancestor.attributes['xmlns:$prefix'];
        ancestor = ancestor.parent;
      }
      if ((namespace == 'http://www.idpf.org/2007/ops' ||
              (prefix == 'epub' && namespace == null)) &&
          entry.value.split(RegExp(r'\s+')).contains(token)) {
        return true;
      }
    }
    return false;
  }

  /// True for the verse/segment index that opens the source chooser. Tanach
  /// marks it `data-category="index"`; the Talmud dialect uses
  /// `class="note-index"` with an `idx-` id instead.
  static bool _isIndex(Element? element) {
    if (element == null) return false;
    if (element.attributes['data-category'] == 'index') return true;
    if (element.classes.contains('note-index')) return true;
    return element.id.startsWith('idx-');
  }

  static ParsedBook layout(ParsedBook book, StudyProjectionSettings settings) {
    if (book.studyDocuments.isEmpty) return book;
    final projectionKey = _projectionKey(settings);
    if (book.studyProjectionKey == projectionKey) return book;
    final documents = {
      for (final entry in book.studyDocuments.entries)
        entry.key: html.parse(entry.value),
    };
    final targets = <String, Element>{};
    final sources = <String>{};
    final translations = <String, StudyTranslationOption>{};
    final primaryTranslationIds = <String>[];
    for (final entry in documents.entries) {
      for (final node in entry.value.querySelectorAll('.translation')) {
        final option = _translationOption(node, primary: true);
        if (option == null) continue;
        translations.putIfAbsent(option.id, () => option);
        if (!primaryTranslationIds.contains(option.id)) {
          primaryTranslationIds.add(option.id);
        }
      }
      for (final node in entry.value.querySelectorAll('[id]')) {
        targets.putIfAbsent('${entry.key}#${node.id}', () => node);
        if (_hasType(node, 'footnote')) {
          final category = node.attributes['data-category'];
          final source = node.attributes['data-source'];
          if (source != null && _commentaryCategories.contains(category)) {
            sources.add(source);
          } else if (category == 'translation') {
            final option = _translationOption(node, primary: false);
            if (option != null) {
              translations.putIfAbsent(option.id, () => option);
            }
          }
        }
      }
    }
    final primaryTranslationId =
        primaryTranslationIds
            .where((id) => translations[id]?.label == 'Metsudah')
            .firstOrNull ??
        primaryTranslationIds.firstOrNull;
    final requestedTranslation = settings.studyTranslation;
    final selectedTranslationId = requestedTranslation.isEmpty
        ? null
        : translations.containsKey(requestedTranslation)
        ? requestedTranslation
        : translations.values
              .where((option) => option.label == requestedTranslation)
              .firstOrNull
              ?.id;
    // Delay removals until every verse has resolved its links (shared notes).
    final extracted = <Element>{};
    final changedPaths = <String>{};
    for (final entry in documents.entries) {
      for (final verse in entry.value.querySelectorAll(_studySectionSelector)) {
        if (verse.id.isEmpty) continue;
        final links = verse
            .querySelectorAll('a')
            .where(
              (a) =>
                  _hasType(a, 'noteref') ||
                  _isIndex(
                    targets[resolve(entry.key, a.attributes['href'] ?? '')],
                  ),
            )
            .toList();
        for (final link in links) {
          final indexKey = resolve(entry.key, link.attributes['href'] ?? '');
          final index = targets[indexKey];
          if (index == null || !_isIndex(index)) {
            continue;
          }
          final linked = <String, Element>{};
          var complete = true;
          for (final noteLink
              in index
                  .querySelectorAll('a')
                  .where((a) => _hasType(a, 'noteref'))) {
            final key = resolve(
              indexKey.split('#').first,
              noteLink.attributes['href'] ?? '',
            );
            final note = targets[key];
            if (note == null ||
                !_hasType(note, 'footnote') ||
                !{
                  ..._commentaryCategories,
                  'translation',
                }.contains(note.attributes['data-category'])) {
              complete = false;
              continue;
            }
            linked.putIfAbsent(key, () => note);
          }
          // Preserve ordinary content and navigation for incomplete indexes.
          if (!complete || linked.isEmpty) continue;
          changedPaths.add(entry.key);
          final primary = verse.querySelector('.translation');
          final alternate = linked.entries
              .where(
                (e) =>
                    e.value.attributes['data-category'] == 'translation' &&
                    _translationId(e.value) == selectedTranslationId,
              )
              .firstOrNull;
          if (primary != null &&
              selectedTranslationId != null &&
              _translationId(primary) != selectedTranslationId &&
              alternate != null) {
            final replacement = _translationBody(
              alternate.value,
              alternate.key,
              verse.id,
            );
            if (replacement != null) primary.replaceWith(replacement);
          }
          for (final noteEntry in linked.entries) {
            final note = noteEntry.value;
            extracted.add(note);
            changedPaths.add(noteEntry.key.split('#').first);
            if (!_commentaryCategories.contains(
                  note.attributes['data-category'],
                ) ||
                !settings.commentarySources.contains(
                  note.attributes['data-source'],
                )) {
              continue;
            }
            final copy = _copy(note, noteEntry.key, verse.id, 'commentary');
            if (settings.commentaryLanguage == 'he' &&
                copy.querySelector('.note-he') != null) {
              for (final node in copy.querySelectorAll('.note-en')) {
                node.remove();
              }
            } else if (settings.commentaryLanguage == 'en' &&
                copy.querySelector('.note-en') != null) {
              for (final node in copy.querySelectorAll('.note-he')) {
                node.remove();
              }
            }
            // A missing selected language retains the available original.
            verse.append(copy);
          }
          extracted.add(index);
          changedPaths.add(indexKey.split('#').first);
          final parent = link.parent;
          link.remove();
          if (parent != null && parent.text.trim().isEmpty) parent.remove();
        }
        _stableIds(verse, verse.id);
      }
    }
    // Retain targets still referenced by unconverted content. This includes
    // a shared note referenced by an incomplete index or a nested source note.
    var changed = true;
    while (changed) {
      changed = false;
      for (final entry in documents.entries) {
        for (final link in entry.value.querySelectorAll('a[href]')) {
          Element? parent = link;
          var removed = false;
          while (parent != null) {
            if (extracted.contains(parent)) {
              removed = true;
              break;
            }
            parent = parent.parent;
          }
          if (removed) continue;
          final target = targets[resolve(entry.key, link.attributes['href']!)];
          if (target != null && extracted.remove(target)) changed = true;
        }
      }
    }
    for (final node in extracted) {
      node.remove();
    }
    for (final document in documents.values) {
      // Remove only a now-empty endnote wrapper, including its heading.
      for (final section in document.querySelectorAll('section')) {
        if (section.querySelector('aside') == null &&
            !section.classes.contains('verse') &&
            section.children.isNotEmpty &&
            section.children.every(
              (e) =>
                  RegExp(r'^h[1-6]$').hasMatch(e.localName ?? '') &&
                  e.text.trim().toLowerCase() == 'translations and commentary',
            )) {
          section.remove();
        }
      }
    }
    // The dual-structure Torah books carry both heading families; show only
    // the one the reader's table of contents currently follows.
    for (final document in documents.values) {
      _applyHeadingMode(document, showParshaAliyot: settings.showParshaAliyot);
    }
    // A chosen verse language drops the other side of every verse, in every
    // chapter, whether or not the chapter needed a note or heading change.
    if (settings.verseLanguage == 'he' || settings.verseLanguage == 'en') {
      for (final document in documents.values) {
        for (final verse in document.querySelectorAll(_studySectionSelector)) {
          _applyVerseLanguage(verse, settings.verseLanguage);
        }
      }
    }
    final spine = book.spine.map((item) {
      if (item.isLoaded &&
          !changedPaths.contains(item.href) &&
          !recognizes(book.studyDocuments[item.href] ?? '')) {
        return item;
      }
      final document = documents[item.href];
      if (document == null) return item;
      final anchors = <String, int>{};
      var blocks = HtmlBlockParser.parseSync(
        document.outerHtml,
        anchors: anchors,
        honorPublisherCss: settings.honorPublisherCss,
        resourceBasePath: item.href.contains('/')
            ? item.href.substring(0, item.href.lastIndexOf('/'))
            : '',
      );
      if (settings.studyContinuous) {
        blocks = mergeContinuousBlocks(blocks);
      }
      return ParsedSpineItem(
        id: item.id,
        href: item.href,
        title: item.title,
        blocks: blocks,
        anchors: {
          ...anchors,
          for (var i = 0; i < blocks.length; i++)
            if (blocks[i].id != null) blocks[i].id!: i,
        },
      );
    }).toList();
    TocEntry remap(TocEntry entry) {
      final target = entry.targetHref;
      final path = target?.split('#').first;
      final si = spine.indexWhere((item) => item.href == path);
      return TocEntry(
        title: entry.title,
        level: entry.level,
        targetHref: target,
        position: si < 0
            ? entry.position
            : TextReadingPosition(
                documentPath: path,
                blockId: target!.contains('#')
                    ? Uri.decodeComponent(target.split('#').last)
                    : null,
                spineIndex: si,
                blockIndex: target.contains('#')
                    ? spine[si].anchors[Uri.decodeComponent(
                            target.split('#').last,
                          )] ??
                          0
                    : 0,
                charOffset: 0,
              ),
        children: entry.children.map(remap).toList(),
      );
    }

    return ParsedBook(
      title: book.title,
      author: book.author,
      language: book.language,
      spine: spine,
      resources: book.resources,
      tableOfContents: book.tableOfContents.map(remap).toList(),
      parshaTableOfContents: book.parshaTableOfContents.map(remap).toList(),
      studyDocuments: book.studyDocuments,
      studySources: orderedStudySources(sources),
      studyTranslations: List<StudyTranslationOption>.unmodifiable(
        translations.values,
      ),
      primaryStudyTranslationId: primaryTranslationId,
      studyProjectionKey: projectionKey,
      studyUnit: book.studyUnit,
      contentFingerprint: book.contentFingerprint,
      rightToLeft: book.rightToLeft,
      tanachDatabasePath: book.tanachDatabasePath,
    );
  }

  static const _commentaryCategories = {
    'rishon',
    'acharon',
    'modern',
    // The Talmud dialect tags every commentary aside simply "commentary".
    'commentary',
  };

  /// Keeps only one heading family in a dual-structure Torah chapter.
  ///
  /// The builder emits the chapter heading next to the Parshah/Aliyah
  /// headings, so a reader that follows one table of contents must not also
  /// page through the other's headings. Chapters without a Parshah heading
  /// are left untouched.
  static void _applyHeadingMode(
    Document document, {
    required bool showParshaAliyot,
  }) {
    final dual = document.querySelector('h1.parsha-heading') != null;
    if (dual && showParshaAliyot) {
      for (final heading in document.querySelectorAll('body h1')) {
        if (!heading.classes.contains('parsha-heading')) heading.remove();
      }
      return;
    }
    for (final heading
        in document.querySelectorAll('.parsha-heading, .aliyah-heading')) {
      heading.remove();
    }
  }


  /// Keeps only the requested side of one verse: Hebrew, English, or both.
  ///
  /// The bilingual verse heading is a label rather than verse text, so it is
  /// never touched. A verse that carries only one language keeps it, which
  /// mirrors the commentary rule that a missing language retains the text that
  /// exists.
  static void _applyVerseLanguage(Element verse, String language) {
    if (language != 'he' && language != 'en') return;
    final hebrew = verse.children.where(_isHebrewVerseBody).toList();
    final english = verse.children.where(_isEnglishVerseBody).toList();
    if (language == 'he') {
      if (hebrew.isEmpty) return;
      for (final element in english) {
        element.remove();
      }
      return;
    }
    if (english.isEmpty) return;
    for (final element in hebrew) {
      element.remove();
    }
  }

  /// The Hebrew verse run: `.hebrew` in the generated books, plus the plain
  /// right-to-left paragraph some editions use instead.
  static bool _isHebrewVerseBody(Element element) =>
      element.localName == 'p' &&
      (element.classes.contains('hebrew') ||
          element.attributes['dir'] == 'rtl' ||
          element.attributes['lang'] == 'he' ||
          element.attributes['xml:lang'] == 'he');

  /// The English verse run, which the builder and the alternate-translation
  /// swap both mark as `.translation`. Tanach uses a `div`; the Talmud
  /// dialect uses a `p`, so the class alone decides.
  static bool _isEnglishVerseBody(Element element) =>
      element.classes.contains('translation');

  static String _projectionKey(StudyProjectionSettings settings) {
    final sources = [...settings.commentarySources]..sort();
    return [
      sources.join('\u001f'),
      settings.commentaryLanguage,
      settings.verseLanguage,
      settings.studyTranslation,
      settings.honorPublisherCss,
      settings.showParshaAliyot,
      settings.hideVowelPoints,
      settings.studyContinuous,
    ].join('\u001e');
  }

  static String resolve(String path, String href) {
    if (href.isEmpty) return '';
    final uri = Uri.tryParse(href);
    if (uri == null || uri.hasScheme || uri.hasAuthority) return href;
    return Uri.decodeFull(Uri(path: path).resolveUri(uri).toString());
  }

  static String? _translationId(Element element) {
    final edition = element.attributes['data-edition']?.trim();
    if (edition != null && edition.isNotEmpty) return edition;
    final source = element.attributes['data-source']?.trim();
    return source == null || source.isEmpty ? null : source;
  }

  static StudyTranslationOption? _translationOption(
    Element element, {
    required bool primary,
  }) {
    final id = _translationId(element);
    if (id == null) return null;
    final label =
        (primary
                ? element.attributes['data-translation-label'] ??
                      element.attributes['data-source']
                : element.attributes['data-source'] ??
                      element.attributes['data-translation-label'])
            ?.trim();
    return StudyTranslationOption(
      id: id,
      label: label == null || label.isEmpty ? id : label,
    );
  }

  static Element? _translationBody(Element note, String key, String verseId) {
    final body = note.children
        .where(
          (child) =>
              child.localName == 'div' &&
              (child.attributes['lang'] == 'en' ||
                  child.attributes['xml:lang'] == 'en' ||
                  child.attributes['dir'] == 'ltr'),
        )
        .firstOrNull;
    if (body == null) return null;
    final copy = body.clone(true);
    copy.id = '$verseId--translation-${Uri.encodeComponent(key)}';
    copy.classes.add('translation');
    copy.attributes['data-primary'] = 'false';
    final edition = note.attributes['data-edition'];
    if (edition != null) copy.attributes['data-edition'] = edition;
    final label = note.attributes['data-source'];
    if (label != null) copy.attributes['data-translation-label'] = label;
    for (final backlink in copy.querySelectorAll('.backlinks')) {
      backlink.remove();
    }
    for (final link in copy.querySelectorAll('[href]')) {
      link.attributes['href'] = resolve(
        key.split('#').first,
        link.attributes['href']!,
      );
    }
    _stableIds(copy, copy.id);
    return copy;
  }

  static Element _copy(Element note, String key, String verseId, String kind) {
    final copy = note.clone(true);
    copy.id = '$verseId--$kind-${Uri.encodeComponent(key)}';
    for (final backlink in copy.querySelectorAll('.backlinks')) {
      backlink.remove();
    }
    for (final link in copy.querySelectorAll('[href]')) {
      link.attributes['href'] = resolve(
        key.split('#').first,
        link.attributes['href']!,
      );
    }
    _stableIds(copy, copy.id);
    return copy;
  }

  /// Rashi (and its slot substitutes Rashbam/Mefaresh) first, Tosafot
  /// second, then the rest alphabetically.
  static List<String> orderedStudySources(Set<String> sources) {
    int rank(String source) {
      final lower = source.toLowerCase();
      if (lower.startsWith('rashi') ||
          lower.startsWith('rashbam') ||
          lower.startsWith('mefaresh')) {
        return 0;
      }
      if (lower.startsWith('tosafot')) return 1;
      return 2;
    }

    final sorted = sources.toList()
      ..sort((a, b) {
        final rankCompare = rank(a).compareTo(rank(b));
        if (rankCompare != 0) return rankCompare;
        return a.toLowerCase().compareTo(b.toLowerCase());
      });
    return sorted;
  }

  /// Talmud continuous mode: join consecutive body paragraphs so breaks fall
  /// only at headings (segment headings like `Berakhot 2a:1`) and amud/file
  /// boundaries. Headings, lists, quotes, images and rules stay as separators.
  static List<ContentBlock> mergeContinuousBlocks(List<ContentBlock> blocks) {
    final merged = <ContentBlock>[];
    var pending = <InlineRun>[];
    var pendingDirection = BlockTextDirection.ltr;
    String? pendingId;

    void flush() {
      if (pending.isEmpty) return;
      merged.add(
        ContentBlock(
          type: BlockType.paragraph,
          runs: List<InlineRun>.unmodifiable(pending),
          direction: pendingDirection,
          id: pendingId,
        ),
      );
      pending = <InlineRun>[];
      pendingId = null;
    }

    for (final block in blocks) {
      if (block.type == BlockType.paragraph &&
          block.resourcePath == null &&
          block.trailingRuns.isEmpty) {
        if (pending.isEmpty) {
          pendingDirection = block.direction;
          pendingId = block.id;
        }
        if (pending.isNotEmpty) {
          pending.add(const InlineRun(text: ' '));
        }
        pending.addAll(block.runs);
      } else {
        flush();
        merged.add(block);
      }
    }
    flush();
    return List<ContentBlock>.unmodifiable(merged);
  }

  static void _stableIds(Element root, String prefix) {
    var i = 0;
    for (final element in root.querySelectorAll(
      'p, div, h1, h2, h3, h4, h5, h6, blockquote, pre, li',
    )) {
      if (element.id.isEmpty) element.id = '$prefix--block-${i++}';
    }
    final first = root.querySelector('p, div, h1, h2, h3, h4, h5, h6');
    if (first != null && root.classes.contains('verse')) first.id = prefix;
  }
}

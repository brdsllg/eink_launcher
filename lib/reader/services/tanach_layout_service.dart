import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

import '../models/parsed_book.dart';
import '../models/reader_settings.dart';
import '../models/reading_position.dart';
import '../models/toc_entry.dart';
import 'html_block_parser.dart';

/// Projects recognized verse/index/footnote relationships into reading order.
/// The original XHTML stays in the parsed book, so filters never delete notes.
class TanachLayoutService {
  static bool recognizes(String source) =>
      source.contains('data-ref') &&
      html.parse(source).querySelector('section.verse[data-ref]') != null;

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

  static ParsedBook layout(ParsedBook book, ReaderSettings settings) {
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
      for (final verse in entry.value.querySelectorAll(
        'section.verse[data-ref]',
      )) {
        if (verse.id.isEmpty) continue;
        final links = verse
            .querySelectorAll('a')
            .where((a) => _hasType(a, 'noteref'))
            .toList();
        for (final link in links) {
          final indexKey = resolve(entry.key, link.attributes['href'] ?? '');
          final index = targets[indexKey];
          if (index == null ||
              !_hasType(index, 'footnote') ||
              index.attributes['data-category'] != 'index') {
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
    final spine = book.spine.map((item) {
      if (item.isLoaded &&
          !changedPaths.contains(item.href) &&
          !recognizes(book.studyDocuments[item.href] ?? '')) {
        return item;
      }
      final document = documents[item.href];
      if (document == null) return item;
      final anchors = <String, int>{};
      final blocks = HtmlBlockParser.parseSync(
        document.outerHtml,
        anchors: anchors,
        honorPublisherCss: settings.honorPublisherCss,
        resourceBasePath: item.href.contains('/')
            ? item.href.substring(0, item.href.lastIndexOf('/'))
            : '',
      );
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
      studyDocuments: book.studyDocuments,
      studySources: sources.toList()..sort(),
      studyTranslations: List<StudyTranslationOption>.unmodifiable(
        translations.values,
      ),
      primaryStudyTranslationId: primaryTranslationId,
      studyProjectionKey: projectionKey,
      contentFingerprint: book.contentFingerprint,
      rightToLeft: book.rightToLeft,
      tanachDatabasePath: book.tanachDatabasePath,
    );
  }

  static const _commentaryCategories = {'rishon', 'acharon', 'modern'};

  static String _projectionKey(ReaderSettings settings) {
    final sources = [...settings.commentarySources]..sort();
    return [
      sources.join('\u001f'),
      settings.commentaryLanguage,
      settings.studyTranslation,
      settings.honorPublisherCss,
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

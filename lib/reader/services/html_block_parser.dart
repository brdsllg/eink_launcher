import 'dart:isolate';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import '../models/content_block.dart';
import 'bidi_service.dart';

class HtmlBlockParser {
  const HtmlBlockParser();

  Future<List<ContentBlock>> parse(
    String xhtml, {
    bool honorPublisherCss = true,
    String resourceBasePath = '',
  }) {
    return Isolate.run(
      () => parseSync(
        xhtml,
        honorPublisherCss: honorPublisherCss,
        resourceBasePath: resourceBasePath,
      ),
    );
  }

  static List<ContentBlock> parseSync(
    String xhtml, {
    bool honorPublisherCss = true,
    String resourceBasePath = '',
    Map<String, int>? anchors,
  }) {
    final fragment = html_parser.parseFragment(xhtml);
    final walker = _HtmlWalker(
      honorPublisherCss: honorPublisherCss,
      resourceBasePath: resourceBasePath,
    );
    walker.parseContainer(fragment);
    anchors?.addAll(walker.anchors);
    return List<ContentBlock>.unmodifiable(walker.blocks);
  }
}

class _HtmlWalker {
  static const _containerTags = {
    'body',
    'article',
    'section',
    'main',
    'header',
    'footer',
    'div',
    'nav',
    'aside',
  };
  static const _ignoredTags = {
    'script',
    'style',
    'head',
    'title',
    'meta',
    'link',
    'base',
    'template',
  };
  static const _directBlockTags = {
    'p',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'blockquote',
    'pre',
    'address',
    'figcaption',
  };

  final bool honorPublisherCss;
  final String resourceBasePath;
  final BidiService _bidi = const BidiService();
  final List<ContentBlock> blocks = [];
  final Map<String, int> anchors = {};

  _HtmlWalker({
    required this.honorPublisherCss,
    required this.resourceBasePath,
  });

  void parseContainer(Node container, {int listDepth = 0}) {
    final inlineBuffer = <Node>[];

    void flushInlineBuffer() {
      if (inlineBuffer.isEmpty) return;
      final element = container is Element ? container : null;
      final runs = _inlineRuns(
        inlineBuffer,
        element == null
            ? const _RunStyle()
            : _styleFor(element, const _RunStyle()),
      );
      inlineBuffer.clear();
      _addTextBlock(BlockType.paragraph, element: element, runs: runs);
    }

    for (final node in container.nodes) {
      if (node is! Element) {
        inlineBuffer.add(node);
        continue;
      }
      final tag = node.localName ?? '';
      if (_ignoredTags.contains(tag)) continue;
      if (!_isBlock(tag)) {
        inlineBuffer.add(node);
        continue;
      }

      flushInlineBuffer();
      final start = blocks.length;
      _parseBlockElement(node, listDepth: listDepth);
      if (blocks.length > start) {
        if (node.id.isNotEmpty) anchors.putIfAbsent(node.id, () => start);
        if (!_containerTags.contains(tag)) {
          for (final anchor in node.querySelectorAll('[id], a[name]')) {
            final id = anchor.id.isEmpty
                ? anchor.attributes['name']
                : anchor.id;
            if (id != null && id.isNotEmpty) {
              anchors.putIfAbsent(id, () => start);
            }
          }
        }
      }
    }
    flushInlineBuffer();
  }

  bool _isBlock(String tag) =>
      _containerTags.contains(tag) ||
      _directBlockTags.contains(tag) ||
      tag == 'ul' ||
      tag == 'ol' ||
      tag == 'li' ||
      tag == 'hr' ||
      tag == 'img' ||
      tag == 'figure';

  void _parseBlockElement(Element element, {required int listDepth}) {
    final tag = element.localName ?? '';
    if (_ignoredTags.contains(tag)) return;
    if (tag == 'hr') {
      blocks.add(const ContentBlock(type: BlockType.horizontalRule));
      return;
    }
    if (tag == 'img') {
      _addImage(element);
      return;
    }
    if (tag == 'figure') {
      final images = element.querySelectorAll('img');
      for (final image in images) {
        _addImage(image);
      }
      for (final caption in element.children.where(
        (child) => child.localName == 'figcaption',
      )) {
        _addTextElement(caption, BlockType.paragraph);
      }
      return;
    }
    if (tag == 'ul' || tag == 'ol') {
      _parseList(element, depth: listDepth, ordered: tag == 'ol');
      return;
    }
    if (tag == 'li') {
      _addListItem(element, depth: listDepth, ordered: false);
      return;
    }
    if (_directBlockTags.contains(tag)) {
      final loneImage = _loneImage(element);
      if (loneImage != null) {
        _addImage(loneImage, inheritedId: _elementId(element));
      } else {
        _addTextElement(element, _typeFor(tag));
      }
      return;
    }
    if (_containerTags.contains(tag)) {
      parseContainer(element, listDepth: listDepth);
    }
  }

  void _parseList(Element list, {required int depth, required bool ordered}) {
    final reversed = list.attributes.containsKey('reversed');
    var ordinal =
        int.tryParse(list.attributes['start'] ?? '') ??
        (reversed ? list.children.where((e) => e.localName == 'li').length : 1);
    for (final item in list.children.where(
      (child) => child.localName == 'li',
    )) {
      ordinal = int.tryParse(item.attributes['value'] ?? '') ?? ordinal;
      _addListItem(item, depth: depth, ordered: ordered, ordinal: ordinal);
      ordinal += reversed ? -1 : 1;
      for (final nested in item.children.where(
        (child) => child.localName == 'ul' || child.localName == 'ol',
      )) {
        _parseList(nested, depth: depth + 1, ordered: nested.localName == 'ol');
      }
    }
  }

  void _addListItem(
    Element item, {
    required int depth,
    required bool ordered,
    int ordinal = 1,
  }) {
    final contentNodes = item.nodes.where((node) {
      return node is! Element ||
          (node.localName != 'ul' && node.localName != 'ol');
    }).toList();
    _addTextBlock(
      BlockType.listItem,
      element: item,
      runs: _inlineRuns(contentNodes, _styleFor(item, const _RunStyle())),
      nestingLevel: depth,
      orderedList: ordered,
      listOrdinal: ordinal,
    );
  }

  void _addTextElement(Element element, BlockType type) {
    if (element.classes.contains('verse-heading')) {
      final spans = element.children
          .where((child) => child.localName == 'span')
          .toList();
      if (spans.length == 2) {
        final inherited = _styleFor(element, const _RunStyle());
        final leading = _inlineRuns(
          spans.first.nodes,
          _styleFor(spans.first, inherited),
        );
        final trailing = _inlineRuns(
          spans.last.nodes,
          _styleFor(spans.last, inherited),
        );
        _addTextBlock(
          type,
          element: element,
          runs: leading,
          trailingRuns: trailing,
          trailingDirection: _directionFor(
            spans.last,
            trailing.map((run) => run.text).join(),
          ),
        );
        return;
      }
    }
    final style = _styleFor(element, const _RunStyle());
    final runs = _inlineRuns(
      element.nodes,
      style,
      preserveWhitespace: type == BlockType.preformatted,
    );
    _addTextBlock(type, element: element, runs: runs);
  }

  void _addTextBlock(
    BlockType type, {
    Element? element,
    required List<InlineRun> runs,
    List<InlineRun> trailingRuns = const [],
    BlockTextDirection trailingDirection = BlockTextDirection.rtl,
    int nestingLevel = 0,
    bool orderedList = false,
    int listOrdinal = 1,
  }) {
    final text = [
      ...runs.map((run) => run.text),
      ...trailingRuns.map((run) => run.text),
    ].join();
    if (text.trim().isEmpty) return;
    final presentation = _presentationFor(element);
    blocks.add(
      ContentBlock(
        type: type,
        runs: runs,
        trailingRuns: trailingRuns,
        direction: _directionFor(element, text),
        trailingDirection: trailingDirection,
        alignment: _alignmentFor(element),
        nestingLevel: nestingLevel,
        orderedList: orderedList,
        listOrdinal: listOrdinal,
        id: element == null ? null : _elementId(element),
        fontSizeMultiplier: presentation.fontSizeMultiplier,
        lineHeight: presentation.lineHeight,
        spacingAfterEm: presentation.spacingAfterEm,
        textIndentEm: presentation.textIndentEm,
        forceBold: presentation.forceBold,
      ),
    );
  }

  void _addImage(Element image, {String? inheritedId}) {
    final source = image.attributes['src']?.trim();
    if (source == null || source.isEmpty) return;
    blocks.add(
      ContentBlock(
        type: BlockType.image,
        id: _elementId(image) ?? inheritedId,
        resourcePath: _resolveReference(resourceBasePath, source),
        alternateText: image.attributes['alt']?.trim(),
      ),
    );
  }

  List<InlineRun> _inlineRuns(
    Iterable<Node> nodes,
    _RunStyle inherited, {
    bool preserveWhitespace = false,
  }) {
    final raw = <InlineRun>[];
    for (final node in nodes) {
      _collectInline(
        node,
        inherited,
        raw,
        preserveWhitespace: preserveWhitespace,
      );
    }
    return _normalizeAndMerge(raw, preserveWhitespace: preserveWhitespace);
  }

  void _collectInline(
    Node node,
    _RunStyle inherited,
    List<InlineRun> output, {
    required bool preserveWhitespace,
  }) {
    if (node is Text) {
      output.add(inherited.toRun(node.data));
      return;
    }
    if (node is! Element) return;
    final tag = node.localName ?? '';
    if (_ignoredTags.contains(tag) || tag == 'ul' || tag == 'ol') return;
    if (tag == 'br') {
      output.add(inherited.toRun('\u2028'));
      return;
    }
    if (tag == 'img') {
      final alt = node.attributes['alt']?.trim();
      if (alt != null && alt.isNotEmpty) output.add(inherited.toRun(alt));
      return;
    }
    final style = _styleFor(node, inherited);
    for (final child in node.nodes) {
      _collectInline(
        child,
        style,
        output,
        preserveWhitespace: preserveWhitespace,
      );
    }
  }

  List<InlineRun> _normalizeAndMerge(
    List<InlineRun> runs, {
    required bool preserveWhitespace,
  }) {
    final merged = <InlineRun>[];
    for (final source in runs) {
      var text = source.text;
      if (!preserveWhitespace && text != '\u2028') {
        text = text.replaceAll(RegExp(r'\s+'), ' ');
      }
      text = text.replaceAll('\u2028', '\n');
      if (text.isEmpty) continue;
      if (merged.isNotEmpty && _sameStyle(merged.last, source)) {
        final previous = merged.removeLast();
        merged.add(previous.copyWith(text: previous.text + text));
      } else {
        merged.add(source.copyWith(text: text));
      }
    }
    if (!preserveWhitespace && merged.isNotEmpty) {
      merged[0] = merged.first.copyWith(text: merged.first.text.trimLeft());
      merged[merged.length - 1] = merged.last.copyWith(
        text: merged.last.text.trimRight(),
      );
      merged.removeWhere((run) => run.text.isEmpty);
    }
    return List<InlineRun>.unmodifiable(merged);
  }

  bool _sameStyle(InlineRun a, InlineRun b) =>
      a.bold == b.bold &&
      a.italic == b.italic &&
      a.code == b.code &&
      a.href == b.href &&
      a.language == b.language;

  _RunStyle _styleFor(Element element, _RunStyle inherited) {
    final tag = element.localName ?? '';
    var bold = inherited.bold || tag == 'strong' || tag == 'b';
    var italic = inherited.italic || tag == 'em' || tag == 'i';
    if (honorPublisherCss) {
      final css = _cssDeclarations(element.attributes['style']);
      final weight = css['font-weight']?.toLowerCase();
      final numericWeight = int.tryParse(weight ?? '');
      bold =
          bold ||
          weight == 'bold' ||
          (numericWeight != null && numericWeight >= 600);
      final fontStyle = css['font-style']?.toLowerCase();
      italic = italic || fontStyle == 'italic' || fontStyle == 'oblique';
    }
    return _RunStyle(
      bold: bold,
      italic: italic,
      code: inherited.code || tag == 'code' || tag == 'kbd' || tag == 'samp',
      href: tag == 'a'
          ? _resolveReference(resourceBasePath, element.attributes['href'])
          : inherited.href,
      language: _languageFor(element) ?? inherited.language,
    );
  }

  String? _languageFor(Element? element) {
    while (element != null) {
      final value =
          element.attributes['lang'] ?? element.attributes['xml:lang'];
      if (value != null) return value;
      element = element.parent;
    }
    return null;
  }

  BlockTextDirection _directionFor(Element? element, String text) {
    Element? current = element;
    while (current != null) {
      final explicit = current.attributes['dir']?.toLowerCase();
      if (explicit == 'rtl') return BlockTextDirection.rtl;
      if (explicit == 'ltr') return BlockTextDirection.ltr;
      current = current.parent;
    }
    return _bidi.directionFor(text);
  }

  BlockAlignment _alignmentFor(Element? element) {
    if (element == null || !honorPublisherCss) return BlockAlignment.start;
    var alignment =
        element.attributes['align']?.toLowerCase() ??
        _cssDeclarations(
          element.attributes['style'],
        )['text-align']?.toLowerCase();
    if (alignment == null) {
      Element? current = element;
      while (current != null && alignment == null) {
        if (current.classes.contains('hebrew') ||
            current.classes.contains('note-he')) {
          alignment = 'right';
        } else if (current.classes.contains('translation') ||
            current.classes.contains('note-en') ||
            current.classes.contains('note-title')) {
          alignment = 'left';
        }
        current = current.parent;
      }
    }
    return switch (alignment) {
      'center' => BlockAlignment.center,
      'left' => BlockAlignment.left,
      'right' => BlockAlignment.right,
      'end' => BlockAlignment.end,
      'justify' => BlockAlignment.justify,
      _ => BlockAlignment.start,
    };
  }

  _BlockPresentation _presentationFor(Element? element) {
    if (element == null) return const _BlockPresentation();
    final isVerseHeading = element.classes.contains('verse-heading');
    final isNoteTitle = element.classes.contains('note-title');
    if (!honorPublisherCss) {
      return _BlockPresentation(forceBold: isVerseHeading || isNoteTitle);
    }

    var inTanach = false;
    var inHebrewNote = false;
    var inEnglishNote = false;
    Element? current = element;
    while (current != null) {
      inTanach =
          inTanach ||
          current.classes.contains('verse') ||
          current.classes.contains('commentary-note');
      inHebrewNote = inHebrewNote || current.classes.contains('note-he');
      inEnglishNote = inEnglishNote || current.classes.contains('note-en');
      current = current.parent;
    }
    if (!inTanach && !isVerseHeading && !isNoteTitle) {
      return const _BlockPresentation();
    }

    final classes = element.classes;
    final isHebrew = classes.contains('hebrew') || inHebrewNote;
    final isTranslation = classes.contains('translation');
    final isEnglish = isTranslation || inEnglishNote;
    final isNoteParagraph = classes.contains('note-paragraph');
    return _BlockPresentation(
      fontSizeMultiplier: isVerseHeading
          ? 1.15
          : isNoteTitle
          ? 0.8
          : null,
      lineHeight: isNoteTitle
          ? 1.45
          : isHebrew
          ? 1.8
          : isEnglish
          ? 1.65
          : null,
      spacingAfterEm: isVerseHeading
          ? 0.35
          : isNoteTitle
          ? 0.7
          : isNoteParagraph
          ? 0.65
          : classes.contains('hebrew')
          ? 0.4
          : isTranslation
          ? 0.55
          : null,
      textIndentEm: inTanach ? 0 : null,
      forceBold: isVerseHeading || isNoteTitle,
    );
  }

  Map<String, String> _cssDeclarations(String? style) {
    if (style == null) return const {};
    final result = <String, String>{};
    for (final declaration in style.split(';')) {
      final separator = declaration.indexOf(':');
      if (separator <= 0) continue;
      result[declaration.substring(0, separator).trim().toLowerCase()] =
          declaration.substring(separator + 1).trim();
    }
    return result;
  }

  Element? _loneImage(Element element) {
    final images = element.querySelectorAll('img');
    if (images.length != 1) return null;
    final textWithoutAlt = element.text.trim();
    return textWithoutAlt.isEmpty ? images.single : null;
  }

  String? _elementId(Element element) {
    final own = element.id.trim();
    if (own.isNotEmpty) return own;
    final namedAnchor = element.querySelector('[id], a[name]');
    final nestedId = namedAnchor?.id.trim();
    if (nestedId != null && nestedId.isNotEmpty) return nestedId;
    final name = namedAnchor?.attributes['name']?.trim();
    return name == null || name.isEmpty ? null : name;
  }

  BlockType _typeFor(String tag) => switch (tag) {
    'h1' => BlockType.heading1,
    'h2' => BlockType.heading2,
    'h3' => BlockType.heading3,
    'h4' => BlockType.heading4,
    'h5' => BlockType.heading5,
    'h6' => BlockType.heading6,
    'blockquote' => BlockType.blockquote,
    'pre' => BlockType.preformatted,
    _ => BlockType.paragraph,
  };
}

class _BlockPresentation {
  final double? fontSizeMultiplier;
  final double? lineHeight;
  final double? spacingAfterEm;
  final double? textIndentEm;
  final bool forceBold;

  const _BlockPresentation({
    this.fontSizeMultiplier,
    this.lineHeight,
    this.spacingAfterEm,
    this.textIndentEm,
    this.forceBold = false,
  });
}

class _RunStyle {
  final bool bold;
  final bool italic;
  final bool code;
  final String? href;
  final String? language;

  const _RunStyle({
    this.bold = false,
    this.italic = false,
    this.code = false,
    this.href,
    this.language,
  });

  InlineRun toRun(String text) => InlineRun(
    text: text,
    bold: bold,
    italic: italic,
    code: code,
    href: href,
    language: language,
  );
}

String _resolveReference(String basePath, String? reference) {
  if (reference == null || reference.trim().isEmpty) return '';
  final value = reference.trim();
  final uri = Uri.tryParse(value);
  if (uri != null && (uri.hasScheme || value.startsWith('#'))) return value;
  if (basePath.isEmpty) return value;
  final base = Uri(path: basePath.endsWith('/') ? basePath : '$basePath/');
  final resolved = base.resolve(value);
  final path = Uri.decodeComponent(resolved.path);
  return resolved.fragment.isEmpty ? path : '$path#${resolved.fragment}';
}

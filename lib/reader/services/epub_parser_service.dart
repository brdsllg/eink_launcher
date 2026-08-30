import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;
import 'package:xml/xml.dart';

import '../models/content_block.dart';
import '../models/parsed_book.dart';
import '../models/reading_position.dart';
import '../models/toc_entry.dart';
import 'html_block_parser.dart';

class EpubParserService {
  const EpubParserService();

  Future<ParsedBook> parseFile(
    String path, {
    bool honorPublisherCss = true,
  }) async {
    final bytes = await File(path).readAsBytes();
    return parseBytes(bytes, honorPublisherCss: honorPublisherCss);
  }

  Future<ParsedBook> parseBytes(
    Uint8List bytes, {
    bool honorPublisherCss = true,
  }) {
    return Isolate.run(
      () => parseBytesSync(bytes, honorPublisherCss: honorPublisherCss),
    );
  }

  static ParsedBook parseBytesSync(
    Uint8List bytes, {
    bool honorPublisherCss = true,
  }) {
    final archive = _decodeArchive(bytes);
    final containerXml = _readText(
      archive,
      'META-INF/container.xml',
      description: 'EPUB container',
    );
    final container = _parseXml(containerXml, 'EPUB container');
    final rootfile = _elements(container, 'rootfile').firstOrNull;
    final packagePath = rootfile == null
        ? null
        : _attribute(rootfile, 'full-path')?.trim();
    if (packagePath == null || packagePath.isEmpty) {
      throw const FormatException('EPUB container has no package document.');
    }

    final packageXml = _readText(
      archive,
      packagePath,
      description: 'EPUB package document',
    );
    final package = _parseXml(packageXml, 'EPUB package document');
    final manifest = <String, _ManifestItem>{};
    for (final item in _elements(package, 'item')) {
      final id = _attribute(item, 'id')?.trim();
      final href = _attribute(item, 'href')?.trim();
      final mediaType = _attribute(item, 'media-type')?.trim();
      if (id == null || id.isEmpty || href == null || href.isEmpty) continue;
      manifest[id] = _ManifestItem(
        id: id,
        href: href,
        resolvedPath: _resolveArchivePath(packagePath, href),
        mediaType: mediaType ?? '',
        properties: (_attribute(item, 'properties') ?? '')
            .split(RegExp(r'\s+'))
            .where((value) => value.isNotEmpty)
            .toSet(),
      );
    }

    final spineElement = _elements(package, 'spine').firstOrNull;
    if (spineElement == null) {
      throw const FormatException('EPUB package has no reading spine.');
    }
    final spineRefs = _childElements(spineElement, 'itemref')
        .map((item) => _attribute(item, 'idref')?.trim())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toList();
    if (spineRefs.isEmpty) {
      throw const FormatException('EPUB reading spine is empty.');
    }

    final spine = <ParsedSpineItem>[];
    for (final idref in spineRefs) {
      final item = manifest[idref];
      if (item == null) continue;
      final xhtml = _readText(
        archive,
        item.resolvedPath,
        description: 'spine item ${item.href}',
      );
      final blocks = HtmlBlockParser.parseSync(
        xhtml,
        honorPublisherCss: honorPublisherCss,
        resourceBasePath: _directoryOf(item.resolvedPath),
      );
      final anchors = <String, int>{};
      for (var index = 0; index < blocks.length; index++) {
        final id = blocks[index].id;
        if (id != null && id.isNotEmpty) anchors.putIfAbsent(id, () => index);
      }
      spine.add(
        ParsedSpineItem(
          id: item.id,
          href: item.resolvedPath,
          title: _firstHeading(blocks),
          blocks: blocks,
          anchors: Map<String, int>.unmodifiable(anchors),
        ),
      );
    }
    if (spine.isEmpty) {
      throw const FormatException('EPUB spine contains no readable documents.');
    }

    final resources = <String, Uint8List>{};
    final spinePaths = spine.map((item) => item.href).toSet();
    for (final item in manifest.values) {
      if (spinePaths.contains(item.resolvedPath) ||
          item.properties.contains('nav') ||
          item.mediaType == 'application/x-dtbncx+xml') {
        continue;
      }
      final file = archive.findFile(item.resolvedPath);
      if (file != null && file.isFile) {
        resources[item.resolvedPath] = Uint8List.fromList(file.content);
      }
    }

    final navItem = manifest.values
        .where((item) => item.properties.contains('nav'))
        .firstOrNull;
    List<TocEntry> toc = const [];
    if (navItem != null) {
      toc = _parseNavigationDocument(archive, navItem, spine);
    }
    if (toc.isEmpty) {
      final ncxId = _attribute(spineElement, 'toc')?.trim();
      final ncxItem = ncxId == null
          ? manifest.values
                .where((item) => item.mediaType == 'application/x-dtbncx+xml')
                .firstOrNull
          : manifest[ncxId];
      if (ncxItem != null) toc = _parseNcx(archive, ncxItem, spine);
    }
    if (toc.isEmpty) toc = _fallbackToc(spine);

    return ParsedBook(
      title: _metadataText(package, 'title') ?? 'Untitled',
      author: _metadataText(package, 'creator'),
      language: _metadataText(package, 'language'),
      spine: List<ParsedSpineItem>.unmodifiable(spine),
      resources: Map<String, Uint8List>.unmodifiable(resources),
      tableOfContents: List<TocEntry>.unmodifiable(toc),
    );
  }
}

Archive _decodeArchive(Uint8List bytes) {
  try {
    return ZipDecoder().decodeBytes(bytes);
  } catch (error) {
    throw FormatException('Invalid EPUB ZIP container: $error');
  }
}

XmlDocument _parseXml(String source, String description) {
  try {
    return XmlDocument.parse(source);
  } catch (error) {
    throw FormatException('Malformed $description: $error');
  }
}

String _readText(Archive archive, String path, {required String description}) {
  final file = archive.findFile(_normalizeArchivePath(path));
  if (file == null || !file.isFile) {
    throw FormatException('Missing $description at $path.');
  }
  return utf8.decode(file.content, allowMalformed: true);
}

List<TocEntry> _parseNavigationDocument(
  Archive archive,
  _ManifestItem item,
  List<ParsedSpineItem> spine,
) {
  final source = _readText(
    archive,
    item.resolvedPath,
    description: 'EPUB navigation document',
  );
  final document = html_parser.parse(source);
  html_dom.Element? tocNav;
  for (final nav in document.querySelectorAll('nav')) {
    final type = nav.attributes['epub:type'] ?? nav.attributes['type'] ?? '';
    final role = nav.attributes['role'] ?? '';
    if (type.split(RegExp(r'\s+')).contains('toc') || role == 'doc-toc') {
      tocNav = nav;
      break;
    }
  }
  tocNav ??= document.querySelector('nav');
  if (tocNav == null) return const [];
  final rootList = tocNav.children
      .where((child) => child.localName == 'ol')
      .firstOrNull;
  if (rootList == null) return const [];
  return _parseNavList(
    rootList,
    navDocumentPath: item.resolvedPath,
    spine: spine,
    level: 0,
  );
}

List<TocEntry> _parseNavList(
  html_dom.Element list, {
  required String navDocumentPath,
  required List<ParsedSpineItem> spine,
  required int level,
}) {
  final entries = <TocEntry>[];
  for (final li in list.children.where((child) => child.localName == 'li')) {
    final anchor = li.children
        .where((child) => child.localName == 'a')
        .firstOrNull;
    final labelElement =
        anchor ??
        li.children.where((child) => child.localName == 'span').firstOrNull;
    final title = labelElement?.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    final href = anchor?.attributes['href']?.trim();
    final target = href == null || href.isEmpty
        ? null
        : _resolveArchiveReference(navDocumentPath, href);
    final nested = li.children
        .where((child) => child.localName == 'ol')
        .firstOrNull;
    final children = nested == null
        ? const <TocEntry>[]
        : _parseNavList(
            nested,
            navDocumentPath: navDocumentPath,
            spine: spine,
            level: level + 1,
          );
    if (title != null && title.isNotEmpty) {
      entries.add(
        TocEntry(
          title: title,
          level: level,
          position: target == null ? null : _positionFor(target, spine),
          targetHref: target,
          children: children,
        ),
      );
    } else {
      entries.addAll(children);
    }
  }
  return entries;
}

List<TocEntry> _parseNcx(
  Archive archive,
  _ManifestItem item,
  List<ParsedSpineItem> spine,
) {
  final source = _readText(
    archive,
    item.resolvedPath,
    description: 'EPUB NCX document',
  );
  final document = _parseXml(source, 'EPUB NCX document');
  final navMap = _elements(document, 'navMap').firstOrNull;
  if (navMap == null) return const [];
  return _parseNcxPoints(
    navMap,
    ncxPath: item.resolvedPath,
    spine: spine,
    level: 0,
  );
}

List<TocEntry> _parseNcxPoints(
  XmlElement parent, {
  required String ncxPath,
  required List<ParsedSpineItem> spine,
  required int level,
}) {
  final entries = <TocEntry>[];
  for (final point in _childElements(parent, 'navPoint')) {
    final label = _childElements(point, 'navLabel').firstOrNull;
    final title = label == null
        ? null
        : _elements(label, 'text').firstOrNull?.innerText.trim();
    final content = _childElements(point, 'content').firstOrNull;
    final source = content == null ? null : _attribute(content, 'src')?.trim();
    final target = source == null || source.isEmpty
        ? null
        : _resolveArchiveReference(ncxPath, source);
    final children = _parseNcxPoints(
      point,
      ncxPath: ncxPath,
      spine: spine,
      level: level + 1,
    );
    if (title != null && title.isNotEmpty) {
      entries.add(
        TocEntry(
          title: title,
          level: level,
          position: target == null ? null : _positionFor(target, spine),
          targetHref: target,
          children: children,
        ),
      );
    } else {
      entries.addAll(children);
    }
  }
  return entries;
}

List<TocEntry> _fallbackToc(List<ParsedSpineItem> spine) {
  return List<TocEntry>.generate(spine.length, (index) {
    final item = spine[index];
    return TocEntry(
      title: item.title ?? 'Chapter ${index + 1}',
      position: TextReadingPosition(
        spineIndex: index,
        blockIndex: 0,
        charOffset: 0,
      ),
      targetHref: item.href,
    );
  });
}

TextReadingPosition? _positionFor(String target, List<ParsedSpineItem> spine) {
  final hash = target.indexOf('#');
  final path = _normalizeArchivePath(
    hash < 0 ? target : target.substring(0, hash),
  );
  final fragment = hash < 0
      ? null
      : Uri.decodeComponent(target.substring(hash + 1));
  final spineIndex = spine.indexWhere((item) => item.href == path);
  if (spineIndex < 0) return null;
  final blockIndex = fragment == null || fragment.isEmpty
      ? 0
      : spine[spineIndex].anchors[fragment] ?? 0;
  return TextReadingPosition(
    spineIndex: spineIndex,
    blockIndex: blockIndex,
    charOffset: 0,
  );
}

String? _metadataText(XmlDocument package, String localName) {
  final value = _elements(package, localName).firstOrNull?.innerText.trim();
  return value == null || value.isEmpty ? null : value;
}

String? _firstHeading(List<ContentBlock> blocks) {
  for (final block in blocks) {
    if (switch (block.type) {
      BlockType.heading1 ||
      BlockType.heading2 ||
      BlockType.heading3 ||
      BlockType.heading4 ||
      BlockType.heading5 ||
      BlockType.heading6 => true,
      _ => false,
    }) {
      final text = block.plainText.trim();
      if (text.isNotEmpty) return text;
    }
  }
  return null;
}

Iterable<XmlElement> _elements(XmlNode node, String localName) =>
    node.descendantElements.where((element) => element.name.local == localName);

Iterable<XmlElement> _childElements(XmlNode node, String localName) => node
    .children
    .whereType<XmlElement>()
    .where((element) => element.name.local == localName);

String? _attribute(XmlElement element, String localName) {
  for (final attribute in element.attributes) {
    if (attribute.name.local == localName) return attribute.value;
  }
  return null;
}

String _resolveArchivePath(String documentPath, String reference) {
  return _resolveArchiveReference(documentPath, reference).split('#').first;
}

String _resolveArchiveReference(String documentPath, String reference) {
  final value = reference.replaceAll('\\', '/');
  if (value.startsWith('#')) {
    return '${_normalizeArchivePath(documentPath)}$value';
  }
  final base = Uri(path: '${_directoryOf(documentPath)}/');
  final resolved = base.resolve(value);
  final path = _normalizeArchivePath(Uri.decodeComponent(resolved.path));
  return resolved.fragment.isEmpty ? path : '$path#${resolved.fragment}';
}

String _directoryOf(String path) {
  final normalized = _normalizeArchivePath(path);
  final slash = normalized.lastIndexOf('/');
  return slash < 0 ? '' : normalized.substring(0, slash);
}

String _normalizeArchivePath(String path) {
  final parts = <String>[];
  for (final part in path.replaceAll('\\', '/').split('/')) {
    if (part.isEmpty || part == '.') continue;
    if (part == '..') {
      if (parts.isNotEmpty) parts.removeLast();
    } else {
      parts.add(part);
    }
  }
  return parts.join('/');
}

class _ManifestItem {
  final String id;
  final String href;
  final String resolvedPath;
  final String mediaType;
  final Set<String> properties;

  const _ManifestItem({
    required this.id,
    required this.href,
    required this.resolvedPath,
    required this.mediaType,
    required this.properties,
  });
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}

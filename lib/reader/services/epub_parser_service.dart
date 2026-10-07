import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

import '../models/reader_settings.dart';
import '../models/tehillim_daily.dart';
import 'tanach_layout_service.dart';

import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;
import 'package:xml/xml.dart';

import '../models/content_block.dart';
import '../models/parsed_book.dart';
import '../models/reading_position.dart';
import '../models/reader_exception.dart';
import '../models/toc_entry.dart';
import 'html_block_parser.dart';

class EpubParserService {
  const EpubParserService();

  Future<ParsedBook> parseFile(
    String path, {
    bool honorPublisherCss = true,
    bool projectStudy = true,
  }) async {
    final bytes = await File(path).readAsBytes();
    return parseBytes(
      bytes,
      honorPublisherCss: honorPublisherCss,
      projectStudy: projectStudy,
    );
  }

  Future<ParsedBook> parseBytes(
    Uint8List bytes, {
    bool honorPublisherCss = true,
    bool projectStudy = true,
  }) {
    return Isolate.run(
      () => parseBytesSync(
        bytes,
        honorPublisherCss: honorPublisherCss,
        projectStudy: projectStudy,
      ),
    );
  }

  static ParsedBook parseBytesSync(
    Uint8List bytes, {
    bool honorPublisherCss = true,
    bool projectStudy = true,
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

    final obfuscatedFonts = _checkEncryption(archive, manifest, spineRefs);

    final xhtmlDocuments = <String, String>{};
    for (final item in manifest.values.where(
      (item) => item.mediaType == 'application/xhtml+xml',
    )) {
      if (!spineRefs.contains(item.id) &&
          archive.findFile(item.resolvedPath) == null) {
        continue;
      }
      xhtmlDocuments[item.resolvedPath] = _readText(
        archive,
        item.resolvedPath,
        description: 'XHTML resource',
      );
    }
    final studyPaths = {
      for (final entry in xhtmlDocuments.entries)
        if (entry.value.contains('data-ref') &&
            TanachLayoutService.recognizes(entry.value))
          entry.key,
    };
    final hasStudy = studyPaths.isNotEmpty;
    final studyUnit = !hasStudy
        ? null
        : studyPaths.any(
                (path) => TanachLayoutService.usesSegments(xhtmlDocuments[path]!),
              )
        ? 'segment'
        : 'verse';
    final spine = <ParsedSpineItem>[];
    for (final idref in spineRefs) {
      final item = manifest[idref];
      if (item == null) continue;
      final xhtml =
          xhtmlDocuments[item.resolvedPath] ??
          _readText(
            archive,
            item.resolvedPath,
            description: 'spine item ${item.href}',
          );
      if (studyPaths.contains(item.resolvedPath)) {
        spine.add(
          ParsedSpineItem(
            id: item.id,
            href: item.resolvedPath,
            title: _firstHeadingInSource(xhtml),
            blocks: const [],
          ),
        );
        continue;
      }
      final anchors = <String, int>{};
      final blocks = HtmlBlockParser.parseSync(
        xhtml,
        anchors: anchors,
        honorPublisherCss: honorPublisherCss,
        resourceBasePath: _directoryOf(item.resolvedPath),
      );
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
          obfuscatedFonts.contains(item.resolvedPath) ||
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
      try {
        toc = _parseNavigationDocument(archive, navItem, spine);
      } on FormatException {
        // Navigation is optional; intact reading content remains usable.
      }
    }
    if (toc.isEmpty) {
      final ncxId = _attribute(spineElement, 'toc')?.trim();
      final ncxItem = ncxId == null
          ? manifest.values
                .where((item) => item.mediaType == 'application/x-dtbncx+xml')
                .firstOrNull
          : manifest[ncxId];
      if (ncxItem != null) {
        try {
          toc = _parseNcx(archive, ncxItem, spine);
        } on FormatException {
          // Fall back to headings when publisher navigation is damaged.
        }
      }
    }
    if (toc.isEmpty) toc = _fallbackToc(spine);

    var parshaToc = const <TocEntry>[];
    if (navItem != null) {
      try {
        parshaToc = _parseParshaNavigation(archive, navItem, spine);
      } on FormatException {
        // A missing alternate navigation only removes the toggle.
      }
    }

    var tehillimToc = const <TocEntry>[];
    if (navItem != null) {
      try {
        tehillimToc = _parseTehillimNavigation(archive, navItem, spine);
      } on FormatException {
        // A missing alternate navigation only removes the toggle.
      }
    }
    final title = _metadataText(package, 'title') ?? 'Untitled';
    if (tehillimToc.isEmpty) {
      tehillimToc = _synthesizedTehillimToc(
        toc,
        spine,
        title: title,
        studySources: hasStudy ? xhtmlDocuments : const {},
      );
    }

    final parsed = ParsedBook(
      studyDocuments: hasStudy ? xhtmlDocuments : const {},
      contentFingerprint: sha256.convert(bytes).toString(),
      studyUnit: studyUnit,
      rightToLeft:
          _attribute(spineElement, 'page-progression-direction') == 'rtl',
      title: title,
      author: _metadataText(package, 'creator'),
      language: _metadataText(package, 'language'),
      spine: List<ParsedSpineItem>.unmodifiable(spine),
      resources: Map<String, Uint8List>.unmodifiable(resources),
      tableOfContents: List<TocEntry>.unmodifiable(toc),
      parshaTableOfContents: List<TocEntry>.unmodifiable(parshaToc),
      tehillimDailyTableOfContents: List<TocEntry>.unmodifiable(tehillimToc),
    );
    return hasStudy && projectStudy
        ? TanachLayoutService.layout(
            parsed,
            ReaderSettings(honorPublisherCss: honorPublisherCss),
          )
        : parsed;
  }
}

// See https://www.w3.org/TR/epub-33/#sec-container-metainf-encryption.xml
// CipherReference paths are rooted at the container, not META-INF or the OPF.
Set<String> _checkEncryption(
  Archive archive,
  Map<String, _ManifestItem> manifest,
  List<String> spineRefs,
) {
  if (archive.findFile('META-INF/encryption.xml') == null) return const {};
  final encryption = _parseXml(
    _readText(
      archive,
      'META-INF/encryption.xml',
      description: 'EPUB encryption metadata',
    ),
    'EPUB encryption metadata',
  );
  if (encryption.rootElement.name.local != 'encryption') {
    throw const FormatException('Invalid EPUB encryption metadata.');
  }
  final spinePaths = {
    for (final id in spineRefs)
      if (manifest[id] != null) manifest[id]!.resolvedPath,
  };
  final ignoredFonts = <String>{};
  for (final entry in _elements(encryption, 'EncryptedData')) {
    final methods = _childElements(entry, 'EncryptionMethod').toList();
    final references = _elements(entry, 'CipherReference').toList();
    if (methods.length != 1 || references.length != 1) {
      throw const FormatException('Incomplete EPUB encryption metadata.');
    }
    final algorithm = _attribute(methods.single, 'Algorithm')?.trim();
    final reference = _attribute(references.single, 'URI')?.trim();
    if (algorithm == null ||
        algorithm.isEmpty ||
        reference == null ||
        reference.isEmpty) {
      throw const FormatException('Incomplete EPUB encryption metadata.');
    }
    final uri = Uri.parse(reference);
    if (uri.hasScheme || uri.hasAuthority || uri.hasQuery || uri.hasFragment) {
      throw const FormatException('Invalid encrypted EPUB resource path.');
    }
    final path = _resolveArchivePath('', reference);
    final items = manifest.values
        .where((item) => item.resolvedPath == path)
        .toList();
    final isFont =
        items.isNotEmpty &&
        items.every((item) => _fontMediaTypes.contains(item.mediaType));
    final isObfuscation =
        algorithm == 'http://www.idpf.org/2008/embedding' ||
        algorithm == 'http://ns.adobe.com/pdf/enc#RC';
    if (isObfuscation && isFont && !spinePaths.contains(path)) {
      // Publisher fonts are never used by this reader. Keep using bundled
      // fonts and do not retain or attempt to decode their obfuscated bytes.
      ignoredFonts.add(path);
      continue;
    }
    throw EncryptedEpubException(resourcePath: path, algorithm: algorithm);
  }
  return ignoredFonts;
}

const _fontMediaTypes = {
  'font/otf',
  'font/ttf',
  'font/woff',
  'font/woff2',
  'application/font-sfnt',
  'application/font-woff',
  'application/vnd.ms-opentype',
  'application/x-font-ttf',
  'application/x-font-opentype',
};

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

/// The Parshah/Aliyah navigation list of a dual-structure Torah book.
///
/// Only the five books of the Torah carry this second list, and EPUB allows
/// exactly one nav with the `toc` semantic, so it ships as `epub:type="other"`.
List<TocEntry> _parseParshaNavigation(
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
  final nav = document.querySelector('nav#parsha-toc');
  if (nav == null) return const [];
  final rootList = nav.children
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

/// The 30-day Tehillim navigation list of Psalms.
///
/// Only Psalms carries this second list, and EPUB allows exactly one nav
/// with the `toc` semantic, so it ships as `epub:type="other"`.
List<TocEntry> _parseTehillimNavigation(
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
  final nav = document.querySelector('nav#tehillim-toc');
  if (nav == null) return const [];
  final rootList = nav.children
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

/// Builds Day parents from the chapter table of contents when the nav
/// document carries no `tehillim-toc` but the book looks like Psalms with
/// 150 chapters. Old EPUBs and sidecars still get Days this way; the reader
/// injects matching day headings at layout time.
List<TocEntry> _synthesizedTehillimToc(
  List<TocEntry> chapterToc,
  List<ParsedSpineItem> spine, {
  required String title,
  required Map<String, String> studySources,
}) {
  final flat = <TocEntry>[];
  void collect(TocEntry entry) {
    flat.add(entry);
    for (final child in entry.children) {
      collect(child);
    }
  }

  for (final entry in chapterToc) {
    collect(entry);
  }
  final chapterPattern = RegExp(r'chapter-(\d+)\.xhtml');
  final byChapter = <int, TocEntry>{};
  for (final entry in flat) {
    final target = entry.targetHref ?? '';
    final match = chapterPattern.firstMatch(target);
    var chapter = match == null ? null : int.tryParse(match.group(1)!);
    chapter ??= _chapterFromTitle(entry.title);
    if (chapter != null &&
        chapter >= 1 &&
        chapter <= 150 &&
        !byChapter.containsKey(chapter)) {
      byChapter[chapter] = entry;
    }
  }
  // Also try the spine when the TOC itself is a fallback without hrefs.
  if (byChapter.length < 150) {
    for (final item in spine) {
      final match = chapterPattern.firstMatch(item.href);
      if (match == null) continue;
      final chapter = int.tryParse(match.group(1)!);
      if (chapter == null ||
          chapter < 1 ||
          chapter > 150 ||
          byChapter.containsKey(chapter)) {
        continue;
      }
      byChapter[chapter] = TocEntry(
        title: '$title $chapter',
        level: 0,
        targetHref: item.href,
        position: _positionFor(item.href, spine),
      );
    }
  }
  if (byChapter.length < 150) return const [];
  for (var chapter = 1; chapter <= 150; chapter++) {
    if (!byChapter.containsKey(chapter)) return const [];
  }
  final lower = title.toLowerCase();
  final titleLooksLikePsalms =
      lower.contains('psalm') || lower.contains('tehill') || lower.contains('תהל');
  var refsLookLikePsalms = false;
  for (final source in studySources.values) {
    final probe = source.toLowerCase();
    if (probe.contains('psalm') ||
        probe.contains('tehill') ||
        probe.contains('תהל')) {
      refsLookLikePsalms = true;
      break;
    }
    if (source.contains('data-ref')) {
      refsLookLikePsalms = true;
      break;
    }
  }
  if (!titleLooksLikePsalms && !refsLookLikePsalms && studySources.isNotEmpty) {
    // A non-Psalms 150-chapter book must not gain a daily schedule.
    // When there are no study sources to inspect (plain EPUB fallback),
    // still require the title to look like Psalms.
    if (studySources.isEmpty) return const [];
  }
  if (!titleLooksLikePsalms && byChapter.values.every(
    (entry) =>
        !_chapterTitleLooksLikePsalms(entry.title) &&
        !((entry.targetHref ?? '').toLowerCase().contains('psalm')),
  )) {
    // Without any Psalms signal in titles, only synthesize when the book
    // title itself says Psalms/Tehillim.
    return const [];
  }

  final days = <TocEntry>[];
  for (var day = 1; day <= 30; day++) {
    final chapters = TehillimDaily.dayChapters[day - 1];
    final firstChapter = day == 26
        ? 119
        : chapters.first;
    final firstEntry = byChapter[firstChapter]!;
    final base = (firstEntry.targetHref ?? '').split('#').first;
    final parentTarget = base.isEmpty ? null : '$base#tehillim-day-$day';
    final children = <TocEntry>[];
    for (final chapter in chapters) {
      final chapterEntry = byChapter[chapter]!;
      final chapterBase =
          (chapterEntry.targetHref ?? '').split('#').first;
      String? childTarget = chapterEntry.targetHref;
      TextReadingPosition? childPosition = chapterEntry.position
          is TextReadingPosition
          ? chapterEntry.position as TextReadingPosition
          : null;
      if (day == 25 && chapter == 119) {
        // Day 25 opens Psalm 119 at verse 1 (chapter start).
        childTarget = chapterBase.isEmpty
            ? null
            : '$chapterBase#tehillim-day-25';
        childPosition = childTarget == null
            ? childPosition
            : _positionFor(childTarget, spine) ?? childPosition;
      } else if (day == 26 && chapter == 119) {
        // Day 26 opens Psalm 119 at verse 97. Prefer the verse anchor when
        // the study source reveals its id; otherwise the injected day anchor
        // (which the layout places before verse 97) still navigates there.
        final verseAnchor = _verseAnchorFor(
          studySources,
          chapterBase,
          chapter: 119,
          verse: 97,
        );
        childTarget = chapterBase.isEmpty
            ? null
            : '$chapterBase#${verseAnchor ?? 'tehillim-day-26'}';
        childPosition = childTarget == null
            ? childPosition
            : _positionFor(childTarget, spine) ?? childPosition;
      }
      children.add(
        TocEntry(
          title: chapterEntry.title,
          level: 1,
          position: childPosition,
          targetHref: childTarget,
          children: const [],
        ),
      );
    }
    final parentPosition = parentTarget == null
        ? firstEntry.position
        : _positionFor(parentTarget, spine) ?? firstEntry.position;
    days.add(
      TocEntry(
        title: 'Day $day',
        level: 0,
        position: parentPosition,
        targetHref: parentTarget,
        children: children,
      ),
    );
  }
  return days;
}

int? _chapterFromTitle(String title) {
  final match = RegExp(r'(\d+)\s*$').firstMatch(title.trim());
  if (match == null) return null;
  return int.tryParse(match.group(1)!);
}

bool _chapterTitleLooksLikePsalms(String title) {
  final lower = title.toLowerCase();
  return lower.contains('psalm') ||
      lower.contains('tehill') ||
      lower.contains('תהל');
}

/// Finds the element id of `chapter:verse` inside the study XHTML for
/// [chapterBase], so Day 26 can point at Psalm 119:97 even in legacy EPUBs
/// whose verse id scheme differs from the current builder.
String? _verseAnchorFor(
  Map<String, String> studySources,
  String chapterBase, {
  required int chapter,
  required int verse,
}) {
  String? key;
  for (final entry in studySources.keys) {
    if (entry == chapterBase || entry.endsWith('/$chapterBase')) {
      key = entry;
      break;
    }
  }
  key ??= studySources.keys
      .where((entry) => entry.endsWith('chapter-$chapter.xhtml'))
      .cast<String?>()
      .firstOrNull;
  if (key == null) return null;
  final source = studySources[key]!;
  final document = html_parser.parse(source);
  for (final section in document.querySelectorAll(
    'section.verse[data-ref], section.segment[data-ref]',
  )) {
    final ref = section.attributes['data-ref'] ?? '';
    final refMatch = RegExp(r':(\d+)\s*$').firstMatch(ref.trim());
    if (refMatch != null &&
        int.tryParse(refMatch.group(1)!) == verse &&
        section.id.isNotEmpty) {
      return section.id;
    }
  }
  // Fall back to the builder's conventional verse id when the source uses
  // it (new EPUBs): v-psalms-119-97.
  final conventional = RegExp(
    'id="(v-[a-z0-9-]+-$chapter-$verse)"',
  ).firstMatch(source);
  return conventional?.group(1);
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
    documentPath: path,
    blockId: fragment,
    spineIndex: spineIndex,
    blockIndex: blockIndex,
    charOffset: 0,
  );
}

String? _metadataText(XmlDocument package, String localName) {
  final value = _elements(package, localName).firstOrNull?.innerText.trim();
  return value == null || value.isEmpty ? null : value;
}

String? _firstHeadingInSource(String source) {
  final match = RegExp(
    r'<h[1-6]\b[^>]*>.*?</h[1-6]\s*>',
    caseSensitive: false,
    dotAll: true,
  ).firstMatch(source);
  if (match == null) return null;
  final value = html_parser.parseFragment(match.group(0)!).text?.trim();
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

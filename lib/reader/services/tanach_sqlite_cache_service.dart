import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import '../models/content_block.dart';
import '../models/doc_ref.dart';
import '../models/parsed_book.dart';
import '../models/reader_settings.dart';
import '../models/toc_entry.dart';
import 'tanach_layout_service.dart';

/// A disposable, per-book SQLite cache for the large structured Tanach EPUBs.
///
/// Raw chapter XHTML is compressed. Chapters are projected into render blocks
/// only when requested, while normalized text selects substring search candidates.
/// User state deliberately remains outside this database.
class TanachSqliteCacheService {
  static const schemaVersion = 3;
  static const maxCacheBytes = 768 * 1024 * 1024;

  static final Map<String, int> _pins = {};
  static String _pathKey(String path) => File(path).absolute.uri.toString();

  static void retain(String path) {
    final key = _pathKey(path);
    _pins.update(key, (n) => n + 1, ifAbsent: () => 1);
  }

  static void release(String path) {
    final key = _pathKey(path);
    final count = _pins[key] ?? 0;
    if (count <= 1) {
      _pins.remove(key);
    } else {
      _pins[key] = count - 1;
    }
  }

  final Directory? cacheDirectory;
  final int cacheByteLimit;

  const TanachSqliteCacheService({
    this.cacheDirectory,
    this.cacheByteLimit = maxCacheBytes,
  });

  Future<Directory> _directory() async =>
      cacheDirectory ??
      Directory('${(await getApplicationCacheDirectory()).path}/tanach_sqlite');

  Future<File> databaseFile(DocRef doc) async {
    final key = sha256.convert(utf8.encode(doc.id)).toString();
    return File('${(await _directory()).path}/$key.sqlite');
  }

  Future<ParsedBook?> loadIfCurrent(
    DocRef doc, {
    required String fingerprint,
  }) async {
    final file = await databaseFile(doc);
    if (!await file.exists()) return null;
    try {
      return await Isolate.run(
        () => _readSkeleton(file.path, fingerprint: fingerprint),
      );
    } catch (_) {
      return null;
    }
  }

  Future<ParsedBook> import(
    DocRef doc,
    ParsedBook source, {
    required String fingerprint,
  }) async {
    final file = await databaseFile(doc);
    final directory = file.parent;
    await directory.create(recursive: true);
    final temporary = File(
      '${file.path}.$pid.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    try {
      final result = await Isolate.run(() {
        _writeDatabase(temporary.path, source, fingerprint);
        return _readSkeleton(temporary.path, fingerprint: fingerprint)!;
      });
      if (await file.exists()) await file.delete();
      await temporary.rename(file.path);
      await _trim(directory, keepPath: file.path);
      return _withDatabasePath(result, file.path);
    } catch (_) {
      if (await temporary.exists()) await temporary.delete();
      rethrow;
    }
  }

  Future<ParsedSpineItem> loadChapter(
    ParsedBook book,
    int spineIndex,
    ReaderSettings settings,
  ) {
    final path = book.tanachDatabasePath;
    if (path == null) {
      throw StateError('The book has no Tanach content database.');
    }
    final item = book.spine[spineIndex];
    if (item.isLoaded) return Future.value(item);
    return Isolate.run(() {
      final database = sqlite3.open(path, mode: OpenMode.readOnly);
      try {
        return projectChapter(database, item, settings);
      } finally {
        database.close();
      }
    });
  }

  /// Resolve the connected note documents, including incoming references so
  /// notes extracted into another spine item are not repeated in an endnote item.
  static Set<String> relatedDocuments(Database database, String path) {
    final paths = <String>{path};
    final pending = <String>[path];
    while (pending.isNotEmpty) {
      final current = pending.removeLast();
      for (final row in database.select(
        'SELECT target FROM dependencies WHERE source = ?',
        [current],
      )) {
        final target = row['target'] as String;
        if (paths.add(target)) pending.add(target);
      }
    }
    return paths;
  }

  static ParsedSpineItem projectChapter(
    Database database,
    ParsedSpineItem item,
    ReaderSettings settings,
  ) {
    if (!item.isLazy) return item;
    final documents = <String, String>{};
    for (final path in relatedDocuments(database, item.href)) {
      final rows = database.select(
        'SELECT source_gzip FROM documents WHERE path = ?',
        [path],
      );
      if (rows.isNotEmpty) {
        documents[path] = utf8.decode(
          gzip.decode(rows.single['source_gzip'] as Uint8List),
        );
      }
    }
    if (!documents.containsKey(item.href)) {
      throw StateError('Tanach chapter ${item.href} is missing.');
    }
    final projected = TanachLayoutService.layout(
      ParsedBook(
        title: item.title ?? '',
        studyDocuments: documents,
        spine: [item],
      ),
      settings,
    ).spine.single;
    return ParsedSpineItem(
      id: item.id,
      href: item.href,
      title: item.title,
      blocks: projected.blocks,
      anchors: projected.anchors,
      isLazy: true,
      // Fixed source weights keep book progress independent of resident chapters.
      characterCount: item.characterCount,
    );
  }

  Future<void> _trim(Directory directory, {required String keepPath}) async {
    try {
      final entries = await directory
          .list()
          .where((entry) => entry is File && entry.path.endsWith('.sqlite'))
          .cast<File>()
          .toList();
      entries.sort(
        (a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()),
      );
      var total = entries.fold<int>(0, (sum, file) => sum + file.lengthSync());
      final keepKey = _pathKey(keepPath);
      for (final entry in entries) {
        if (total <= cacheByteLimit) break;
        final entryKey = _pathKey(entry.path);
        if (entryKey == keepKey || _pins.containsKey(entryKey)) continue;
        total -= entry.lengthSync();
        await entry.delete();
      }
    } catch (_) {
      // Cache pruning must never prevent a book from opening.
    }
  }

  static ParsedBook _withDatabasePath(ParsedBook book, String path) =>
      ParsedBook(
        title: book.title,
        author: book.author,
        language: book.language,
        rightToLeft: book.rightToLeft,
        contentFingerprint: book.contentFingerprint,
        studySources: book.studySources,
        studyTranslations: book.studyTranslations,
        primaryStudyTranslationId: book.primaryStudyTranslationId,
        spine: book.spine,
        resources: book.resources,
        tableOfContents: book.tableOfContents,
        tanachDatabasePath: path,
      );

  static ParsedBook? _readSkeleton(String path, {required String fingerprint}) {
    final database = sqlite3.open(path, mode: OpenMode.readOnly);
    try {
      final meta = {
        for (final row in database.select('SELECT key, value FROM meta'))
          row['key'] as String: row['value'] as String,
      };
      if (int.tryParse(meta['schema_version'] ?? '') != schemaVersion ||
          meta['fingerprint'] != fingerprint) {
        return null;
      }
      final spine = <ParsedSpineItem>[];
      for (final row in database.select(
        'SELECT spine_index, id, href, title, character_count, is_study, '
        'blocks_json, anchors_json FROM spine ORDER BY spine_index',
      )) {
        final study = (row['is_study'] as int) != 0;
        final blocks = study
            ? const <ContentBlock>[]
            : _decodeBlocks(row['blocks_json'] as String? ?? '[]');
        spine.add(
          ParsedSpineItem(
            id: row['id'] as String,
            href: row['href'] as String,
            title: row['title'] as String?,
            blocks: blocks,
            anchors: study
                ? const {}
                : Map<String, int>.from(
                    jsonDecode(row['anchors_json'] as String? ?? '{}') as Map,
                  ),
            characterCount: row['character_count'] as int,
            isLoaded: !study,
            isLazy: study,
          ),
        );
      }
      if (spine.isEmpty) return null;
      final resources = <String, Uint8List>{};
      for (final row in database.select('SELECT path, bytes FROM resources')) {
        resources[row['path'] as String] = row['bytes'] as Uint8List;
      }
      final translations = <StudyTranslationOption>[
        for (final value
            in jsonDecode(meta['study_translations'] ?? '[]') as List)
          StudyTranslationOption(
            id: value['id'] as String,
            label: value['label'] as String,
          ),
      ];
      return ParsedBook(
        title: meta['title'] ?? 'Untitled',
        author: _nullable(meta['author']),
        language: _nullable(meta['language']),
        rightToLeft: meta['right_to_left'] == '1',
        contentFingerprint: meta['content_fingerprint'] ?? fingerprint,
        studySources: List<String>.from(
          jsonDecode(meta['study_sources'] ?? '[]') as List,
        ),
        studyTranslations: translations,
        primaryStudyTranslationId: _nullable(meta['primary_translation_id']),
        spine: List.unmodifiable(spine),
        resources: Map.unmodifiable(resources),
        tableOfContents: [
          for (final value in jsonDecode(meta['toc'] ?? '[]') as List)
            TocEntry.fromJson(value as Map<String, dynamic>),
        ],
        tanachDatabasePath: path,
      );
    } finally {
      database.close();
    }
  }

  static String? _nullable(String? value) =>
      value == null || value.isEmpty ? null : value;

  static void _writeDatabase(String path, ParsedBook book, String fingerprint) {
    final file = File(path);
    if (file.existsSync()) file.deleteSync();
    final database = sqlite3.open(path);
    try {
      database.execute('PRAGMA journal_mode = OFF');
      database.execute('PRAGMA synchronous = OFF');
      database.execute('''
        CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT NOT NULL);
        CREATE TABLE spine(
          spine_index INTEGER PRIMARY KEY,
          id TEXT NOT NULL,
          href TEXT NOT NULL UNIQUE,
          title TEXT,
          character_count INTEGER NOT NULL,
          is_study INTEGER NOT NULL,
          blocks_json TEXT,
          anchors_json TEXT
        );
        CREATE TABLE documents(
          path TEXT PRIMARY KEY,
          source_gzip BLOB NOT NULL,
          search_text TEXT NOT NULL
        );
        CREATE TABLE dependencies(source TEXT, target TEXT, PRIMARY KEY(source, target));
        CREATE TABLE resources(path TEXT PRIMARY KEY, bytes BLOB NOT NULL);
      ''');
      final sources = <String>{};
      final translations = <String, StudyTranslationOption>{};
      final primaryIds = <String>[];
      final counts = <String, int>{};
      database.execute('BEGIN IMMEDIATE');
      try {
        for (final entry in book.studyDocuments.entries) {
          final document = html.parse(entry.value);
          counts[entry.key] = (document.body?.text ?? '')
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim()
              .length;
          for (final element in document.querySelectorAll(
            '.translation, aside[data-category="translation"]',
          )) {
            final primary = element.classes.contains('translation');
            final option = _translationOption(element, primary: primary);
            if (option == null) continue;
            translations.putIfAbsent(option.id, () => option);
            if (primary && !primaryIds.contains(option.id)) {
              primaryIds.add(option.id);
            }
          }
          for (final note in document.querySelectorAll('aside[data-source]')) {
            if (const {
              'rishon',
              'acharon',
              'modern',
            }.contains(note.attributes['data-category'])) {
              sources.add(note.attributes['data-source']!);
            }
          }
          database.execute('INSERT INTO documents VALUES (?, ?, ?)', [
            entry.key,
            Uint8List.fromList(gzip.encode(utf8.encode(entry.value))),
            normalizeTanachSearchText(document.body?.text ?? document.outerHtml)
                .replaceAll(RegExp(r'\s+'), ''),
          ]);
          for (final link in document.querySelectorAll('a[href]')) {
            final isNote = link.attributes.entries.any(
              (e) =>
                  e.key.toString().endsWith(':type') &&
                  e.value.split(' ').contains('noteref'),
            );
            var inIndex = false;
            for (
              Element? parent = link.parent;
              parent != null;
              parent = parent.parent
            ) {
              if (parent.attributes['data-category'] == 'index') {
                inIndex = true;
                break;
              }
            }
            if (!isNote && !inIndex) continue;
            final target = TanachLayoutService.resolve(
              entry.key,
              link.attributes['href']!,
            ).split('#').first;
            if (target == entry.key ||
                !book.studyDocuments.containsKey(target)) {
              continue;
            }
            database.execute(
              'INSERT OR IGNORE INTO dependencies VALUES (?, ?)',
              [entry.key, target],
            );
            database.execute(
              'INSERT OR IGNORE INTO dependencies VALUES (?, ?)',
              [target, entry.key],
            );
          }
        }
        for (var index = 0; index < book.spine.length; index++) {
          final item = book.spine[index];
          final source = book.studyDocuments[item.href];
          final isStudy = source != null;
          final characterCount = counts[item.href] ?? item.characterCount;
          database.execute(
            'INSERT INTO spine VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
            [
              index,
              item.id,
              item.href,
              item.title,
              characterCount,
              isStudy ? 1 : 0,
              isStudy ? null : jsonEncode(_encodeBlocks(item.blocks)),
              isStudy ? null : jsonEncode(item.anchors),
            ],
          );
        }
        for (final entry in book.resources.entries) {
          database.execute('INSERT INTO resources VALUES (?, ?)', [
            entry.key,
            entry.value,
          ]);
        }
        final primary =
            primaryIds
                .where((id) => translations[id]?.label == 'Metsudah')
                .firstOrNull ??
            primaryIds.firstOrNull;
        final meta = <String, String>{
          'schema_version': '$schemaVersion',
          'fingerprint': fingerprint,
          'content_fingerprint': book.contentFingerprint,
          'title': book.title,
          'author': book.author ?? '',
          'language': book.language ?? '',
          'right_to_left': book.rightToLeft ? '1' : '0',
          'study_sources': jsonEncode(sources.toList()..sort()),
          'study_translations': jsonEncode([
            for (final option in translations.values)
              {'id': option.id, 'label': option.label},
          ]),
          'primary_translation_id': primary ?? '',
          'toc': jsonEncode(
            book.tableOfContents.map((entry) => entry.toJson()).toList(),
          ),
        };
        for (final entry in meta.entries) {
          database.execute('INSERT INTO meta VALUES (?, ?)', [
            entry.key,
            entry.value,
          ]);
        }
        database.execute('COMMIT');
      } catch (_) {
        database.execute('ROLLBACK');
        rethrow;
      }
      database.execute('PRAGMA optimize');
    } finally {
      database.close();
    }
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
}

String normalizeTanachSearchText(String source) {
  final buffer = StringBuffer();
  var wasSpace = false;
  for (final rune in source.runes) {
    if (_isHebrewMark(rune) || rune == 0x00ad) continue;
    final character = String.fromCharCode(rune).toLowerCase();
    final isSpace = character.trim().isEmpty;
    if (isSpace) {
      if (!wasSpace && buffer.isNotEmpty) buffer.write(' ');
    } else {
      buffer.write(character);
    }
    wasSpace = isSpace;
  }
  return buffer.toString().trim();
}

bool _isHebrewMark(int rune) =>
    (rune >= 0x0591 && rune <= 0x05bd) ||
    rune == 0x05bf ||
    rune == 0x05c1 ||
    rune == 0x05c2 ||
    rune == 0x05c4 ||
    rune == 0x05c5 ||
    rune == 0x05c7;

List<Map<String, dynamic>> _encodeBlocks(List<ContentBlock> blocks) => [
  for (final block in blocks)
    {
      'type': block.type.name,
      'direction': block.direction.name,
      'alignment': block.alignment.name,
      'nestingLevel': block.nestingLevel,
      'orderedList': block.orderedList,
      'id': block.id,
      'resourcePath': block.resourcePath,
      'alternateText': block.alternateText,
      'fontSizeMultiplier': block.fontSizeMultiplier,
      'lineHeight': block.lineHeight,
      'spacingAfterEm': block.spacingAfterEm,
      'textIndentEm': block.textIndentEm,
      'forceBold': block.forceBold,
      'trailingDirection': block.trailingDirection.name,
      'runs': [_encodeRuns(block.runs), _encodeRuns(block.trailingRuns)],
    },
];

List<Map<String, dynamic>> _encodeRuns(List<InlineRun> runs) => [
  for (final run in runs)
    {
      'text': run.text,
      'bold': run.bold,
      'italic': run.italic,
      'code': run.code,
      'href': run.href,
      'language': run.language,
    },
];

List<ContentBlock> _decodeBlocks(String source) => [
  for (final value in jsonDecode(source) as List)
    ContentBlock(
      type: BlockType.values.byName(value['type'] as String),
      direction: BlockTextDirection.values.byName(value['direction'] as String),
      alignment: BlockAlignment.values.byName(value['alignment'] as String),
      nestingLevel: value['nestingLevel'] as int,
      orderedList: value['orderedList'] as bool,
      id: value['id'] as String?,
      resourcePath: value['resourcePath'] as String?,
      alternateText: value['alternateText'] as String?,
      fontSizeMultiplier: (value['fontSizeMultiplier'] as num?)?.toDouble(),
      lineHeight: (value['lineHeight'] as num?)?.toDouble(),
      spacingAfterEm: (value['spacingAfterEm'] as num?)?.toDouble(),
      textIndentEm: (value['textIndentEm'] as num?)?.toDouble(),
      forceBold: value['forceBold'] as bool? ?? false,
      trailingDirection: BlockTextDirection.values.byName(
        value['trailingDirection'] as String? ?? 'rtl',
      ),
      runs: _decodeRuns((value['runs'] as List)[0] as List),
      trailingRuns: _decodeRuns((value['runs'] as List)[1] as List),
    ),
];

List<InlineRun> _decodeRuns(List values) => [
  for (final value in values)
    InlineRun(
      text: value['text'] as String,
      bold: value['bold'] as bool,
      italic: value['italic'] as bool,
      code: value['code'] as bool,
      href: value['href'] as String?,
      language: value['language'] as String?,
    ),
];

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}

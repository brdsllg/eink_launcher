import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import '../models/content_block.dart';
import '../models/doc_ref.dart';
import '../models/parsed_book.dart';
import '../models/toc_entry.dart';
import 'epub_parser_service.dart';

/// Disposable, versioned parse cache. Images are included so a hit never needs
/// to reopen the ZIP. Source metadata and CSS mode invalidate stale blocks.
class ParsedEpubCacheService {
  static const version = 1;
  static const maxBytes = 64 * 1024 * 1024;
  final Directory? cacheDirectory;
  const ParsedEpubCacheService({this.cacheDirectory});

  Future<ParsedBook> load(
    DocRef doc,
    bool honorPublisherCss, {
    Future<ParsedBook> Function()? parser,
  }) async {
    String? cachePath;
    String? fingerprint;
    try {
      final stat = await File(doc.path).stat();
      if (stat.type != FileSystemEntityType.file) {
        throw FileSystemException('EPUB is missing', doc.path);
      }
      fingerprint = '${stat.size}:${stat.modified.microsecondsSinceEpoch}';
      final key = sha256
          .convert(
            utf8.encode('$version:${doc.id}:$fingerprint:$honorPublisherCss'),
          )
          .toString();
      final directory =
          cacheDirectory ??
          Directory(
            '${(await getApplicationCacheDirectory()).path}/parsed_epubs',
          );
      cachePath = '${directory.path}/$key.json';
      final path = cachePath;
      final cached = await Isolate.run(() => _read(path));
      if (cached != null) return cached;
    } catch (_) {
      // Cache availability never determines whether the original can open.
    }
    final book =
        await (parser?.call() ??
            const EpubParserService().parseFile(
              doc.path,
              honorPublisherCss: honorPublisherCss,
            ));
    if (cachePath != null) {
      try {
        final stat = await File(doc.path).stat();
        if ('${stat.size}:${stat.modified.microsecondsSinceEpoch}' ==
            fingerprint) {
          final path = cachePath;
          await Isolate.run(() => _write(path, book));
        }
      } catch (_) {}
    }
    return book;
  }

  static ParsedBook? _read(String path) {
    try {
      final file = File(path);
      if (!file.existsSync() || file.lengthSync() > maxBytes) return null;
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      if (json['version'] != version) return null;
      final book = _decode(json);
      if (book.spine.isEmpty) return null;
      file.setLastModifiedSync(DateTime.now());
      return book;
    } catch (_) {
      return null;
    }
  }

  static void _write(String path, ParsedBook book) {
    File? temp;
    try {
      final encoded = utf8.encode(jsonEncode(_encode(book)));
      if (encoded.length > maxBytes) return;
      final file = File(path);
      file.parent.createSync(recursive: true);
      temp = File('$path.$pid.${DateTime.now().microsecondsSinceEpoch}.tmp');
      temp.writeAsBytesSync(encoded, flush: true);
      temp.renameSync(path);
      final entries =
          file.parent
              .listSync()
              .whereType<File>()
              .where((entry) => entry.path.endsWith('.json'))
              .toList()
            ..sort(
              (a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()),
            );
      var total = entries.fold(0, (int sum, entry) => sum + entry.lengthSync());
      for (final entry in entries) {
        if (total <= maxBytes) break;
        total -= entry.lengthSync();
        entry.deleteSync();
      }
    } catch (_) {
      try {
        if (temp?.existsSync() ?? false) temp!.deleteSync();
      } catch (_) {}
    }
  }

  static Map<String, dynamic> _encode(ParsedBook book) => {
    'version': version,
    'title': book.title,
    'author': book.author,
    'language': book.language,
    'toc': book.tableOfContents.map((entry) => entry.toJson()).toList(),
    'resources': book.resources.map(
      (key, value) => MapEntry(key, base64Encode(value)),
    ),
    'spine': [
      for (final item in book.spine)
        {
          'id': item.id,
          'href': item.href,
          'title': item.title,
          'anchors': item.anchors,
          'blocks': [
            for (final block in item.blocks)
              {
                'type': block.type.name,
                'direction': block.direction.name,
                'alignment': block.alignment.name,
                'nestingLevel': block.nestingLevel,
                'orderedList': block.orderedList,
                'id': block.id,
                'resourcePath': block.resourcePath,
                'alternateText': block.alternateText,
                'runs': [
                  for (final run in block.runs)
                    {
                      'text': run.text,
                      'bold': run.bold,
                      'italic': run.italic,
                      'code': run.code,
                      'href': run.href,
                      'language': run.language,
                    },
                ],
              },
          ],
        },
    ],
  };

  static ParsedBook _decode(Map<String, dynamic> json) => ParsedBook(
    title: json['title'] as String,
    author: json['author'] as String?,
    language: json['language'] as String?,
    tableOfContents: [
      for (final entry in json['toc'] as List)
        TocEntry.fromJson(entry as Map<String, dynamic>),
    ],
    resources: (json['resources'] as Map<String, dynamic>).map(
      (key, value) => MapEntry(key, base64Decode(value as String)),
    ),
    spine: [
      for (final item in json['spine'] as List)
        ParsedSpineItem(
          id: item['id'] as String,
          href: item['href'] as String,
          title: item['title'] as String?,
          anchors: Map<String, int>.from(item['anchors'] as Map),
          blocks: [
            for (final block in item['blocks'] as List)
              ContentBlock(
                type: BlockType.values.byName(block['type'] as String),
                direction: BlockTextDirection.values.byName(
                  block['direction'] as String,
                ),
                alignment: BlockAlignment.values.byName(
                  block['alignment'] as String,
                ),
                nestingLevel: block['nestingLevel'] as int,
                orderedList: block['orderedList'] as bool,
                id: block['id'] as String?,
                resourcePath: block['resourcePath'] as String?,
                alternateText: block['alternateText'] as String?,
                runs: [
                  for (final run in block['runs'] as List)
                    InlineRun(
                      text: run['text'] as String,
                      bold: run['bold'] as bool,
                      italic: run['italic'] as bool,
                      code: run['code'] as bool,
                      href: run['href'] as String?,
                      language: run['language'] as String?,
                    ),
                ],
              ),
          ],
        ),
    ],
  );
}

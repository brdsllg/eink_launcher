import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import '../models/laid_out_page.dart';
import '../models/reader_settings.dart';
import '../models/reading_position.dart';

class PaginationCacheService {
  static const int _cacheVersion = 7;
  static const int defaultMaxBytes = 64 * 1024 * 1024;
  static Future<void> _writes = Future.value();
  static Future<void>? _legacyCleanup;

  final Directory? cacheDirectory;
  final int maxBytes;

  const PaginationCacheService({
    this.cacheDirectory,
    this.maxBytes = defaultMaxBytes,
  });

  String keyFor({
    required String docId,
    required int spineIndex,
    required double width,
    required double height,
    required ReaderSettings settings,
  }) {
    final source = jsonEncode({
      'version': _cacheVersion,
      'study': [
        settings.inlineCommentary,
        [...settings.commentarySources]..sort(),
        settings.commentaryLanguage,
        settings.studyTranslation,
      ],
      'docId': docId,
      'spineIndex': spineIndex,
      // Fractional logical pixels can change a TextPainter line break. Keep
      // enough precision to avoid reusing geometry from a nearby viewport.
      'width': width.toStringAsFixed(3),
      'height': height.toStringAsFixed(3),
      'latinFont': settings.latinFontFamily,
      'hebrewFont': settings.hebrewFontFamily,
      'fontSizeStep': settings.fontSizeStep,
      'lineHeight': settings.lineHeight,
      'marginStep': settings.marginStep,
      'justify': settings.justify,
      'hyphenate': settings.hyphenate,
      'paragraphMode': settings.paragraphMode.name,
      'publisherCss': settings.honorPublisherCss,
    });
    return sha1.convert(utf8.encode(source)).toString();
  }

  Future<List<LaidOutPage>?> load(String key) async {
    try {
      final file = await _fileFor(key);
      if (!await file.exists()) return null;
      if (await file.length() > maxBytes) {
        await file.delete();
        return null;
      }
      final data =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      if (data['version'] != _cacheVersion) return null;
      await file.setLastModified(DateTime.now());
      final pages = data['pages'] as List<dynamic>;
      return List<LaidOutPage>.unmodifiable(
        pages.map((value) => _pageFromJson(value as Map<String, dynamic>)),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> save(String key, List<LaidOutPage> pages) {
    // Serialize publication and eviction across sessions sharing this cache.
    final operation = _writes.then((_) => _save(key, pages));
    _writes = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> _save(String key, List<LaidOutPage> pages) async {
    File? temporary;
    try {
      final file = await _fileFor(key);
      await file.parent.create(recursive: true);
      final encoded = utf8.encode(
        jsonEncode({
          'version': _cacheVersion,
          'pages': pages.map(_pageToJson).toList(),
        }),
      );
      if (encoded.length > maxBytes) return;
      // Separate temporary files prevent two superseded pagination runs from
      // writing through the same handle. Rename is atomic on the Android/Linux
      // target and replaces any older cache entry in one filesystem operation.
      temporary = File(
        '${file.path}.${DateTime.now().microsecondsSinceEpoch}.$pid.tmp',
      );
      await temporary.writeAsBytes(encoded, flush: true);
      await temporary.rename(file.path);
      await _trim(file.parent);
    } catch (_) {
      try {
        if (temporary != null && await temporary.exists()) {
          await temporary.delete();
        }
      } catch (_) {}
    }
  }

  Future<File> _fileFor(String key) async {
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(key)) {
      throw ArgumentError('Invalid cache key');
    }
    if (cacheDirectory == null) await (_legacyCleanup ??= _removeLegacyCache());
    final directory =
        cacheDirectory ??
        Directory('${(await getApplicationCacheDirectory()).path}/pages');
    return File('${directory.path}/$key.json');
  }

  static Future<void> _removeLegacyCache() async {
    try {
      final directory = Directory(
        '${(await getApplicationDocumentsDirectory()).path}/pages',
      );
      if (!await directory.exists()) return;
      await for (final entity in directory.list(followLinks: false)) {
        final name = entity.uri.pathSegments.last;
        if (entity is File &&
            RegExp(r'^[a-f0-9]{40}\.json(?:\.[0-9.]+\.tmp)?$').hasMatch(name)) {
          await entity.delete();
        }
      }
    } catch (_) {
      /* Disposable cache cleanup must not block reading. */
    }
  }

  Future<void> _trim(Directory directory) async {
    final entries = <({File file, FileStat stat})>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File) continue;
      final stat = await entity.stat();
      if (entity.path.endsWith('.tmp')) {
        if (DateTime.now().difference(stat.modified) >
            const Duration(days: 1)) {
          await entity.delete();
        }
      } else if (entity.path.endsWith('.json')) {
        entries.add((file: entity, stat: stat));
      }
    }
    entries.sort((a, b) => a.stat.modified.compareTo(b.stat.modified));
    var total = entries.fold(0, (sum, entry) => sum + entry.stat.size);
    for (final entry in entries) {
      if (total <= maxBytes) break;
      await entry.file.delete();
      total -= entry.stat.size;
    }
  }

  Map<String, dynamic> _pageToJson(LaidOutPage page) => {
    'pageIndex': page.pageIndex,
    'start': page.start.toJson(),
    'end': page.end.toJson(),
    'slices': [
      for (final slice in page.slices)
        {
          'blockIndex': slice.blockIndex,
          'startCharOffset': slice.startCharOffset,
          'endCharOffset': slice.endCharOffset,
          'sourceTop': slice.sourceTop,
          'height': slice.height,
        },
    ],
  };

  LaidOutPage _pageFromJson(Map<String, dynamic> json) => LaidOutPage(
    pageIndex: json['pageIndex'] as int,
    start: TextReadingPosition.fromJson(json['start'] as Map<String, dynamic>),
    end: TextReadingPosition.fromJson(json['end'] as Map<String, dynamic>),
    slices: List<BlockSlice>.unmodifiable(
      (json['slices'] as List<dynamic>).map((value) {
        final slice = value as Map<String, dynamic>;
        return BlockSlice(
          blockIndex: slice['blockIndex'] as int,
          startCharOffset: slice['startCharOffset'] as int,
          endCharOffset: slice['endCharOffset'] as int,
          sourceTop: (slice['sourceTop'] as num).toDouble(),
          height: (slice['height'] as num).toDouble(),
        );
      }),
    ),
  );
}

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import '../models/laid_out_page.dart';
import '../models/reader_settings.dart';
import '../models/reading_position.dart';

class PaginationCacheService {
  static const int _cacheVersion = 2;

  final Directory? cacheDirectory;

  const PaginationCacheService({this.cacheDirectory});

  String keyFor({
    required String docId,
    required int spineIndex,
    required double width,
    required double height,
    required ReaderSettings settings,
  }) {
    final source = jsonEncode({
      'version': _cacheVersion,
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
      final data =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      if (data['version'] != _cacheVersion) return null;
      final pages = data['pages'] as List<dynamic>;
      return List<LaidOutPage>.unmodifiable(
        pages.map((value) => _pageFromJson(value as Map<String, dynamic>)),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> save(String key, List<LaidOutPage> pages) async {
    File? temporary;
    try {
      final file = await _fileFor(key);
      await file.parent.create(recursive: true);
      // Separate temporary files prevent two superseded pagination runs from
      // writing through the same handle. Rename is atomic on the Android/Linux
      // target and replaces any older cache entry in one filesystem operation.
      temporary = File(
        '${file.path}.${DateTime.now().microsecondsSinceEpoch}.$pid.tmp',
      );
      await temporary.writeAsString(
        jsonEncode({
          'version': _cacheVersion,
          'pages': pages.map(_pageToJson).toList(),
        }),
        flush: true,
      );
      await temporary.rename(file.path);
    } catch (_) {
      if (temporary != null && await temporary.exists()) {
        await temporary.delete();
      }
    }
  }

  Future<File> _fileFor(String key) async {
    final directory =
        cacheDirectory ??
        Directory('${(await getApplicationDocumentsDirectory()).path}/pages');
    return File('${directory.path}/$key.json');
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

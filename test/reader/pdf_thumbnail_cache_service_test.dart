import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:eink_launcher/reader/services/pdf_crop_service.dart';
import 'package:eink_launcher/reader/services/pdf_thumbnail_cache_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('round-trips an owned thumbnail and keys document geometry', () async {
    final directory = await Directory.systemTemp.createTemp('pdf-thumbnails-');
    addTearDown(() => directory.delete(recursive: true));
    final cache = PdfThumbnailCacheService.forTesting(
      cacheDirectory: directory,
    );
    final key = cache.keyFor(
      docId: 'document-a',
      pageIndex: 3,
      pixelWidth: 160,
      pixelHeight: 240,
      crop: PdfCropRect.fullPage,
    );
    final changedPage = cache.keyFor(
      docId: 'document-a',
      pageIndex: 4,
      pixelWidth: 160,
      pixelHeight: 240,
      crop: PdfCropRect.fullPage,
    );
    final changedCrop = cache.keyFor(
      docId: 'document-a',
      pageIndex: 3,
      pixelWidth: 160,
      pixelHeight: 240,
      crop: const PdfCropRect(left: 0.1, top: 0, right: 1, bottom: 1),
    );
    expect(changedPage, isNot(key));
    expect(changedCrop, isNot(key));

    await cache.store(key, await _makeImage(18, 24, Colors.black));
    expect(await cache.contains(key), isTrue);
    final restored = await cache.load(key);
    expect(restored, isNotNull);
    expect(restored!.width, 18);
    expect(restored.height, 24);
    restored.dispose();
    expect(directory.listSync().whereType<File>(), hasLength(1));
  });

  test('corrupt and temporary entries are removed without throwing', () async {
    final directory = await Directory.systemTemp.createTemp('pdf-thumbnails-');
    addTearDown(() => directory.delete(recursive: true));
    final cache = PdfThumbnailCacheService.forTesting(
      cacheDirectory: directory,
    );
    final key = cache.keyFor(
      docId: 'document-b',
      pageIndex: 0,
      pixelWidth: 100,
      pixelHeight: 100,
      crop: PdfCropRect.fullPage,
    );
    final corrupt = File('${directory.path}/$key.png');
    await corrupt.writeAsBytes([1, 2, 3, 4]);
    final temporary = File('${directory.path}/abandoned.png.1.tmp');
    await temporary.writeAsString('partial');

    expect(await cache.load(key), isNull);
    expect(await corrupt.exists(), isFalse);
    expect(await temporary.exists(), isFalse);
  });

  test('encoded files are evicted to the configured disk budget', () async {
    final directory = await Directory.systemTemp.createTemp('pdf-thumbnails-');
    addTearDown(() => directory.delete(recursive: true));
    final cache = PdfThumbnailCacheService.forTesting(
      cacheDirectory: directory,
      maxBytes: 1,
    );
    final key = cache.keyFor(
      docId: 'document-c',
      pageIndex: 0,
      pixelWidth: 32,
      pixelHeight: 32,
      crop: PdfCropRect.fullPage,
    );

    await cache.store(
      key,
      await _makeImage(32, 32, Colors.blue),
      docId: 'document-c',
      pageIndex: 0,
    );
    expect(await cache.contains(key), isFalse);
    expect(await cache.loadOpeningPreview('document-c'), isNull);
    expect(
      directory.listSync().whereType<File>().where(
        (file) => file.path.endsWith('.png'),
      ),
      isEmpty,
    );
  });

  test('opening preview resolves only the first page across restart', () async {
    final directory = await Directory.systemTemp.createTemp('pdf-thumbnails-');
    addTearDown(() => directory.delete(recursive: true));
    final cache = PdfThumbnailCacheService.forTesting(
      cacheDirectory: directory,
    );
    expect(await cache.loadOpeningPreview('document'), isNull);
    final first = _key(cache, 'document', 0);
    final later = _key(cache, 'document', 4);
    await cache.store(
      first,
      await _makeImage(18, 24, Colors.black),
      docId: 'document',
      pageIndex: 0,
    );
    await cache.store(
      later,
      await _makeImage(28, 30, Colors.white),
      docId: 'document',
      pageIndex: 4,
    );

    final restored = PdfThumbnailCacheService.forTesting(
      cacheDirectory: directory,
    );
    final preview = await restored.loadOpeningPreview('document');
    expect(preview, isNotNull);
    expect(preview!.width, 18);
    expect(preview.height, 24);
    preview.dispose();
    expect(await restored.loadOpeningPreview('unknown-document'), isNull);
    expect(
      directory.listSync().whereType<File>().where(
        (file) => file.path.endsWith('.png'),
      ),
      hasLength(2),
    );
    expect(directory.listSync().whereType<File>(), hasLength(3));
  });

  for (final useLoad in [true, false]) {
    test(
      'existing first-page ${useLoad ? 'load' : 'hit'} gains opening metadata',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'pdf-thumbnails-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final cache = PdfThumbnailCacheService.forTesting(
          cacheDirectory: directory,
        );
        final key = _key(cache, 'legacy-document', 0);
        await cache.store(key, await _makeImage(18, 24, Colors.black));
        expect(await cache.loadOpeningPreview('legacy-document'), isNull);
        if (useLoad) {
          final image = await cache.load(
            key,
            docId: 'legacy-document',
            pageIndex: 0,
          );
          image!.dispose();
        } else {
          expect(
            await cache.contains(key, docId: 'legacy-document', pageIndex: 0),
            isTrue,
          );
        }
        final restarted = PdfThumbnailCacheService.forTesting(
          cacheDirectory: directory,
        );
        final opening = await restarted.loadOpeningPreview('legacy-document');
        expect(opening, isNotNull);
        opening!.dispose();
      },
    );
  }

  for (final corrupt in [true, false]) {
    test(
      '${corrupt ? 'corrupt' : 'missing'} first-page PNG invalidates opening metadata',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'pdf-thumbnails-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final cache = PdfThumbnailCacheService.forTesting(
          cacheDirectory: directory,
        );
        final key = _key(cache, 'document', 0);
        await cache.store(
          key,
          await _makeImage(18, 24, Colors.black),
          docId: 'document',
          pageIndex: 0,
        );
        final file = File('${directory.path}/$key.png');
        if (corrupt) {
          await file.writeAsBytes([1, 2, 3]);
        } else {
          await file.delete();
        }
        expect(await cache.loadOpeningPreview('document'), isNull);
        final restarted = PdfThumbnailCacheService.forTesting(
          cacheDirectory: directory,
        );
        expect(await restarted.loadOpeningPreview('document'), isNull);
        expect(
          await File('${directory.path}/opening-previews.json').exists(),
          isFalse,
        );
      },
    );
  }

  test('restart eviction prunes opening metadata', () async {
    final directory = await Directory.systemTemp.createTemp('pdf-thumbnails-');
    addTearDown(() => directory.delete(recursive: true));
    final cache = PdfThumbnailCacheService.forTesting(
      cacheDirectory: directory,
    );
    await cache.store(
      _key(cache, 'document', 0),
      await _makeImage(18, 24, Colors.black),
      docId: 'document',
      pageIndex: 0,
    );
    final restarted = PdfThumbnailCacheService.forTesting(
      cacheDirectory: directory,
      maxBytes: 1,
    );
    expect(await restarted.loadOpeningPreview('document'), isNull);
    expect(directory.listSync(), isEmpty);
  });

  test('corrupt index is a miss and preserves cached PNGs', () async {
    final directory = await Directory.systemTemp.createTemp('pdf-thumbnails-');
    addTearDown(() => directory.delete(recursive: true));
    final cache = PdfThumbnailCacheService.forTesting(
      cacheDirectory: directory,
    );
    final key = _key(cache, 'document', 0);
    await cache.store(key, await _makeImage(18, 24, Colors.black));
    await File('${directory.path}/opening-previews.json')
        .writeAsString('{broken');
    final restarted = PdfThumbnailCacheService.forTesting(
      cacheDirectory: directory,
    );
    expect(await restarted.loadOpeningPreview('document'), isNull);
    expect(await restarted.contains(key), isTrue);
  });

  test(
    'opening index is bounded and rejects references to absent PNGs',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'pdf-thumbnails-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final cache = PdfThumbnailCacheService.forTesting(
        cacheDirectory: directory,
      );
      final key = _key(cache, 'document', 0);
      await cache.store(key, await _makeImage(18, 24, Colors.black));
      final index = File('${directory.path}/opening-previews.json');
      await index.writeAsString(
        jsonEncode({
          'version': PdfThumbnailCacheService.cacheVersion,
          'firstPages': {
            for (
              var i = 0;
              i < PdfThumbnailCacheService.maxOpeningPreviews + 2;
              i++
            )
              'doc-$i': key,
            'absent': 'missing-png',
          },
        }),
      );
      final restarted = PdfThumbnailCacheService.forTesting(
        cacheDirectory: directory,
      );
      expect(await restarted.loadOpeningPreview('absent'), isNull);
      final stored = jsonDecode(await index.readAsString()) as Map;
      expect(
        stored['firstPages'],
        hasLength(PdfThumbnailCacheService.maxOpeningPreviews),
      );
      expect(stored['firstPages'], isNot(contains('absent')));
    },
  );
}

String _key(PdfThumbnailCacheService cache, String docId, int pageIndex) =>
    cache.keyFor(
      docId: docId,
      pageIndex: pageIndex,
      pixelWidth: 240,
      pixelHeight: 320,
      crop: PdfCropRect.fullPage,
    );

Future<ui.Image> _makeImage(int width, int height, Color color) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = color,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  picture.dispose();
  return image;
}

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

    await cache.store(key, await _makeImage(32, 32, Colors.blue));
    expect(await cache.contains(key), isFalse);
    expect(
      directory.listSync().whereType<File>().where(
        (file) => file.path.endsWith('.png'),
      ),
      isEmpty,
    );
  });
}

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

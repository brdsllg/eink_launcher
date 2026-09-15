import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eink_launcher/reader/models/reader_settings.dart';
import 'package:eink_launcher/reader/services/epub_parser_service.dart';
import 'package:eink_launcher/reader/services/epub_paginator_service.dart';

import 'tanach_compatibility_test.dart' as fixtures;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('bilingual inline commentary renders with bundled fonts', () async {
    for (final entry in {
      'Literata': 'Literata-Regular.ttf',
      'Frank Ruhl Libre': 'FrankRuhlLibre-Regular.ttf',
    }.entries) {
      final loader = FontLoader(entry.key)
        ..addFont(rootBundle.load('assets/fonts/${entry.value}'));
      await loader.load();
    }
    final book = EpubParserService.parseBytesSync(fixtures.fixture());
    final blocks = book.spine.first.blocks;
    const settings = ReaderSettings(justify: false, hyphenate: false);
    final pages = const EpubPaginatorService().paginateSpine(
      spineIndex: 0,
      blocks: blocks,
      contentSize: const Size(352, 608),
      settings: settings,
    );
    expect(pages, isNotEmpty);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..drawColor(Colors.white, BlendMode.src);
    var y = 16.0;
    for (final slice in pages.first.slices) {
      final painter = TextBlockLayout.createPainter(
        blocks[slice.blockIndex],
        settings,
        352,
      );
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(16, y, 352, slice.height));
      painter.paint(canvas, Offset(16, y - slice.sourceTop));
      canvas.restore();
      painter.dispose();
      y += slice.height;
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(384, 640);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    expect(png!.lengthInBytes, greaterThan(1000));
    final destination = Platform.environment['TANACH_QA_PNG'];
    if (destination != null) {
      File(destination).writeAsBytesSync(png.buffer.asUint8List());
    }
    image.dispose();
    picture.dispose();
  });
}

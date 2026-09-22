import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:eink_launcher/reader/controllers/text_reader_session.dart';
import 'package:eink_launcher/reader/models/content_block.dart';
import 'package:eink_launcher/reader/models/doc_ref.dart';
import 'package:eink_launcher/reader/models/parsed_book.dart';
import 'package:eink_launcher/reader/models/reader_settings.dart';
import 'package:eink_launcher/reader/services/book_store_service.dart';
import 'package:eink_launcher/reader/services/epub_paginator_service.dart';
import 'package:eink_launcher/reader/services/pagination_cache_service.dart';
import 'package:eink_launcher/reader/services/text_block_parser.dart';
import 'package:eink_launcher/reader/widgets/block_slice_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Uint8List> portraitPng() async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(Colors.black, BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(200, 400);
  final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
      .asUint8List();
  image.dispose();
  picture.dispose();
  return bytes;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'session discovers image dimensions and responsive layout uses them',
    () async {
      final dir = await Directory.systemTemp.createTemp('image-layout-');
      final store = BookStoreService.instance;
      await store.init(customFile: File('${dir.path}/library.json'));
      const image = ContentBlock(
        type: BlockType.image,
        resourcePath: 'portrait.png',
      );
      final bytes = await portraitPng();
      final book = ParsedBook(
        title: 'Images',
        resources: {'portrait.png': bytes},
        spine: [
          ParsedSpineItem(id: 'one', href: 'one', blocks: [image]),
        ],
      );
      final session = TextReaderSession(
        doc: const DocRef(
          id: 'image-book',
          path: '/image.epub',
          format: DocFormat.epub,
          title: 'Images',
          fileSize: 1,
        ),
        bookLoader: (_, _) async => book,
        paginationCache: PaginationCacheService(
          cacheDirectory: Directory('${dir.path}/pages'),
        ),
      );
      await session.open();
      await session.prepareViewport(const Size(400, 600));
      expect(session.imageSizeFor('portrait.png'), const Size(200, 400));
      expect(
        session.currentLaidOutPage!.slices.single.height,
        greaterThan(160),
      );
      final pages = await const EpubPaginatorService().paginateSpineResponsive(
        spineIndex: 0,
        blocks: [image],
        contentSize: const Size(400, 600),
        settings: const ReaderSettings(),
        imageSizes: {'portrait.png': session.imageSizeFor('portrait.png')!},
        isCancelled: () => false,
        onProgress: (_) {},
      );
      expect(pages.single.slices.single.height, greaterThan(400));
      session.dispose();
      await store.flush();
      store.dispose();
      await dir.delete(recursive: true);
    },
  );

  testWidgets('image painting and pagination agree on the full figure height', (
    tester,
  ) async {
    final bytes = await tester.runAsync(portraitPng);
    const block = ContentBlock(
      type: BlockType.image,
      resourcePath: 'portrait.png',
    );
    const settings = ReaderSettings();
    final page = const EpubPaginatorService()
        .paginateSpine(
          spineIndex: 0,
          blocks: [block],
          contentSize: const Size(400, 600),
          settings: settings,
          imageSizes: {'portrait.png': const Size(200, 400)},
        )
        .single;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 400,
              child: BlockSliceView(
                block: block,
                slice: page.slices.single,
                settings: settings,
                pageHeight: 600,
                imageBytes: bytes,
                imageSize: const Size(200, 400),
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byType(Image)).height, closeTo(432, 0.01));
    expect(tester.takeException(), isNull);
  });

  test('Markdown resolves encoded local paths, skips remote images and invalidates changed assets', () async {
    final dir = await Directory.systemTemp.createTemp('markdown-images-');
    addTearDown(() => dir.delete(recursive: true));
    final source = File('${dir.path}/book.md');
    final image = File('${dir.path}/my image.png');
    await image.writeAsBytes(await portraitPng());
    await source.writeAsString(
      '![local](my%20image.png)\n\n![remote](https://example.com/pic.png)\n\n![missing](missing.png)',
    );
    const parser = TextBlockParser();
    final first = await parser.parseFile(
      source.path,
      format: DocFormat.markdown,
      title: 'Images',
    );
    expect(first.resources.length, 1);
    expect(first.resources.values.single, await image.readAsBytes());
    await image.writeAsBytes([1, 2, 3]);
    final changed = await parser.parseFile(
      source.path,
      format: DocFormat.markdown,
      title: 'Images',
    );
    expect(changed.contentFingerprint, isNot(first.contentFingerprint));
  });
}

import 'dart:io';

import 'package:eink_launcher/reader/controllers/text_reader_session.dart';
import 'package:eink_launcher/reader/models/content_block.dart';
import 'package:eink_launcher/reader/models/doc_ref.dart';
import 'package:eink_launcher/reader/models/parsed_book.dart';
import 'package:eink_launcher/reader/services/book_store_service.dart';
import 'package:eink_launcher/reader/services/epub_paginator_service.dart';
import 'package:eink_launcher/reader/services/pagination_cache_service.dart';
import 'package:eink_launcher/reader/widgets/block_slice_view.dart';
import 'package:eink_launcher/reader/widgets/text_page_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'underline and notes save, edit, survive navigation/reload and delete',
    (tester) async {
      late Directory directory;
      late File library;
      late TextReaderSession session;
      await settleIo(tester, () async {
        directory = await Directory.systemTemp.createTemp('annotation-flow-');
        library = File('${directory.path}/library.json');
        await BookStoreService.instance.init(customFile: library);
        session = TextReaderSession(
          doc: const DocRef(
            id: 'annotations',
            path: '/book.txt',
            format: DocFormat.txt,
            title: 'Annotations',
            fileSize: 100,
          ),
          paginationCache: PaginationCacheService(
            cacheDirectory: Directory('${directory.path}/pages'),
          ),
          bookLoader: (_, _) async => ParsedBook(
            title: 'Annotations',
            spine: [
              ParsedSpineItem(
                id: 'chapter',
                href: 'chapter.txt',
                blocks: [
                  ContentBlock(
                    type: BlockType.paragraph,
                    runs: [InlineRun(text: 'hello reader. ' * 100)],
                  ),
                ],
              ),
            ],
          ),
        );
        await session.open();
        await session.prepareViewport(const Size(360, 280));
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 360,
                height: 280,
                child: TextPageView(session: session),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final blockFinder = find.byType(BlockSliceView).first;
      final view = tester.widget<BlockSliceView>(blockFinder);
      final painter = TextBlockLayout.createPainter(
        view.block,
        view.settings,
        tester.getSize(blockFinder).width,
      );
      final prefix = TextBlockLayout.prefixFor(
        view.block,
        view.settings,
      ).length;
      final box = painter
          .getBoxesForSelection(
            TextSelection(baseOffset: prefix, extentOffset: prefix + 5),
          )
          .first;
      final word = tester.getTopLeft(blockFinder) + box.toRect().center;
      painter.dispose();
      Future<void> select() async {
        await tester.longPressAt(word);
        await tester.pump();
      }

      final store = BookStoreService.instance;
      await select();
      await tester.tap(find.byKey(const Key('selection-underline')));
      await tester.pump();
      var saved = store.getBookState('annotations')!.annotations;
      expect(saved.single.text, 'hello');
      expect(saved.single.startOffset, 0);
      expect(saved.single.endOffset, 5);
      expect(saved.single.note, isNull);
      await tester.tapAt(word);
      await tester.pumpAndSettle();
      expect(find.text('No note — underline only'), findsOneWidget);
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('annotation-note-input')),
        'remember\nthis',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      saved = store.getBookState('annotations')!.annotations;
      expect(saved.single.note, 'remember\nthis');
      final originalId = saved.single.id;
      await tester.tapAt(word);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'remember\nthis',
      );
      await tester.enterText(find.byType(TextField), 'discarded');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(
        store.getBookState('annotations')!.annotations.single.note,
        'remember\nthis',
      );
      await select();
      await tester.tap(find.byKey(const Key('selection-note')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'second note');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(
        store.getBookState('annotations')!.annotations.last.note,
        'second note',
      );
      await settleIo(tester, () async {
        await session.nextPage();
        await store.flush();
        expect(store.getBookState('annotations')!.annotations.length, 2);
        await store.flush();
        await store.init(customFile: library);
        expect(
          store.getBookState('annotations')!.annotations.first.id,
          originalId,
        );
        expect(
          store.getBookState('annotations')!.annotations.first.note,
          'remember\nthis',
        );
        await session.prevPage();
      });
      // Refresh from the reopened library without retaining any local annotation list.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 360,
                height: 280,
                child: TextPageView(session: session),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (var remaining = 1; remaining >= 0; remaining--) {
        await tester.tapAt(word);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Delete'));
        await tester.pumpAndSettle();
        expect(
          store.getBookState('annotations')!.annotations.length,
          remaining,
        );
        expect(
          tester.widget<BlockSliceView>(blockFinder).annotations.length,
          remaining,
        );
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await settleIo(tester, () async {
        await store.flush();
        session.dispose();
        await store.flush();
        await store.init(customFile: library);
        expect(store.getBookState('annotations')!.annotations, isEmpty);
        store.dispose();
        await directory.delete(recursive: true);
      });
    },
  );
}

// Advance the widget zone while disk futures and the debounced store complete.
Future<void> settleIo(
  WidgetTester tester,
  Future<void> Function() action,
) async {
  var done = false;
  Object? failure;
  await tester.runAsync(() async {
    action().then(
      (_) => done = true,
      onError: (Object error) {
        failure = error;
        done = true;
      },
    );
  });
  for (var i = 0; !done && i < 200; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  if (failure != null) throw failure!;
  expect(done, isTrue, reason: 'Disk operation did not complete');
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eink_launcher/reader/controllers/text_reader_session.dart';
import 'package:eink_launcher/reader/models/doc_ref.dart';
import 'package:eink_launcher/reader/models/reading_position.dart';
import 'package:eink_launcher/reader/models/toc_entry.dart';
import 'package:eink_launcher/reader/services/book_store_service.dart';
import 'package:eink_launcher/reader/services/epub_parser_service.dart';
import 'package:eink_launcher/reader/services/pagination_cache_service.dart';

import 'tanach_compatibility_test.dart' as fixtures;

class _NoCache extends PaginationCacheService {
  @override
  Future<void> save(String key, pages) async {}
  @override
  Future<Never?> load(String key) async => null;
}

void main() {
  test(
    'filters, typography and reopening preserve verse and bookmark anchors',
    () async {
      final temp = Directory.systemTemp.createTempSync('tanach-session');
      final store = BookStoreService.instance;
      await store.init(customFile: File('${temp.path}/state.json'));
      final original = EpubParserService.parseBytesSync(fixtures.fixture());
      const doc = DocRef(
        id: 'tanach',
        path: '/tanach.epub',
        title: 'Tanach',
        format: DocFormat.epub,
        fileSize: 1,
      );
      TextReaderSession create() => TextReaderSession(
        doc: doc,
        bookStore: store,
        paginationCache: _NoCache(),
        bookLoader: (_, _) async => original,
      );
      var session = create();
      try {
        await session.open();
        expect(session.error, isNull);
        await session.prepareViewport(const Size(300, 400));
        await session.goToToc(
          TocEntry(
            title: 'Second verse',
            position: TextReadingPosition(
              spineIndex: 0,
              blockIndex: session.book!.spine.first.anchors['v-two']!,
              charOffset: 0,
            ),
          ),
        );
        await session.addBookmark('Second verse');
        await session.applySettings(
          session.settings.copyWith(inlineCommentary: false),
        );
        expect((session.position as TextReadingPosition).blockId, 'v-two');
        await session.applySettings(
          session.settings.copyWith(
            inlineCommentary: true,
            commentarySources: ['Rashi on Genesis'],
            commentaryLanguage: 'en',
            fontSizeStep: 5,
          ),
        );
        expect((session.position as TextReadingPosition).blockId, 'v-two');
        session.suspend();
        session.dispose();
        session = create();
        await session.open();
        expect(session.error, isNull);
        expect((session.position as TextReadingPosition).blockId, 'v-two');
        await session.prepareViewport(const Size(300, 400));
        await session.goToToc(
          TocEntry(
            title: 'Bookmark',
            position: session.bookmarks.single.position,
          ),
        );
        expect((session.position as TextReadingPosition).blockId, 'v-two');
      } finally {
        session.dispose();
        store.dispose();
        temp.deleteSync(recursive: true);
      }
    },
  );
}

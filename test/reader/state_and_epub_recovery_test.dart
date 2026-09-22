import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:eink_launcher/reader/models/book_state.dart';
import 'package:eink_launcher/reader/models/bookmark.dart';
import 'package:eink_launcher/reader/models/doc_ref.dart';
import 'package:eink_launcher/reader/models/reading_position.dart';
import 'package:eink_launcher/reader/services/book_store_service.dart';
import 'package:eink_launcher/reader/services/epub_parser_service.dart';
import 'package:flutter_test/flutter_test.dart';

BookState state(String id) => BookState(
  docId: id,
  lastPath: '/$id.pdf',
  format: DocFormat.pdf,
  lastRead: DateTime.utc(2026),
  position: const PdfReadingPosition(pageIndex: 0),
);
Uint8List fixture({String extraManifest = '', String? ncx}) {
  final archive = Archive()
    ..add(
      ArchiveFile.string(
        'META-INF/container.xml',
        '<container><rootfiles><rootfile full-path="book.opf"/></rootfiles></container>',
      ),
    )
    ..add(
      ArchiveFile.string(
        'book.opf',
        '<package><metadata><title>Test</title></metadata><manifest><item id="chapter" href="chapter.xhtml" media-type="application/xhtml+xml"/>$extraManifest</manifest><spine><itemref idref="chapter"/></spine></package>',
      ),
    )
    ..add(
      ArchiveFile.string(
        'chapter.xhtml',
        '<html><body><h1>Chapter</h1><p>Readable content.</p></body></html>',
      ),
    );
  if (ncx != null) archive.add(ArchiveFile.string('toc.ncx', ncx));
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

void main() {
  test(
    'valid nested bookmarks survive a corrupt sibling and a restart',
    () async {
      final dir = await Directory.systemTemp.createTemp('nested-state-');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/library.json');
      final good = Bookmark(
        id: 'keep',
        docId: 'good',
        createdAt: DateTime(2026),
        label: 'Keep this',
        position: const PdfReadingPosition(pageIndex: 3),
      );
      final value = state('good').toJson()
        ..['bookmarks'] = [
          good.toJson(),
          {'invalid': true},
        ];
      await file.writeAsString(
        jsonEncode({
          'version': 1,
          'books': {'good': value},
        }),
      );
      var store = BookStoreService.instance;
      await store.init(customFile: file);
      expect(store.getBookState('good')!.bookmarks.single.label, 'Keep this');
      await store.flush();
      store.dispose();
      store = BookStoreService.instance;
      await store.init(customFile: file);
      expect(
        store.getBookState('good')!.bookmarks.single.position,
        good.position,
      );
      expect(await File('${file.path}.corrupt').exists(), isTrue);
      store.dispose();
    },
  );

  test('unknown library versions remain untouched while known records are readable', () async {
    final dir = await Directory.systemTemp.createTemp('future-state-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/library.json');
    final original = jsonEncode({
      'version': 999,
      'books': {'good': state('good').toJson()},
      'future': 'retain',
    });
    await file.writeAsString(original);
    final store = BookStoreService.instance;
    await store.init(customFile: file);
    expect(store.getBookState('good'), isNotNull);
    expect(store.writesBlocked, isTrue);
    store.saveBookState(state('new'));
    await store.flush();
    expect(await file.readAsString(), original);
    store.dispose();
  });

  test(
    'failed writes retain dirty state and retry persists every pending record',
    () async {
      final dir = await Directory.systemTemp.createTemp('retry-state-');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/library.json');
      final store = BookStoreService.instance;
      await store.init(customFile: file);
      final obstruction = Directory('${file.path}.tmp');
      await obstruction.create();
      store.saveBookState(state('one'));
      await store.flush();
      expect(store.hasUnsavedChanges, isTrue);
      expect(store.saveError.value, isNotNull);
      store.saveBookState(state('two'));
      await obstruction.delete();
      await store.flush();
      expect(store.saveError.value, isNull);
      expect(store.hasUnsavedChanges, isFalse);
      expect(
        (jsonDecode(await file.readAsString())['books'] as Map).keys,
        containsAll(['one', 'two']),
      );
      store.dispose();
    },
  );
  test(
    'One invalid book must not hide unrelated valid reading state',
    () async {
      final dir = await Directory.systemTemp.createTemp('review-state-');
      final file = File('${dir.path}/library.json');
      final good = state('good').toJson();
      final bad = state('bad').toJson()..['format'] = 'unknown-future-format';
      await file.writeAsString(
        jsonEncode({
          'version': 1,
          'books': {'good': good, 'bad': bad},
        }),
      );
      final store = BookStoreService.instance;
      await store.init(customFile: file);
      final restored = store.getBookState('good');
      final backup = await File('${file.path}.corrupt').exists();
      store.dispose();
      await dir.delete(recursive: true);
      expect(backup, isTrue);
      expect(restored, isNotNull);
    },
  );
  test('A failed reading-state write must report that saving failed', () async {
    final dir = await Directory.systemTemp.createTemp('review-write-');
    final file = File('${dir.path}/library.json');
    final store = BookStoreService.instance;
    await store.init(customFile: file);
    await Directory('${file.path}.tmp').create(); // deterministic write failure
    store.saveBookState(state('new'));
    await store.flush();
    final warning = store.recoveryWarning;
    final exists = await file.exists();
    store.dispose();
    await dir.delete(recursive: true);
    expect(exists, isFalse);
    expect(warning, isNotNull);
  });
  test('Missing non-spine XHTML must not block readable EPUB chapters', () {
    final bytes = fixture(
      extraManifest: '<item id="unused" href="unused.xhtml" media-type="application/xhtml+xml"/>',
    );
    expect(() => EpubParserService.parseBytesSync(bytes), returnsNormally);
  });
  test('Invalid NCX must fall back to chapter headings', () {
    final bytes = fixture(
      extraManifest: '<item id="toc" href="toc.ncx" media-type="application/x-dtbncx+xml"/>',
      ncx: '<ncx><broken>',
    );
    expect(() => EpubParserService.parseBytesSync(bytes), returnsNormally);
  });
}

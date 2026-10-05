import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:eink_launcher/reader/models/doc_ref.dart';
import 'package:eink_launcher/reader/models/parsed_book.dart';
import 'package:eink_launcher/reader/models/reader_settings.dart';
import 'package:eink_launcher/reader/services/parsed_epub_cache_service.dart';
import 'package:eink_launcher/reader/services/tanach_sqlite_cache_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('study-sidecar-test-');
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('sidecar path replaces the .epub extension', () {
    expect(
      TanachSqliteCacheService.sidecarPathForEpub('/books/berakhot.epub'),
      '/books/berakhot.study.sqlite',
    );
    expect(
      TanachSqliteCacheService.sidecarPathForEpub('/books/BERAKHOT.EPUB'),
      '/books/BERAKHOT.study.sqlite',
    );
  });

  test('laptop fingerprint matches the device file hash', () async {
    // The device computes sha256 over the raw file bytes
    // (ParsedEpubCacheService._fingerprint); the laptop tool must hash the
    // identical bytes or every sidecar fails validation.
    final epub = File('${directory.path}/tamid.epub');
    await epub.writeAsBytes([1, 2, 3, 4, 5]);
    final bytes = await epub.readAsBytes();
    final laptop = sha256.convert(bytes).toString();
    final device = (await sha256.bind(epub.openRead()).first).toString();
    expect(laptop, device);
  });

  test('adoptSidecar copies a current sidecar into the cache', () async {
    final epub = File('${directory.path}/tamid.epub');
    await epub.writeAsString('epub bytes');
    final fingerprint =
        (await sha256.bind(epub.openRead()).first).toString();
    final doc = DocRef(
      id: 'tamid-test',
      path: epub.path,
      format: DocFormat.epub,
      title: 'Tamid',
      fileSize: await epub.length(),
    );
    final service = TanachSqliteCacheService(
      cacheDirectory: Directory('${directory.path}/cache'),
    );
    await TanachSqliteCacheService.writeDatabaseForExport(
      TanachSqliteCacheService.sidecarPathForEpub(epub.path),
      _book(),
      fingerprint,
    );

    final adopted = await service.adoptSidecar(doc, fingerprint: fingerprint);
    expect(adopted, isNotNull);
    expect(adopted!.hasLazyTanachContent, isTrue);
    expect(adopted.spine.every((item) => item.isLazy), isTrue);

    // The internal cache now serves it with no sidecar needed.
    final reopened = await service.loadIfCurrent(doc, fingerprint: fingerprint);
    expect(reopened, isNotNull);

    final chapter = await service.loadChapter(
      adopted,
      0,
      const ReaderSettings(commentarySources: ['Rashi on Genesis']),
    );
    expect(chapter.plainTextForTest, contains('Commentary text'));
  });

  test('adoptSidecar ignores stale and corrupt sidecars', () async {
    final epub = File('${directory.path}/tamid.epub');
    await epub.writeAsString('epub bytes');
    final fingerprint =
        (await sha256.bind(epub.openRead()).first).toString();
    final doc = DocRef(
      id: 'tamid-test',
      path: epub.path,
      format: DocFormat.epub,
      title: 'Tamid',
      fileSize: await epub.length(),
    );
    final service = TanachSqliteCacheService(
      cacheDirectory: Directory('${directory.path}/cache'),
    );

    // Stale: sidecar built for different EPUB bytes.
    await TanachSqliteCacheService.writeDatabaseForExport(
      TanachSqliteCacheService.sidecarPathForEpub(epub.path),
      _book(),
      'stale-fingerprint',
    );
    expect(
      await service.adoptSidecar(doc, fingerprint: fingerprint),
      isNull,
    );
    expect(await service.loadIfCurrent(doc, fingerprint: fingerprint), isNull);

    // Corrupt: not a database at all.
    await File(
      TanachSqliteCacheService.sidecarPathForEpub(epub.path),
    ).writeAsString('not a database');
    expect(
      await service.adoptSidecar(doc, fingerprint: fingerprint),
      isNull,
    );

    // Missing: no sidecar file.
    await File(
      TanachSqliteCacheService.sidecarPathForEpub(epub.path),
    ).delete();
    expect(
      await service.adoptSidecar(doc, fingerprint: fingerprint),
      isNull,
    );
  });

  test('ParsedEpubCacheService.load uses the sidecar without parsing',
      () async {
    final epub = File('${directory.path}/tamid.epub');
    await epub.writeAsString('epub bytes');
    final doc = DocRef(
      id: 'tamid-load-test',
      path: epub.path,
      format: DocFormat.epub,
      title: 'Tamid',
      fileSize: await epub.length(),
    );
    final fingerprint =
        (await sha256.bind(epub.openRead()).first).toString();
    await TanachSqliteCacheService.writeDatabaseForExport(
      TanachSqliteCacheService.sidecarPathForEpub(epub.path),
      _book(),
      fingerprint,
    );

    final cache = ParsedEpubCacheService(
      cacheDirectory: Directory('${directory.path}/parsed'),
    );
    final book = await cache.load(
      doc,
      true,
      parser: () => throw StateError('must not parse when sidecar exists'),
    );
    expect(book.hasLazyTanachContent, isTrue);
    expect(book.spine, hasLength(2));
  });
}

ParsedBook _book() => ParsedBook(
      title: 'Genesis',
      contentFingerprint: 'content-fingerprint',
      spine: [
        ParsedSpineItem(
          id: 'chapter-1',
          href: 'text/chapter-1.xhtml',
          title: 'Genesis 1',
          blocks: [],
        ),
        ParsedSpineItem(
          id: 'chapter-2',
          href: 'text/chapter-2.xhtml',
          title: 'Genesis 2',
          blocks: [],
        ),
      ],
      studyDocuments: {
        'text/chapter-1.xhtml': _chapter(1),
        'text/chapter-2.xhtml': _chapter(2),
      },
    );

String _chapter(int chapter) => '''
<html xmlns="http://www.w3.org/1999/xhtml"
      xmlns:epub="http://www.idpf.org/2007/ops">
<body>
  <section class="verse" id="v-genesis-$chapter-1" data-ref="Genesis $chapter:1">
    <h2>Verse 1</h2>
    <div class="hebrew" lang="he" dir="rtl">text</div>
    <div class="translation" lang="en" dir="ltr"
         data-edition="metsudah" data-primary="true"
         data-translation-label="Metsudah">Primary translation</div>
    <p><a epub:type="noteref" href="#index-$chapter">Notes</a></p>
  </section>
  <aside epub:type="footnote" data-category="index" id="index-$chapter">
    <a epub:type="noteref" href="#rashi-$chapter">Rashi</a>
  </aside>
  <aside epub:type="footnote" class="commentary-note" id="rashi-$chapter"
         data-category="rishon" data-source="Rashi on Genesis"
         data-ref="Rashi on Genesis $chapter:1">
    <p class="note-title">Rashi</p>
    <div class="note-en" lang="en"><p>Commentary text chapter $chapter</p></div>
  </aside>
</body>
</html>
''';

extension on ParsedSpineItem {
  String get plainTextForTest =>
      blocks.map((block) => block.plainText).join('\n');
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:eink_launcher/reader/models/book_state.dart';
import 'package:eink_launcher/reader/models/doc_ref.dart';
import 'package:eink_launcher/reader/models/reading_position.dart';
import 'package:eink_launcher/reader/models/reader_settings.dart';
import 'package:eink_launcher/reader/services/book_store_service.dart';

void main() {
  late Directory tempDir;
  late File libraryFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('book_store_test_');
    libraryFile = File('${tempDir.path}/library.json');
    await BookStoreService.instance.init(customFile: libraryFile);
  });

  tearDown(() async {
    BookStoreService.instance.dispose();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('persists book state atomically and restores it on reload', () async {
    final state = BookState(
      docId: 'test-doc-id-123',
      lastPath: '/storage/books/test.pdf',
      format: DocFormat.pdf,
      lastRead: DateTime.utc(2025, 1, 1),
      position: const PdfReadingPosition(pageIndex: 5, withinPage: 0.5),
      percent: 0.25,
      settingsOverride: const ReaderSettings(fontSizeStep: 5),
      uniformPdfCrop: const [0.1, 0.2, 0.9, 0.8],
    );

    BookStoreService.instance.saveBookState(state);
    await BookStoreService.instance.flush();

    expect(await libraryFile.exists(), isTrue);

    // Re-initialize with same file to verify reload
    BookStoreService.instance.dispose();
    await BookStoreService.instance.init(customFile: libraryFile);

    final restored = BookStoreService.instance.getBookState('test-doc-id-123');
    expect(restored, isNotNull);
    expect(restored!.docId, equals('test-doc-id-123'));
    expect(restored.percent, equals(0.25));
    expect((restored.position as PdfReadingPosition).pageIndex, equals(5));
    expect((restored.position as PdfReadingPosition).withinPage, equals(0.5));
    expect(restored.settingsOverride?.fontSizeStep, equals(5));
    expect(restored.uniformPdfCrop, equals([0.1, 0.2, 0.9, 0.8]));
  });

  test('falls back to global settings when no override exists', () {
    const customGlobal = ReaderSettings(lineHeight: 1.8);
    BookStoreService.instance.saveGlobalSettings(customGlobal);

    final resolved = BookStoreService.instance.getSettingsForDoc(
      'non-existent',
    );
    expect(resolved.lineHeight, equals(1.8));
  });

  test('overlapping lifecycle flushes persist the latest state without temp-file races', () async {
    final store = BookStoreService.instance;
    final writes = <Future<void>>[];
    for (var page = 0; page < 20; page++) {
      store.saveBookState(
        BookState(
          docId: 'concurrent',
          lastPath: '/book.pdf',
          format: DocFormat.pdf,
          lastRead: DateTime(2026),
          position: PdfReadingPosition(pageIndex: page),
        ),
      );
      writes.add(store.flush());
    }
    await Future.wait(writes);
    expect(await File('${libraryFile.path}.tmp').exists(), isFalse);
    store.dispose();
    await BookStoreService.instance.init(customFile: libraryFile);
    expect(
      BookStoreService.instance.getBookState('concurrent')?.position,
      const PdfReadingPosition(pageIndex: 19),
    );
  });
}

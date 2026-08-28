import 'package:flutter_test/flutter_test.dart';

import 'package:eink_launcher/services/file_mime_type_service.dart';

void main() {
  test('maps common document and ebook extensions precisely', () {
    expect(
      FileMimeTypeService.forPath('/books/novel.epub'),
      'application/epub+zip',
    );
    expect(
      FileMimeTypeService.forPath('/documents/report.docx'),
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    );
    expect(FileMimeTypeService.forPath('/documents/notes.md'), 'text/markdown');
    expect(
      FileMimeTypeService.forPath('/documents/manual.pdf'),
      'application/pdf',
    );
    expect(FileMimeTypeService.forPath('/documents/readme.txt'), 'text/plain');
  });

  test('matches extensions without case sensitivity', () {
    expect(FileMimeTypeService.forPath('/Pictures/SCAN.JPEG'), 'image/jpeg');
    expect(
      FileMimeTypeService.forPath('/Books/NOVEL.EPUB'),
      'application/epub+zip',
    );
  });

  test('uses a constrained binary fallback instead of wildcard MIME', () {
    expect(
      FileMimeTypeService.forPath('/files/archive.unknown-extension'),
      FileMimeTypeService.fallbackType,
    );
    expect(
      FileMimeTypeService.forPath('/files/no-extension'),
      FileMimeTypeService.fallbackType,
    );
    expect(FileMimeTypeService.fallbackType, isNot('*/*'));
  });
}

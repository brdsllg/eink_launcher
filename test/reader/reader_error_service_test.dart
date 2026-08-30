import 'dart:io';

import 'package:eink_launcher/reader/models/doc_ref.dart';
import 'package:eink_launcher/reader/models/reader_exception.dart';
import 'package:eink_launcher/reader/services/reader_error_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('preserves safe typed messages, including encrypted EPUB failures', () {
    const failure = EncryptedEpubException(
      resourcePath: 'private/chapter.xhtml',
      algorithm: 'unknown',
    );
    expect(readerErrorMessage(failure, DocFormat.epub), failure.message);
    expect(
      readerErrorMessage(const ReaderException('Safe message'), DocFormat.pdf),
      'Safe message',
    );
  });

  test('maps missing files and denied access without leaking paths', () {
    for (final code in [2, 3]) {
      final message = readerErrorMessage(
        FileSystemException(
          'internal',
          '/private/book',
          OSError('missing', code),
        ),
        DocFormat.pdf,
      );
      expect(message, contains('no longer available'));
      expect(message, isNot(contains('/private')));
    }
    for (final code in [5, 13]) {
      expect(
        readerErrorMessage(
          FileSystemException(
            'internal',
            '/private/book',
            OSError('denied', code),
          ),
          DocFormat.epub,
        ),
        contains('permissions'),
      );
    }
    expect(
      readerErrorMessage(
        const FileSystemException('unreadable'),
        DocFormat.txt,
      ),
      contains('Could not read this file'),
    );
  });

  test(
    'formats malformed documents and memory failures as recovery guidance',
    () {
      expect(
        readerErrorMessage(OutOfMemoryError(), DocFormat.pdf),
        contains('not enough memory'),
      );
      for (final format in DocFormat.values) {
        final message = readerErrorMessage(
          const FormatException('private parser detail'),
          format,
        );
        expect(message, contains('Try again'));
        expect(message, isNot(contains('private parser detail')));
      }
    },
  );
}

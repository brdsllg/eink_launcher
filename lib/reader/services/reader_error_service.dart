import 'dart:io';

import '../models/doc_ref.dart';
import '../models/reader_exception.dart';

/// Keeps platform paths, stack traces, and parser internals out of fallback UI.
String readerErrorMessage(Object error, DocFormat format) {
  if (error is ReaderException) return error.message;
  if (error is OutOfMemoryError) {
    return 'There is not enough memory to read this document. Close other apps and try again.';
  }
  if (error is FileSystemException) {
    final code = error.osError?.errorCode;
    if (error is PathNotFoundException || code == 2 || code == 3) {
      return 'This file is no longer available. Return to files and select it again, or restore it and retry.';
    }
    if (code == 5 || code == 13) {
      return 'Access to this file was denied. Check storage permissions and try again.';
    }
    return 'Could not read this file. Check that it is available and try again.';
  }
  return switch (format) {
    DocFormat.pdf => 'Could not read this PDF. It may be damaged, password-protected, or unsupported. Try again or choose another file.',
    DocFormat.epub => 'Could not read this EPUB. It may be damaged or have an unsupported structure. Try again or choose another file.',
    DocFormat.txt || DocFormat.markdown =>
      'Could not prepare this text document. Try again or choose another file.',
  };
}

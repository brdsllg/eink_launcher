import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// A rename must never overwrite a name created after the browser's listing.
/// Do not fall back to dart:io rename (which replaces existing destinations).
void renameWithoutReplacing(String source, String destination) {
  if (File(source).absolute.path == File(destination).absolute.path) return;
  if (Platform.isWindows) {
    final library = DynamicLibrary.open('kernel32.dll');
    final move = library
        .lookupFunction<
          Int32 Function(Pointer<Utf16>, Pointer<Utf16>),
          int Function(Pointer<Utf16>, Pointer<Utf16>)
        >('MoveFileW');
    final getError = library.lookupFunction<Uint32 Function(), int Function()>(
      'GetLastError',
    );
    final from = source.toNativeUtf16();
    final to = destination.toNativeUtf16();
    try {
      if (move(from, to) == 0) {
        final code = getError();
        throw FileSystemException(
          'Could not rename without replacing the destination',
          source,
          OSError('MoveFileW failed', code),
        );
      }
    } finally {
      calloc.free(from);
      calloc.free(to);
    }
    return;
  }
  if (Platform.isAndroid || Platform.isLinux) {
    final library = DynamicLibrary.open(
      Platform.isAndroid ? 'libc.so' : 'libc.so.6',
    );
    if (!library.providesSymbol('renameat2')) {
      throw const FileSystemException(
        'Safe rename requires a system with renameat2 support.',
      );
    }
    final move = library
        .lookupFunction<
          Int32 Function(Int32, Pointer<Utf8>, Int32, Pointer<Utf8>, Uint32),
          int Function(int, Pointer<Utf8>, int, Pointer<Utf8>, int)
        >('renameat2');
    final errno = library
        .lookupFunction<Pointer<Int32> Function(), Pointer<Int32> Function()>(
          Platform.isAndroid ? '__errno' : '__errno_location',
        );
    final from = source.toNativeUtf8();
    final to = destination.toNativeUtf8();
    try {
      // AT_FDCWD and RENAME_NOREPLACE, supported by Android 11+ libc.
      if (move(-100, from, -100, to, 1) != 0) {
        final code = errno().value;
        throw FileSystemException(
          'Could not rename without replacing the destination',
          source,
          OSError('renameat2 failed', code),
        );
      }
    } finally {
      calloc.free(from);
      calloc.free(to);
    }
    return;
  }
  throw const FileSystemException(
    'Safe rename is unsupported on this platform.',
  );
}

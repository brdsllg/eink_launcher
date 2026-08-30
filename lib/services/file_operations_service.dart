import 'dart:io';

import '../models/clipboard_state.dart';

// All filesystem mutation for the file browser lives here so the screen stays
// about layout/interaction. Uses only dart:io — no new packages.
//
// Paths throughout are absolute 'Unix-style' paths. On the Android target
// Dart's File/Directory always report '/'-separated absolute paths, and the
// rest of the codebase (constants.dart, main.dart) hardcodes '/' too, so we
// stay consistent with that rather than mixing in Platform.pathSeparator.
//
// Every mutation is wrapped so a permission error on one item can't abort the
// rest; failing items are reported back as human-readable messages rather than
// thrown up into the UI.
class FileOperationsService {
  ClipboardState? _clipboard;

  ClipboardState? get clipboard => _clipboard;
  bool get hasClipboard => _clipboard != null && _clipboard!.paths.isNotEmpty;

  void copy(List<String> paths) {
    _clipboard = ClipboardState(
      paths: List.of(paths),
      mode: ClipboardMode.copy,
    );
  }

  void cut(List<String> paths) {
    _clipboard = ClipboardState(paths: List.of(paths), mode: ClipboardMode.cut);
  }

  void clearClipboard() {
    _clipboard = null;
  }

  // ---------------------------------------------------------------------------
  // New folder / rename / delete
  // ---------------------------------------------------------------------------

  /// Creates an empty folder named [name] inside [parentPath].
  /// Throws on failure (permission, invalid name, existing path).
  Future<void> createFolder(String parentPath, String name) {
    return Directory('$parentPath/$name').create();
  }

  /// Renames the entry at [path] in place to [newName] (same parent).
  /// Throws on failure.
  Future<void> renameEntry(String path, String newName) async {
    final parent = _parentOf(path);
    final newPath = '$parent/$newName';
    if (Directory(path).existsSync()) {
      await Directory(path).rename(newPath);
    } else {
      await File(path).rename(newPath);
    }
  }

  /// Deletes each of [paths]. Folders are removed recursively.
  /// Returns a list of error messages — empty on full success. One failed item
  /// never blocks the others.
  Future<List<String>> deleteEntries(List<String> paths) async {
    final errors = <String>[];
    for (final path in paths) {
      try {
        final entity = FileSystemEntity.typeSync(path, followLinks: false);
        if (entity == FileSystemEntityType.directory) {
          await Directory(path).delete(recursive: true);
        } else {
          await File(path).delete();
        }
      } catch (e) {
        errors.add('Could not delete ${_basename(path)}: $e');
      }
    }
    return errors;
  }

  // ---------------------------------------------------------------------------
  // Paste
  // ---------------------------------------------------------------------------

  /// Pastes every clipboard item into [destinationDir] (the currently viewed
  /// folder). Returns a list of error messages — empty on full success.
  ///
  /// The clipboard is single-use: after everything pastes successfully it is
  /// cleared, so the same items can't be pasted again (regardless of copy or
  /// cut). If any item fails, the clipboard is kept so the user can retry the
  /// remaining items.
  Future<List<String>> paste(String destinationDir) async {
    final state = _clipboard;
    if (state == null || state.paths.isEmpty) return const [];

    final errors = <String>[];
    // The moving flag must be decided up front from the pre-clear snapshot;
    // for a cut-paste it's also why the clipboard is only cleared once ALL
    // items have moved successfully.
    final moving = state.mode == ClipboardMode.cut;

    for (final src in state.paths) {
      try {
        await _pasteOne(src, destinationDir, moving);
      } catch (e) {
        errors.add('Could not paste ${_basename(src)}: $e');
      }
    }

    // Single-use clipboard: clear it once the paste fully succeeded, so you
    // can't keep re-pasting the same copied/cut item.
    if (errors.isEmpty) {
      _clipboard = null;
    }

    return errors;
  }

  Future<void> _pasteOne(String src, String destinationDir, bool moving) async {
    final srcType = FileSystemEntity.typeSync(src, followLinks: false);

    // A folder pasted into itself (or one of its own descendants) would
    // recurse forever — detect that up front and refuse.
    if (srcType == FileSystemEntityType.directory) {
      final srcNorm = src.endsWith('/') ? src : '$src/';
      final destNorm = destinationDir.endsWith('/')
          ? destinationDir
          : '$destinationDir/';
      if (destNorm == srcNorm || destNorm.startsWith(srcNorm)) {
        throw Exception('cannot paste a folder into itself');
      }
    }

    final name = _basename(src);
    final dest = _uniqueDestination(destinationDir, name);

    if (moving) {
      // Cut = move. Same-volume renames are the fast path and never need a
      // copy; if that fails (e.g. different mount) fall back to copy + remove.
      await _moveForPaste(src, dest, srcType);
    } else if (srcType == FileSystemEntityType.directory) {
      await _copyDirectoryRecursive(src, dest);
    } else {
      await File(src).copy(dest);
    }
  }

  /// Moves [src] to [dest]. Tries a plain rename first (fast, same volume);
  /// on any failure copies recursively and removes the original.
  Future<void> _moveForPaste(
    String src,
    String dest,
    FileSystemEntityType srcType,
  ) async {
    try {
      if (srcType == FileSystemEntityType.directory) {
        await Directory(src).rename(dest);
      } else {
        await File(src).rename(dest);
      }
      return;
    } catch (_) {
      // rename() failed — likely a cross-device move. Fall back to copy+delete.
    }

    if (srcType == FileSystemEntityType.directory) {
      await _copyDirectoryRecursive(src, dest);
      await Directory(src).delete(recursive: true);
    } else {
      await File(src).copy(dest);
      await File(src).delete();
    }
  }

  /// Recursively copies [src] (a directory) into [dest]. Symlinks are copied
  /// as links, never followed, so a link pointing back at an ancestor can't
  /// make this recurse forever.
  Future<void> _copyDirectoryRecursive(String src, String dest) async {
    await Directory(dest).create(recursive: true);
    final entities = Directory(src).listSync(followLinks: false);
    final fileFutures = <Future<void>>[];

    for (final entity in entities) {
      final childName = _basename(entity.path);
      final childDest = '$dest/$childName';
      final type = FileSystemEntity.typeSync(entity.path, followLinks: false);

      if (type == FileSystemEntityType.directory) {
        await _copyDirectoryRecursive(entity.path, childDest);
      } else if (type == FileSystemEntityType.file) {
        fileFutures.add(File(entity.path).copy(childDest));
      } else {
        // Symbolic link (or other special entry): recreate it at the
        // destination, pointing at the same target. Links are never followed,
        // so a link back to an ancestor can't cause recursion.
        try {
          final link = Link(entity.path);
          final target = link.targetSync();
          await Link(childDest).create(target);
        } catch (_) {
          // Unreadable/undeletable link target — ignore rather than abort.
        }
      }
    }

    if (fileFutures.isNotEmpty) {
      await Future.wait(fileFutures);
    }
  }

  /// Returns a destination path inside [dir] for [name] that doesn't exist yet.
  /// On a clash it appends " (1)", " (2)", … — before the extension for files,
  /// after the bare name for folders — and never overwrites.
  String _uniqueDestination(String dir, String name) {
    var candidate = '$dir/$name';
    if (!_exists(candidate)) return candidate;

    // Split name into base and (for files) extension.
    final dot = name.lastIndexOf('.');
    final isDotfile = name.startsWith('.');
    final hasExt = !isDotfile && dot > 0 && dot < name.length - 1;
    final base = hasExt ? name.substring(0, dot) : name;
    final ext = hasExt ? name.substring(dot) : '';

    var i = 1;
    while (true) {
      candidate = '$dir/$base ($i)$ext';
      if (!_exists(candidate)) return candidate;
      i++;
    }
  }

  bool _exists(String path) {
    return FileSystemEntity.typeSync(path, followLinks: false) !=
        FileSystemEntityType.notFound;
  }

  // ---------------------------------------------------------------------------
  // Small helpers
  // ---------------------------------------------------------------------------

  String _basename(String path) {
    final trimmed = path.endsWith('/')
        ? path.substring(0, path.length - 1)
        : path;
    return trimmed.split('/').last;
  }

  String _parentOf(String path) {
    final trimmed = path.endsWith('/')
        ? path.substring(0, path.length - 1)
        : path;
    final idx = trimmed.lastIndexOf('/');
    return idx <= 0 ? '/' : trimmed.substring(0, idx);
  }
}

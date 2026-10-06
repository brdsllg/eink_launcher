import 'dart:convert';
import 'dart:io';

import '../constants.dart';
import '../models/clipboard_state.dart';
import 'no_replace_rename.dart';

// All filesystem mutation for the file browser lives here so the screen stays
// about layout/interaction. Uses only dart:io — no new packages.
//
// Android paths use '/'. Host verification on Windows also receives native
// backslashes from directory listings; normalize those only on Windows.
//
// Every mutation is wrapped so a permission error on one item can't abort the
// rest; failing items are reported back as human-readable messages rather than
// thrown up into the UI.
class FileOperationsService {
  /// [trashRoot], [now] and [trashRetention] exist so tests can point the
  /// recycle bin at a temp folder and move the clock.
  FileOperationsService({
    String? trashRoot,
    DateTime Function()? now,
    Duration? trashRetention,
  }) : _trashRoot = trashRoot ?? kTrashRoot,
       _now = now ?? DateTime.now,
       _trashRetention = trashRetention ?? kTrashRetention;

  final String _trashRoot;
  final DateTime Function() _now;
  final Duration _trashRetention;
  Future<void> _trashQueue = Future<void>.value();

  ClipboardState? _clipboard;
  Future<List<String>>? _activePaste;

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
    _checkSingleFileName(name, 'name');
    return Directory('$parentPath/$name').create();
  }

  static void _checkSingleFileName(String value, String paramName) {
    if (value.isEmpty ||
        value == '.' ||
        value == '..' ||
        value.contains('/') ||
        value.contains('\\') ||
        value.contains('\u0000')) {
      throw ArgumentError.value(value, paramName, 'Expected a single file name');
    }
  }

  /// Renames the entry at [path] in place to [newName] (same parent).
  /// Throws on failure.
  Future<void> renameEntry(String path, String newName) async {
    _checkSingleFileName(newName, 'newName');
    final parent = _parentOf(path);
    final newPath = '$parent/$newName';
    renameWithoutReplacing(path, newPath);
  }

  /// Deletes each of [paths]. Folders are removed recursively.
  /// Returns a list of error messages — empty on full success. One failed item
  /// never blocks the others.
  Future<List<String>> deleteEntries(List<String> paths) async {
    final errors = <String>[];
    for (final path in paths) {
      try {
        final entity = await FileSystemEntity.type(path, followLinks: false);
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
  // Recycle bin
  //
  // Deleted items are moved (an instant rename on the same volume) into
  // [trashItemsDir]. A small JSON index beside that folder remembers where each
  // item came from and when it was deleted, so it can be restored and purged
  // once it is older than the retention period. Every bin mutation runs one at
  // a time through [_serialized] because each one read-modify-writes the index.
  // ---------------------------------------------------------------------------

  /// The hidden folder that holds the bin ([trashItemsDir] and the index).
  String get trashRoot => _trashRoot;

  /// The folder the user browses as the Recycle Bin.
  String get trashItemsDir => '$_trashRoot/items';

  String get _trashIndexPath => '$_trashRoot/index.json';

  /// True for the bin folder itself and anything inside it.
  bool isInTrash(String path) {
    final p = _slashed(path);
    final items = _slashed(trashItemsDir);
    return p == items || p.startsWith('$items/');
  }

  /// True only for the bin's top level, where items still have a record of
  /// where they came from (and so can be restored).
  bool isTrashRoot(String path) => _slashed(path) == _slashed(trashItemsDir);

  /// Creates the bin folder if needed so it can be listed while still empty.
  Future<void> ensureTrashDir() async {
    try {
      await Directory(trashItemsDir).create(recursive: true);
    } catch (_) {
      // Listing the folder will report the problem.
    }
  }

  /// Moves each of [paths] into the bin instead of deleting it. Returns error
  /// messages — empty on full success. One failed item never blocks the others.
  Future<List<String>> trashEntries(List<String> paths) {
    return _serialized(() async {
      try {
        await Directory(trashItemsDir).create(recursive: true);
      } catch (e) {
        return ['Could not open the Recycle Bin: $e'];
      }
      final errors = <String>[];
      final index = await _readTrashIndex();
      for (final path in paths) {
        try {
          final type = await FileSystemEntity.type(path, followLinks: false);
          if (type == FileSystemEntityType.notFound) {
            throw const FileSystemException('No longer exists');
          }
          final dest = await _uniqueDestinationAsync(
            trashItemsDir,
            _basename(path),
          );
          await _moveForPaste(path, dest, type);
          index[_basename(dest)] = _TrashRecord(
            originalPath: _slashed(path),
            deletedAt: _now(),
          );
        } catch (e) {
          errors.add('Could not delete ${_basename(path)}: $e');
        }
      }
      await _writeTrashIndex(index);
      return errors;
    });
  }

  /// Moves each of [paths] (top-level bin items) back to the folder it was
  /// deleted from, recreating that folder if it is gone. A name clash gets a
  /// " (1)" suffix, never an overwrite. Returns error messages.
  Future<List<String>> restoreEntries(List<String> paths) {
    return _serialized(() async {
      final errors = <String>[];
      final index = await _readTrashIndex();
      for (final path in paths) {
        final name = _basename(path);
        try {
          final type = await FileSystemEntity.type(path, followLinks: false);
          if (type == FileSystemEntityType.notFound) {
            index.remove(name);
            throw const FileSystemException('No longer in the Recycle Bin');
          }
          final original = index[name]?.originalPath;
          // Without a record (index lost) fall back to the storage root.
          final targetDir = original != null
              ? _parentOf(original)
              : _parentOf(_trashRoot);
          final targetName = original != null ? _basename(original) : name;
          await Directory(targetDir).create(recursive: true);
          final dest = await _uniqueDestinationAsync(targetDir, targetName);
          await _moveForPaste(path, dest, type);
          index.remove(name);
        } catch (e) {
          errors.add('Could not restore $name: $e');
        }
      }
      await _writeTrashIndex(index);
      return errors;
    });
  }

  /// Permanently deletes items that are already in the bin, and forgets them.
  Future<List<String>> deleteFromTrash(List<String> paths) {
    return _serialized(() => _deleteTrashItems(paths));
  }

  /// Permanently deletes everything in the bin. Returns error messages.
  Future<List<String>> emptyTrash() {
    return _serialized(() async {
      final List<String> paths;
      try {
        final dir = Directory(trashItemsDir);
        paths = await dir.exists()
            ? await dir.list(followLinks: false).map((e) => e.path).toList()
            : <String>[];
      } catch (e) {
        return ['Could not read the Recycle Bin: $e'];
      }
      return _deleteTrashItems(paths);
    });
  }

  Future<List<String>> _deleteTrashItems(List<String> paths) async {
    final errors = await deleteEntries(paths);
    final index = await _readTrashIndex();
    var changed = false;
    for (final path in paths) {
      final name = _basename(path);
      if (index.containsKey(name) &&
          await FileSystemEntity.type(path, followLinks: false) ==
              FileSystemEntityType.notFound) {
        index.remove(name);
        changed = true;
      }
    }
    if (changed) await _writeTrashIndex(index);
    return errors;
  }

  /// Whole days left before each top-level bin item is purged (rounded up, so
  /// a fresh item shows 30), keyed by the item's name in the bin.
  Future<Map<String, int>> trashDaysRemaining() async {
    final now = _now();
    final index = await _readTrashIndex();
    return {
      for (final entry in index.entries)
        entry.key:
            (entry.value.deletedAt
                        .add(_trashRetention)
                        .difference(now)
                        .inMinutes /
                    Duration.minutesPerDay)
                .ceil()
                .clamp(0, _trashRetention.inDays)
                .toInt(),
    };
  }

  /// Permanently deletes bin items older than the retention period (30 days).
  /// Returns how many were removed. Items with no record — e.g. the index was
  /// lost — are given a fresh deletion time rather than purged, so nothing is
  /// ever removed on a guess.
  Future<int> purgeExpiredTrash() {
    return _serialized(() async {
      final dir = Directory(trashItemsDir);
      final List<FileSystemEntity> items;
      try {
        if (!await dir.exists()) return 0;
        items = await dir.list(followLinks: false).toList();
      } catch (_) {
        return 0;
      }

      final index = await _readTrashIndex();
      final cutoff = _now().subtract(_trashRetention);
      final present = <String>{};
      var purged = 0;
      var changed = false;

      for (final item in items) {
        final name = _basename(item.path);
        present.add(name);
        final record = index[name];
        if (record == null) {
          index[name] = _TrashRecord(originalPath: null, deletedAt: _now());
          changed = true;
        } else if (record.deletedAt.isBefore(cutoff)) {
          try {
            if (await FileSystemEntity.type(item.path, followLinks: false) ==
                FileSystemEntityType.directory) {
              await Directory(item.path).delete(recursive: true);
            } else {
              await File(item.path).delete();
            }
            index.remove(name);
            purged++;
            changed = true;
          } catch (_) {
            // Try again on the next purge.
          }
        }
      }

      // Forget records whose item is no longer in the bin.
      final stale = index.keys.where((k) => !present.contains(k)).toList();
      for (final key in stale) {
        index.remove(key);
        changed = true;
      }
      if (changed) await _writeTrashIndex(index);
      return purged;
    });
  }

  Future<T> _serialized<T>(Future<T> Function() action) {
    final result = _trashQueue.then((_) => action());
    _trashQueue = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  Future<Map<String, _TrashRecord>> _readTrashIndex() async {
    final index = <String, _TrashRecord>{};
    try {
      final file = File(_trashIndexPath);
      if (!await file.exists()) return index;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return index;
      decoded.forEach((name, value) {
        if (name is! String || value is! Map) return;
        final at = value['at'];
        if (at is! int) return;
        final from = value['from'];
        index[name] = _TrashRecord(
          originalPath: from is String ? from : null,
          deletedAt: DateTime.fromMillisecondsSinceEpoch(at),
        );
      });
    } catch (_) {
      // A missing or damaged index is not fatal: unrecorded items are adopted
      // with a fresh deletion time by the next purge.
    }
    return index;
  }

  Future<void> _writeTrashIndex(Map<String, _TrashRecord> index) async {
    try {
      final json = jsonEncode({
        for (final entry in index.entries)
          entry.key: {
            'from': entry.value.originalPath,
            'at': entry.value.deletedAt.millisecondsSinceEpoch,
          },
      });
      final tmp = File('$_trashIndexPath.tmp');
      await tmp.writeAsString(json, flush: true);
      await tmp.rename(_trashIndexPath);
    } catch (_) {
      // Best effort: without the index, items are adopted on the next purge.
    }
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
  Future<List<String>> paste(String destinationDir) {
    return _activePaste ??= _paste(destinationDir).whenComplete(() {
      _activePaste = null;
    });
  }

  Future<List<String>> _paste(String destinationDir) async {
    final state = _clipboard;
    if (state == null || state.paths.isEmpty) return const [];

    final errors = <String>[];
    final failed = <String>[];
    // The moving flag must be decided up front from the pre-clear snapshot;
    // for a cut-paste it's also why the clipboard is only cleared once ALL
    // items have moved successfully.
    final moving = state.mode == ClipboardMode.cut;

    for (final src in state.paths) {
      try {
        await _pasteOne(src, destinationDir, moving);
      } catch (e) {
        failed.add(src);
        errors.add('Could not paste ${_basename(src)}: $e');
      }
    }

    // Single-use clipboard: clear it once the paste fully succeeded, so you
    // can't keep re-pasting the same copied/cut item.
    if (identical(_clipboard, state)) {
      _clipboard = failed.isEmpty
          ? null
          : ClipboardState(paths: failed, mode: state.mode);
    }

    return errors;
  }

  Future<void> _pasteOne(String src, String destinationDir, bool moving) async {
    final srcType = await FileSystemEntity.type(src, followLinks: false);

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
    final dest = await _uniqueDestinationAsync(destinationDir, name);

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
    final entities = await Directory(src).list(followLinks: false).toList();
    final fileFutures = <Future<void>>[];

    for (final entity in entities) {
      final childName = _basename(entity.path);
      final childDest = '$dest/$childName';
      final type = await FileSystemEntity.type(entity.path, followLinks: false);

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
          final target = await link.target();
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
  Future<String> _uniqueDestinationAsync(String dir, String name) async {
    var candidate = '$dir/$name';
    if (!await _existsAsync(candidate)) return candidate;

    final dot = name.lastIndexOf('.');
    final isDotfile = name.startsWith('.');
    final hasExt = !isDotfile && dot > 0 && dot < name.length - 1;
    final base = hasExt ? name.substring(0, dot) : name;
    final ext = hasExt ? name.substring(dot) : '';

    var i = 1;
    while (true) {
      candidate = '$dir/$base ($i)$ext';
      if (!await _existsAsync(candidate)) return candidate;
      i++;
    }
  }

  Future<bool> _existsAsync(String path) async {
    return await FileSystemEntity.type(path, followLinks: false) !=
        FileSystemEntityType.notFound;
  }

  // ---------------------------------------------------------------------------
  // Small helpers
  // ---------------------------------------------------------------------------

  String _slashed(String path) =>
      Platform.isWindows ? path.replaceAll('\\', '/') : path;

  String _basename(String path) {
    if (Platform.isWindows) path = path.replaceAll('\\', '/');
    final trimmed = path.endsWith('/')
        ? path.substring(0, path.length - 1)
        : path;
    return trimmed.split('/').last;
  }

  String _parentOf(String path) {
    if (Platform.isWindows) path = path.replaceAll('\\', '/');
    final trimmed = path.endsWith('/')
        ? path.substring(0, path.length - 1)
        : path;
    final idx = trimmed.lastIndexOf('/');
    return idx <= 0 ? '/' : trimmed.substring(0, idx);
  }
}

/// Where a recycle-bin item was deleted from and when. [originalPath] is null
/// for an item that turned up in the bin without a record.
class _TrashRecord {
  const _TrashRecord({required this.originalPath, required this.deletedAt});

  final String? originalPath;
  final DateTime deletedAt;
}

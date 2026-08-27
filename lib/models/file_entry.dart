import 'dart:io';

class FileEntry {
  final String path;
  final String name;
  final bool isDirectory;

  FileStat? _stat;
  String? _sizeLabel;
  bool _sizeLabelComputed = false;

  FileEntry({
    required this.path,
    required this.name,
    required this.isDirectory,
    FileStat? stat,
  }) {
    _stat = stat;
  }

  // Stat info for files (size, etc.). Null for search results, which don't
  // stat their matches. Directories have a stat too, but its size is just the
  // inode size, not the folder's contents — so it's never shown.
  // Mutable to support lazy stat patching (loading a folder's listing returns
  // entries without stats, and the visible page's stats stream in afterward).
  FileStat? get stat => _stat;
  set stat(FileStat? value) {
    _stat = value;
    // Invalidate the cached label so a later stat is reflected.
    _sizeLabelComputed = false;
    _sizeLabel = null;
  }

  // Human-readable size for files, e.g. "2.4 MB". Null for directories.
  // Cached on first access and invalidated whenever [stat] is reassigned.
  String? get sizeLabel {
    if (!_sizeLabelComputed) {
      _sizeLabel = _computeSizeLabel();
      _sizeLabelComputed = true;
    }
    return _sizeLabel;
  }

  String? _computeSizeLabel() {
    if (isDirectory || _stat == null) return null;
    final bytes = _stat!.size;
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
    return '${(mb / 1024).toStringAsFixed(1)} GB';
  }
}


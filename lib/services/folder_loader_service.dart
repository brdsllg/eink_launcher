import 'dart:async';
import 'dart:isolate';
import 'dart:io';

import '../models/file_entry.dart';

/// Persistent background isolate for folder listing and lazy stat loading.
///
/// Avoids the 100–300ms isolate-startup overhead of compute() on every
/// navigation. The isolate stays warm; callers send a path or stat request
/// and await the result.
class FolderLoaderService {
  static FolderLoaderService? _instance;
  static FolderLoaderService get instance =>
      _instance ??= FolderLoaderService._();

  FolderLoaderService._();

  SendPort? _sendPort;
  Isolate? _isolate;
  Future<void>? _starting;

  /// Ensures the background isolate is running. Idempotent.
  /// Concurrent callers share one startup, and a failed startup never
  /// leaves a half-ready isolate behind.
  Future<void> _ensureIsolate() async {
    if (_sendPort != null) return;
    if (_starting != null) {
      await _starting;
      if (_sendPort != null) return;
      throw StateError('Folder worker did not start.');
    }
    final startup = _startIsolate();
    _starting = startup;
    try {
      await startup.timeout(const Duration(seconds: 5));
    } finally {
      _starting = null;
    }
    if (_sendPort == null) throw StateError('Folder worker did not start.');
  }

  Future<void> _startIsolate() async {
    final receivePort = ReceivePort();
    Isolate? isolate;
    try {
      isolate = await Isolate.spawn(_isolateEntry, receivePort.sendPort);
      final sendPort = await receivePort.first.timeout(
        const Duration(seconds: 5),
      );
      if (sendPort is! SendPort) throw StateError('Bad worker handshake.');
      _isolate = isolate;
      _sendPort = sendPort;
    } catch (_) {
      isolate?.kill(priority: Isolate.immediate);
      _isolate = null;
      _sendPort = null;
      rethrow;
    } finally {
      receivePort.close();
    }
  }

  void _restartWorker() {
    try {
      _isolate?.kill(priority: Isolate.immediate);
    } catch (_) {}
    _isolate = null;
    _sendPort = null;
    _starting = null;
  }

  Future<T> _ask<T>(List<Object> message, {required Duration timeout}) async {
    await _ensureIsolate();
    final responsePort = ReceivePort();
    try {
      _sendPort!.send([...message, responsePort.sendPort]);
      final result = await responsePort.first.timeout(timeout);
      if (result is T) return result;
      // Worker replies 'Error: ...' (String) for folder failures.
      throw Exception(result.toString());
    } on TimeoutException {
      // A hung worker must not hang the browser forever; drop it so the
      // next call starts a fresh one.
      _restartWorker();
      rethrow;
    } catch (_) {
      rethrow;
    } finally {
      responsePort.close();
    }
  }

  /// Lists the folder at [path] on the background isolate and returns
  /// sorted FileEntry results (with stats initially null for fast initial render).
  Future<List<FileEntry>> loadFolder(String path) async {
    try {
      final result = await _ask<List>(
        [path],
        timeout: const Duration(seconds: 15),
      );
      return result.cast<FileEntry>();
    } on TimeoutException {
      // One retry on a fresh worker; a second hang is a real error.
      final result = await _ask<List>(
        [path],
        timeout: const Duration(seconds: 15),
      );
      return result.cast<FileEntry>();
    }
  }

  /// Stats a batch of file paths on the background isolate.
  /// Returns a map of path → FileStat for successful stats.
  Future<Map<String, FileStat>> loadStats(List<String> paths) async {
    try {
      final result = await _ask<Map>(
        ['stats', paths],
        timeout: const Duration(seconds: 15),
      );
      return result.cast<String, FileStat>();
    } catch (_) {
      // File metadata is optional; an isolate hiccup must not break listing.
      return {};
    }
  }

  /// The isolate's main loop.
  static void _isolateEntry(SendPort mainSendPort) {
    final port = ReceivePort();
    mainSendPort.send(port.sendPort);

    port.listen((message) {
      if (message is List && message.isNotEmpty && message[0] == 'stats') {
        final paths = message[1] as List<String>;
        final replyPort = message[2] as SendPort;
        final stats = <String, FileStat>{};
        for (final path in paths) {
          try {
            stats[path] = File(path).statSync();
          } catch (_) {}
        }
        replyPort.send(stats);
      } else if (message is List && message.isNotEmpty) {
        final path = message[0] as String;
        final replyPort = message[1] as SendPort;

        try {
          final entries = _loadFolder(path);
          replyPort.send(entries);
        } catch (e) {
          replyPort.send('Error: $e');
        }
      }
    });
  }

  static List<FileEntry> _loadFolder(String path) {
    final rawEntries = Directory(path).listSync();

    final entries = rawEntries.map((e) {
      final name = e.path.split('/').last;
      final isDir = e is Directory;
      return FileEntry(
        path: e.path,
        name: name,
        isDirectory: isDir,
        stat: null, // Loaded lazily for visible page
      );
    }).toList();

    entries.sort((a, b) {
      if (a.isDirectory != b.isDirectory) {
        return a.isDirectory ? -1 : 1;
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    return entries;
  }

  void dispose() {
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _sendPort = null;
    _instance = null;
  }
}

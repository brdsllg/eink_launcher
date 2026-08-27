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

  /// Ensures the background isolate is running. Idempotent.
  Future<void> _ensureIsolate() async {
    if (_sendPort != null) return;

    final receivePort = ReceivePort();
    _isolate = await Isolate.spawn(_isolateEntry, receivePort.sendPort);

    final completer = Completer<SendPort>();
    receivePort.listen((message) {
      if (message is SendPort) {
        completer.complete(message);
      }
    });
    _sendPort = await completer.future;
    receivePort.close();
  }

  /// Lists the folder at [path] on the background isolate and returns
  /// sorted FileEntry results (with stats initially null for fast initial render).
  Future<List<FileEntry>> loadFolder(String path) async {
    await _ensureIsolate();

    final responsePort = ReceivePort();
    _sendPort!.send([path, responsePort.sendPort]);

    final result = await responsePort.first;
    responsePort.close();

    if (result is List) {
      return result.cast<FileEntry>();
    }
    throw Exception(result.toString());
  }

  /// Stats a batch of file paths on the background isolate.
  /// Returns a map of path → FileStat for successful stats.
  Future<Map<String, FileStat>> loadStats(List<String> paths) async {
    await _ensureIsolate();

    final responsePort = ReceivePort();
    _sendPort!.send(['stats', paths, responsePort.sendPort]);

    final result = await responsePort.first;
    responsePort.close();

    if (result is Map) {
      return result.cast<String, FileStat>();
    }
    return {};
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

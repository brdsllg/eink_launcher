import 'dart:async';
import 'dart:isolate';
import 'dart:io';

import '../models/file_entry.dart';

class SearchParams {
  final String rootPath;
  final String query;
  final int maxResults;
  const SearchParams(this.rootPath, this.query, {this.maxResults = 200});
}

/// Streams search results from a persistent background isolate.
///
/// Results arrive one-at-a-time as the filesystem walk proceeds, so the UI
/// can display matches within milliseconds of starting. The walk can be
/// cancelled mid-flight via [cancel].
class StreamingSearchService {
  Isolate? _isolate;
  Future<void>? _initializing;
  int _generation = 0;
  bool _disposed = false;
  SendPort? _commandPort;
  StreamSubscription? _resultSubscription;
  ReceivePort? _resultPort;

  /// Starts a new search. Results stream into [onResult] as they are found.
  /// [onDone] fires when the walk finishes (or is cancelled).
  ///
  /// Any previously running search is cancelled first.
  Future<void> search({
    required SearchParams params,
    required void Function(FileEntry entry) onResult,
    required void Function() onDone,
  }) async {
    final generation = ++_generation;
    await _cancelCurrentSearch();
    if (_disposed || generation != _generation) return;
    await (_initializing ??= _ensureIsolate());
    if (_disposed || generation != _generation) return;

    _resultPort = ReceivePort();
    _resultSubscription = _resultPort!.listen((message) {
      if (_disposed || generation != _generation) return;
      if (message == null) {
        onDone();
      } else if (message is FileEntry) {
        onResult(message);
      }
    });

    _commandPort!.send([
      params.rootPath,
      params.query,
      params.maxResults,
      _resultPort!.sendPort,
    ]);
  }

  /// Cancels the in-flight search. Safe to call even if nothing is running.
  Future<void> cancel() async {
    _generation++;
    await _cancelCurrentSearch();
  }

  Future<void> _cancelCurrentSearch() async {
    _commandPort?.send('cancel');
    _resultSubscription?.cancel();
    _resultSubscription = null;
    _resultPort?.close();
    _resultPort = null;
  }

  Future<void> _ensureIsolate() async {
    if (_commandPort != null) return;

    final initPort = ReceivePort();
    _isolate = await Isolate.spawn(_isolateMain, initPort.sendPort);

    _commandPort = await initPort.first as SendPort;
    initPort.close();
    if (_disposed) {
      _isolate?.kill(priority: Isolate.immediate);
      _isolate = null;
      _commandPort = null;
    }
  }

  static void _isolateMain(SendPort initSendPort) {
    final commandPort = ReceivePort();
    initSendPort.send(commandPort.sendPort);

    var generation = 0;

    commandPort.listen((message) async {
      if (message == 'cancel') {
        generation++;
        return;
      }

      final args = message as List;
      final rootPath = args[0] as String;
      final query = args[1] as String;
      final maxResults = args[2] as int;
      final replyPort = args[3] as SendPort;

      final current = ++generation;
      int found = 0;
      final queryLower = query.toLowerCase();

      Future<void> walk(String dirPath) async {
        if (current != generation || found >= maxResults) return;
        try {
          await for (final child in Directory(
            dirPath,
          ).list(followLinks: false)) {
            if (current != generation || found >= maxResults) return;
            final name = child.path.replaceAll('\\', '/').split('/').last;
            final isDir = child is Directory;
            if (name.toLowerCase().contains(queryLower)) {
              replyPort.send(
                FileEntry(path: child.path, name: name, isDirectory: isDir),
              );
              found++;
            }
            if (isDir) await walk(child.path);
          }
        } on FileSystemException {
          // An unreadable folder does not abort the rest of the search.
        }
      }

      await walk(rootPath);
      if (current != generation) return;
      replyPort.send(null);
    });
  }

  void dispose() {
    _disposed = true;
    _generation++;
    _resultSubscription?.cancel();
    _resultPort?.close();
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _commandPort = null;
  }
}

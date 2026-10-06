import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Service for handling file intents from Android when a user opens a file with this app.
/// 
/// When the user opens an EPUB or PDF file with your app from the file manager,
/// this service captures the file path and navigates to the reader.
class FileIntentService {
  static const _channel = MethodChannel('eink_launcher/file_intent');
  static const _eventChannel = EventChannel('eink_launcher/file_intent_events');

  static final FileIntentService _instance = FileIntentService._internal();

  factory FileIntentService() {
    return _instance;
  }

  FileIntentService._internal();

  StreamSubscription<dynamic>? _fileEventSubscription;
  bool _initialized = false;
  String? _pendingInitialFile;

  Function(String filePath)? _onFileOpened;

  /// Callback when a file is opened with this app.
  /// If the OS already delivered the launch file before this was set,
  /// it is replayed immediately so the first file is never dropped.
  Function(String filePath)? get onFileOpened => _onFileOpened;

  set onFileOpened(Function(String filePath)? callback) {
    _onFileOpened = callback;
    final pending = _pendingInitialFile;
    if (pending != null && callback != null) {
      _pendingInitialFile = null;
      // Deliver outside the setter so a slow reader open can't re-enter.
      Future.microtask(() => callback(pending));
    }
  }

  /// Start listening for files without fetching the launch file yet.
  /// Safe to call from `main()` before any UI callback exists.
  void startListening() {
    if (_initialized) return;
    _initialized = true;
    _listenToFileIntents();
  }

  /// Initialize the service and set up listeners.
  /// The launch file is kept until [onFileOpened] is set, so calling this
  /// before the UI is ready no longer loses the first file.
  Future<void> initialize() async {
    startListening();
    final initialFile = await getInitialFile();
    if (initialFile == null) return;
    final callback = _onFileOpened;
    if (callback != null) {
      callback(initialFile);
    } else {
      _pendingInitialFile ??= initialFile;
    }
  }

  /// Get the initial file path if the app was opened with a file intent
  Future<String?> getInitialFile() async {
    try {
      final result = await _channel.invokeMethod<Map>('getInitialFile');
      if (result != null) {
        final path = result['path'] as String?;
        return path;
      }
      return null;
    } on PlatformException catch (e) {
      debugPrint('Error getting initial file: ${e.message}');
      return null;
    }
  }

  /// Listen to ongoing file intents (e.g., when app is already running)
  void _listenToFileIntents() {
    _fileEventSubscription = _eventChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        if (event is Map) {
          final path = event['path'] as String?;
          if (path != null) {
            onFileOpened?.call(path);
          }
        }
      },
      onError: (error) {
        debugPrint('Error listening to file intents: $error');
      },
    );
  }

  /// Clean up resources
  void dispose() {
    if (_initialized) {
      _fileEventSubscription?.cancel();
      _fileEventSubscription = null;
      _initialized = false;
    }
  }
}

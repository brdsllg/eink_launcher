import 'dart:async';
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

  /// Callback when a file is opened with this app
  Function(String filePath)? onFileOpened;

  /// Initialize the service and set up listeners
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    _listenToFileIntents();
    final initialFile = await getInitialFile();
    if (initialFile != null && onFileOpened != null) {
      onFileOpened!(initialFile);
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
      print('Error getting initial file: ${e.message}');
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
        print('Error listening to file intents: $error');
      },
    );
  }

  /// Clean up resources
  void dispose() {
    if (_initialized) {
      _fileEventSubscription?.cancel();
      _initialized = false;
    }
  }
}

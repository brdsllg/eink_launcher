import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../services/startup_health_service.dart';

import '../models/book_state.dart';
import '../models/reader_settings.dart';

class BookStoreService {
  static BookStoreService? _instance;
  static BookStoreService get instance => _instance ??= BookStoreService._();

  BookStoreService._();

  static const String _libraryFileName = 'library.json';
  static const Duration _debounceDuration = Duration(seconds: 2);

  bool _isLoaded = false;
  ReaderSettings _globalSettings = const ReaderSettings();
  final Map<String, BookState> _books = {};
  Timer? _debounceTimer;
  Future<void> _pendingFlush = Future<void>.value();
  File? _storageFile;
  Future<void>? _initialization;
  bool _writesBlocked = false;
  String? _recoveryWarning;

  String? get recoveryWarning => _recoveryWarning;
  bool get writesBlocked => _writesBlocked;

  ReaderSettings get globalSettings => _globalSettings;
  Map<String, BookState> get books => Map.unmodifiable(_books);

  Future<void> init({File? customFile}) {
    if (_initialization != null) return _initialization!;
    if (_isLoaded && customFile == null) return Future<void>.value();
    return _initialization = _load(customFile).whenComplete(() {
      _initialization = null;
    });
  }

  Future<void> _load(File? customFile) async {
    _debounceTimer?.cancel();
    await _pendingFlush;
    _isLoaded = false;
    _writesBlocked = false;
    _recoveryWarning = null;
    _books.clear();
    _globalSettings = const ReaderSettings();

    if (customFile != null) {
      _storageFile = customFile;
    } else {
      final docDir = await getApplicationDocumentsDirectory();
      _storageFile = File('${docDir.path}/$_libraryFileName');
    }

    try {
      if (await _storageFile!.exists()) {
        final content = await _storageFile!.readAsString();
        try {
          final jsonMap = json.decode(content) as Map<String, dynamic>;

          if (jsonMap.containsKey('globalSettings')) {
            _globalSettings = ReaderSettings.fromJson(
              jsonMap['globalSettings'] as Map<String, dynamic>,
            );
          }

          if (jsonMap.containsKey('books')) {
            final booksMap = jsonMap['books'] as Map<String, dynamic>;
            _books.clear();
            booksMap.forEach((key, value) {
              _books[key] = BookState.fromJson(value as Map<String, dynamic>);
            });
          }
        } catch (error, stack) {
          _books.clear();
          _globalSettings = const ReaderSettings();
          await _preserveCorruptFile();
          StartupHealthService.instance.recordError(error, stack);
        }
      }
    } catch (error, stack) {
      // Unreadable is not the same as corrupt. Do not replace a file we could
      // not read, or one we could not safely move to a backup.
      _writesBlocked = true;
      _recoveryWarning = 'Reading state could not be preserved. Saving is disabled for this launch.';
      StartupHealthService.instance.recordError(error, stack);
    }
    _isLoaded = true;
  }

  Future<void> _preserveCorruptFile() async {
    // At most three complete backups. Never truncate a user's recoverable
    // reading state and never replace an earlier backup to make room.
    for (var slot = 0; slot < 3; slot++) {
      final suffix = slot == 0 ? '.corrupt' : '.corrupt.$slot';
      final backup = File('${_storageFile!.path}$suffix');
      if (await backup.exists()) continue;
      await _storageFile!.rename(backup.path);
      _recoveryWarning = 'Damaged reading state was backed up. New reading state will be saved separately.';
      return;
    }
    _writesBlocked = true;
    _recoveryWarning = 'Reading-state backups are full. The original is untouched; saving is disabled for this launch.';
  }

  BookState? getBookState(String docId) => _books[docId];

  ReaderSettings getSettingsForDoc(String docId) {
    final book = _books[docId];
    return book?.settingsOverride ?? _globalSettings;
  }

  void saveBookState(BookState state) {
    _books[state.docId] = state;
    _scheduleSave();
  }

  void saveGlobalSettings(ReaderSettings settings) {
    _globalSettings = settings;
    _scheduleSave();
  }

  void _scheduleSave() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceDuration, () => flush());
  }

  Future<void> flush() {
    _debounceTimer?.cancel();
    _debounceTimer = null;

    // Pause, route disposal and memory warnings can flush together. Serializing
    // writes prevents them from renaming/deleting each other's temporary file.
    _pendingFlush = _pendingFlush.then((_) => _writeLatestState());
    return _pendingFlush;
  }

  Future<void> _writeLatestState() async {
    if (_storageFile == null || !_isLoaded || _writesBlocked) return;

    final data = {
      'version': 1,
      'globalSettings': _globalSettings.toJson(),
      'books': _books.map((k, v) => MapEntry(k, v.toJson())),
    };

    final content = const JsonEncoder.withIndent('  ').convert(data);
    final tmpFile = File('${_storageFile!.path}.tmp');

    try {
      await tmpFile.writeAsString(content, flush: true);
      await tmpFile.rename(_storageFile!.path);
    } catch (_) {
      try {
        if (await tmpFile.exists()) {
          await tmpFile.delete();
        }
      } catch (_) {}
    }
  }

  void dispose() {
    _debounceTimer?.cancel();
    _instance = null;
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

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
  File? _storageFile;

  ReaderSettings get globalSettings => _globalSettings;
  Map<String, BookState> get books => Map.unmodifiable(_books);

  Future<void> init({File? customFile}) async {
    if (_isLoaded && customFile == null) return;

    if (customFile != null) {
      _storageFile = customFile;
    } else {
      final docDir = await getApplicationDocumentsDirectory();
      _storageFile = File('${docDir.path}/$_libraryFileName');
    }

    if (await _storageFile!.exists()) {
      try {
        final content = await _storageFile!.readAsString();
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
      } catch (e) {
        // Fallback to empty if corrupted
        _books.clear();
        _globalSettings = const ReaderSettings();
      }
    }
    _isLoaded = true;
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

  Future<void> flush() async {
    _debounceTimer?.cancel();
    _debounceTimer = null;

    if (_storageFile == null) return;

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
      if (await tmpFile.exists()) {
        try {
          await tmpFile.delete();
        } catch (_) {}
      }
    }
  }

  void dispose() {
    _debounceTimer?.cancel();
    _instance = null;
  }
}

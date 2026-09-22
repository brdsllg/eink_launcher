import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';

import '../../services/startup_health_service.dart';

import '../models/book_state.dart';
import '../models/annotation.dart';
import '../models/bookmark.dart';
import '../models/doc_ref.dart';
import '../models/reader_settings.dart';
import '../models/reader_tabs_state.dart';

class BookStoreService {
  static BookStoreService? _instance;
  static BookStoreService get instance => _instance ??= BookStoreService._();

  BookStoreService._();

  static const String _libraryFileName = 'library.json';
  static const Duration _debounceDuration = Duration(seconds: 2);

  bool _isLoaded = false;
  ReaderSettings _globalSettings = const ReaderSettings();
  final Map<String, BookState> _books = {};
  ReaderTabsState _tabsState = ReaderTabsState();
  Timer? _debounceTimer;
  Future<void> _pendingFlush = Future<void>.value();
  File? _storageFile;
  Future<void>? _initialization;
  bool _writesBlocked = false;
  String? _recoveryWarning;

  final ValueNotifier<String?> saveError = ValueNotifier(null);
  int _revision = 0;
  int _savedRevision = 0;
  bool get hasUnsavedChanges => _revision != _savedRevision;
  String? get recoveryWarning => saveError.value ?? _recoveryWarning;
  bool get writesBlocked => _writesBlocked;

  ReaderSettings get globalSettings => _globalSettings;
  Map<String, BookState> get books => Map.unmodifiable(_books);
  ReaderTabsState get tabsState => _tabsState;

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
    saveError.value = null;
    _revision = _savedRevision = 0;
    _books.clear();
    _tabsState = ReaderTabsState();
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
          final version = jsonMap['version'] ?? 1;
          final supportedVersion = version == 1;
          var damaged = false;
          void recover(void Function() read) {
            try {
              read();
            } catch (_) {
              damaged = true;
            }
          }

          List<dynamic> validItems(
            dynamic raw,
            void Function(Map<String, dynamic>) validate,
          ) {
            if (raw == null) return [];
            if (raw is! List) {
              damaged = true;
              return [];
            }
            final items = <dynamic>[];
            for (final value in raw) {
              recover(() {
                validate(value as Map<String, dynamic>);
                items.add(value);
              });
            }
            return items;
          }

          if (jsonMap.containsKey('globalSettings')) {
            recover(() {
              _globalSettings = ReaderSettings.fromJson(
                jsonMap['globalSettings'] as Map<String, dynamic>,
              );
            });
          }
          if (jsonMap.containsKey('books')) {
            recover(() {
              final booksMap = jsonMap['books'] as Map<String, dynamic>;
              for (final entry in booksMap.entries) {
                recover(() {
                  final value = Map<String, dynamic>.from(entry.value as Map);
                  value['bookmarks'] = validItems(value['bookmarks'], (v) {
                    Bookmark.fromJson(v);
                  });
                  value['annotations'] = validItems(value['annotations'], (v) {
                    Annotation.fromJson(v);
                  });
                  if (value['settingsOverride'] != null) {
                    try {
                      ReaderSettings.fromJson(
                        value['settingsOverride'] as Map<String, dynamic>,
                      );
                    } catch (_) {
                      value.remove('settingsOverride');
                      damaged = true;
                    }
                  }
                  final book = BookState.fromJson(value);
                  _books[book.docId] = book;
                });
              }
            });
          }
          if (jsonMap.containsKey('tabs')) {
            recover(() {
              final value = Map<String, dynamic>.from(jsonMap['tabs'] as Map);
              value['documents'] = validItems(value['documents'], (v) {
                DocRef.fromJson(v);
              });
              _tabsState = ReaderTabsState.fromJson(value);
            });
          }
          if (!supportedVersion) {
            _writesBlocked = true;
            _recoveryWarning = 'This reading-state version is not supported. Available records were opened, but saving is disabled to protect the original.';
          } else if (damaged) {
            await _preserveCorruptFile();
            if (!_writesBlocked) {
              _recoveryWarning = 'Some reading-state records could not be loaded. The original was backed up; valid bookmarks and notes were recovered.';
            }
          }
        } catch (error, stack) {
          _books.clear();
          _tabsState = ReaderTabsState();
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
      _revision++;
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

  void saveTabsState(ReaderTabsState tabsState) {
    _tabsState = tabsState;
    _scheduleSave();
  }

  void _scheduleSave() {
    _revision++;
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
    if (!hasUnsavedChanges) return;
    final revision = _revision;
    final tmpFile = File('${_storageFile!.path}.tmp');
    try {
      final data = {
        'version': 1,
        'globalSettings': _globalSettings.toJson(),
        'books': _books.map((k, v) => MapEntry(k, v.toJson())),
        'tabs': _tabsState.toJson(),
      };

      final content = jsonEncode(data);
      await tmpFile.writeAsString(content, flush: true);
      await tmpFile.rename(_storageFile!.path);
      _savedRevision = revision;
      saveError.value = null;
    } catch (_) {
      saveError.value = 'Reading changes have not been saved. Free storage or restore access, then retry. Keep the app open to retain pending notes and bookmarks.';
      try {
        if (await tmpFile.exists()) {
          await tmpFile.delete();
        }
      } catch (_) {}
    }
  }

  void dispose() {
    _debounceTimer?.cancel();
    saveError.dispose();
    _instance = null;
  }
}

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants.dart';
import '../models/file_entry.dart';
import '../services/file_operations_service.dart';
import '../services/folder_loader_service.dart';

enum LauncherStartupState { loading, ready, recovery }

/// Owns all navigation state, folder loading, permission state, selection,
/// and clipboard operations for [FileBrowserScreen].
///
/// The screen holds no business logic — it only renders this state via
/// [ListenableBuilder] and orchestrates BuildContext-dependent UI (dialogs,
/// snackbars, launching) around the controller's methods.
class FileBrowserController extends ChangeNotifier {
  static const String _homeFolderPrefixKey = 'home_folder_path';

  final FileOperationsService _ops = FileOperationsService();
  SharedPreferences? _prefs;
  final Future<SharedPreferences> Function() _loadPreferences;
  final Future<List<FileEntry>> Function(String) _listFolder;
  bool _disposed = false;
  bool _starting = false;
  LauncherStartupState _startupState = LauncherStartupState.loading;
  String? _startupMessage;

  FileBrowserController({
    Future<SharedPreferences> Function()? loadPreferences,
    Future<List<FileEntry>> Function(String)? listFolder,
  }) : _loadPreferences = loadPreferences ?? SharedPreferences.getInstance,
       _listFolder = listFolder ?? FolderLoaderService.instance.loadFolder;

  LauncherStartupState get startupState => _startupState;
  String? get startupMessage => _startupMessage;

  void dismissStartupMessage() {
    _startupMessage = null;
    notifyListeners();
  }

  String _currentPath = kStorageRoot;
  String _homeFolder = kStorageRoot;
  List<FileEntry> _entries = [];
  String _status = '';
  bool _permissionGranted = false;
  int _currentPage = 0;
  int _loadToken = 0;
  int _itemsPerPage = 0;

  bool _searchOpen = false;
  bool _selecting = false;
  final Set<String> _selectedPaths = {};

  FileOperationsService get ops => _ops;
  String get currentPath => _currentPath;
  String get homeFolder => _homeFolder;
  List<FileEntry> get entries => _entries;
  String get status => _status;
  bool get permissionGranted => _permissionGranted;
  int get currentPage => _currentPage;
  bool get searchOpen => _searchOpen;
  bool get selecting => _selecting;
  Set<String> get selectedPaths => _selectedPaths;
  bool get hasSelection => _selectedPaths.isNotEmpty;
  bool get atRoot => _currentPath == kStorageRoot;

  /// Loads shared preferences and the persisted home folder. Idempotent.
  Future<void> init({bool useStorageRoot = false}) async {
    _homeFolder = kStorageRoot;
    _currentPath = kStorageRoot;
    // Recovery must still work if the preferences plugin cannot load at all.
    // This bypass is for this launch only; it does not erase a valid preference.
    if (useStorageRoot) return;
    final prefs = await _loadPreferences().timeout(const Duration(seconds: 5));
    if (_disposed) return;
    _prefs = prefs;
    final saved = prefs.get(_homeFolderPrefixKey);
    if (saved is String && saved.startsWith('/') && !saved.contains('\u0000')) {
      _homeFolder = saved;
      _currentPath = saved;
    } else if (saved != null) {
      await _clearInvalidHome();
    }
  }

  Future<void> _clearInvalidHome() async {
    _homeFolder = kStorageRoot;
    _currentPath = kStorageRoot;
    _startupMessage = 'Saved home folder unavailable. Using internal storage.';
    if (_prefs != null && !await _prefs!.remove(_homeFolderPrefixKey)) {
      throw StateError('Could not clear the invalid home folder preference.');
    }
  }

  /// Preferences must resolve before permission handling or the first listing.
  Future<void> initialize({
    required Future<bool> Function() checkPermission,
    bool useStorageRoot = false,
    void Function(Object, StackTrace)? onError,
  }) async {
    if (_disposed || _starting) return;
    _starting = true;
    _startupState = LauncherStartupState.loading;
    _startupMessage = null;
    notifyListeners();
    try {
      await init(useStorageRoot: useStorageRoot);
      if (_disposed) return;
      final granted = await checkPermission();
      if (_disposed) return;
      _permissionGranted = granted;
      if (granted) {
        try {
          await loadFolder(_currentPath, propagateError: true);
        } catch (error, stack) {
          if (_disposed) return;
          if (_homeFolder == kStorageRoot) rethrow;
          onError?.call(error, stack);
          await _clearInvalidHome();
          if (_disposed) return;
          await loadFolder(kStorageRoot, propagateError: true);
        }
      }
      if (!_disposed) {
        _startupState = LauncherStartupState.ready;
        notifyListeners();
      }
    } catch (error, stack) {
      if (_disposed) return;
      onError?.call(error, stack);
      showRecovery('Startup could not finish. Retry or use internal storage.');
    } finally {
      _starting = false;
    }
  }

  void showRecovery(String message) {
    if (_disposed) return;
    _startupState = LauncherStartupState.recovery;
    _startupMessage = message;
    notifyListeners();
  }

  Future<void> setPermissionGranted(bool granted) async {
    if (_disposed) return;
    _permissionGranted = granted;
    notifyListeners();
    if (granted) {
      await loadFolder(_currentPath);
    }
  }

  /// Loads [path]'s listing on the shared background isolate. Two-phase: the
  /// directory list returns instantly (stats null); the visible page's file
  /// stats then stream in via [loadStats] so the first render is fast.
  ///
  /// [resetPage] defaults to true (navigating into a different folder should
  /// start at page 1). [reloadAfterMutation] passes false so a rename/delete/
  /// paste in the current folder doesn't bump the user back to page 1.
  Future<void> loadFolder(
    String path, {
    bool resetPage = true,
    bool propagateError = false,
  }) async {
    if (_disposed) return;
    final token = ++_loadToken;
    _currentPath = path;
    _status = 'Loading…';
    _selecting = false;
    _selectedPaths.clear();
    notifyListeners();

    try {
      final entries = await _listFolder(path)
          .timeout(const Duration(seconds: 15));
      if (_disposed || token != _loadToken) return;

      _entries = entries;
      if (resetPage) {
        _currentPage = 0;
      } else if (_itemsPerPage > 0) {
        // Keep the user's place, but clamp in case the item count shrank
        // enough to remove pages entirely (e.g. deleting most of a page).
        final totalPages = (_entries.length / _itemsPerPage).ceil().clamp(
          1,
          1000000,
        );
        _currentPage = _currentPage.clamp(0, totalPages - 1);
      }
      _status = entries.isEmpty ? 'Empty folder' : '';
      notifyListeners();

      loadStatsForCurrentPage();
    } catch (e) {
      if (_disposed || token != _loadToken) return;
      _entries = [];
      _currentPage = 0;
      _status = 'Could not read this folder';
      notifyListeners();
      if (propagateError) rethrow;
    }
  }

  /// Reports the real on-screen page size once [PaginatedList] has laid out,
  /// so [loadStatsForCurrentPage] can scope stat-loading to what's actually
  /// visible instead of the whole folder. Returns true if the value changed
  /// (first layout, rotation, keyboard open/close) so the caller knows to
  /// re-trigger stat loading for the now-differently-sized page.
  bool setItemsPerPageHint(int itemsPerPage) {
    if (_disposed) return false;
    if (_itemsPerPage == itemsPerPage) return false;
    _itemsPerPage = itemsPerPage;
    return true;
  }

  /// Stats only the files on the current page that haven't been statted yet.
  /// Scoped to [_itemsPerPage] (reported by PaginatedList) rather than the
  /// whole folder — a folder with thousands of files used to trigger one
  /// giant synchronous stat batch before the visible page's sizes appeared.
  /// No-ops until the real page size is known (see [setItemsPerPageHint]);
  /// there's nothing meaningful to scope to before then.
  Future<void> loadStatsForCurrentPage() async {
    if (_disposed || _itemsPerPage <= 0) return;
    final token = _loadToken;
    final start = _currentPage * _itemsPerPage;
    if (start >= _entries.length) return;
    final end = (start + _itemsPerPage).clamp(0, _entries.length);
    final toStat = _entries
        .sublist(start, end)
        .where((e) => !e.isDirectory && e.stat == null)
        .toList();
    if (toStat.isEmpty) return;

    Map<String, FileStat> stats;
    try {
      stats = await FolderLoaderService.instance.loadStats(
        toStat.map((e) => e.path).toList(),
      );
    } catch (_) {
      return; // File metadata is optional; listing and navigation stay usable.
    }
    if (_disposed || token != _loadToken) return;

    for (final entry in _entries) {
      if (stats.containsKey(entry.path)) {
        entry.stat = stats[entry.path];
      }
    }
    notifyListeners();
  }

  void setPage(int page) {
    if (_currentPage == page) return;
    _currentPage = page;
    notifyListeners();
    loadStatsForCurrentPage();
  }

  void setSearchOpen(bool open) {
    if (_searchOpen == open) return;
    _searchOpen = open;
    notifyListeners();
  }

  void goHome() {
    if (_currentPath == _homeFolder) return;
    loadFolder(_homeFolder);
  }

  void goUp() {
    if (atRoot) return;
    loadFolder(_parentPath(_currentPath));
  }

  /// Saves the current folder as home. Returns a snack message.
  Future<String> setCurrentAsHome() async {
    _homeFolder = _currentPath;
    await _prefs?.setString(_homeFolderPrefixKey, _homeFolder);
    notifyListeners();
    return 'Home folder set to $_currentPath';
  }

  // ---------------------------------------------------------------------------
  // Selection mode
  // ---------------------------------------------------------------------------

  void toggleSelect(String path) {
    if (!_selectedPaths.remove(path)) {
      _selectedPaths.add(path);
    }
    if (_selectedPaths.isEmpty) _selecting = false;
    notifyListeners();
  }

  void enterSelectionFor(String path) {
    _selecting = true;
    _selectedPaths.add(path);
    notifyListeners();
  }

  void exitSelection() {
    _selecting = false;
    _selectedPaths.clear();
    notifyListeners();
  }

  void selectAll() {
    _selecting = true;
    _selectedPaths.clear();
    for (final entry in _entries) {
      _selectedPaths.add(entry.path);
    }
    notifyListeners();
  }
  // ---------------------------------------------------------------------------
  // File-management operations (return a snack message, '' for none)
  // ---------------------------------------------------------------------------

  Future<String> copySelected() async {
    final count = _selectedPaths.length;
    _ops.copy(_selectedPaths.toList());
    exitSelection();
    return 'Copied $count item${count == 1 ? '' : 's'} to clipboard';
  }

  Future<String> cutSelected() async {
    final count = _selectedPaths.length;
    _ops.cut(_selectedPaths.toList());
    exitSelection();
    return 'Cut $count item${count == 1 ? '' : 's'} to clipboard';
  }

  /// Pastes the clipboard into the current folder. If [onErrors] is given
  /// and any item fails, it receives the detailed per-item error messages
  /// and the returned summary is left empty (the caller shows the detail
  /// instead of a generic snack); otherwise falls back to a generic message.
  Future<String> paste({void Function(List<String> errors)? onErrors}) async {
    if (!_ops.hasClipboard) return '';
    final errors = await _ops.paste(_currentPath);
    reloadAfterMutation();
    if (errors.isEmpty) return '';
    if (onErrors != null) {
      onErrors(errors);
      return '';
    }
    return 'Some items could not be pasted';
  }

  Future<String> createFolder(String name) async {
    await _ops.createFolder(_currentPath, name);
    reloadAfterMutation();
    return 'Created folder';
  }

  Future<String> renameEntry(String path, String newName) async {
    await _ops.renameEntry(path, newName);
    reloadAfterMutation();
    exitSelection();
    return 'Renamed';
  }

  /// Deletes [paths]. See [paste] for how [onErrors] is used.
  Future<String> deleteSelectedPaths(
    List<String> paths, {
    void Function(List<String> errors)? onErrors,
  }) async {
    final errors = await _ops.deleteEntries(paths);
    reloadAfterMutation();
    exitSelection();
    if (errors.isEmpty) return 'Deleted';
    if (onErrors != null) {
      onErrors(errors);
      return '';
    }
    return 'Some items could not be deleted';
  }

  /// Reloads the current folder after a mutation that changed its contents,
  /// preserving the current page (clamped) instead of jumping back to page 1.
  void reloadAfterMutation() {
    final path = _currentPath;
    loadFolder(path, resetPage: false);
  }

  String _parentPath(String path) {
    if (path == kStorageRoot) return kStorageRoot;
    final idx = path.lastIndexOf('/');
    var parent = idx <= 0 ? kStorageRoot : path.substring(0, idx);
    if (parent.length < kStorageRoot.length) parent = kStorageRoot;
    return parent;
  }

  @override
  void dispose() {
    _disposed = true;
    _loadToken++;
    super.dispose();
  }
}

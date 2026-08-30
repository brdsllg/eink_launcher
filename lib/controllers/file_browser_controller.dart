import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants.dart';
import '../models/file_entry.dart';
import '../services/file_operations_service.dart';
import '../services/folder_loader_service.dart';

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
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    final saved = _prefs?.getString(_homeFolderPrefixKey);
    if (saved != null && Directory(saved).existsSync()) {
      _homeFolder = saved;
      _currentPath = saved;
    }
  }

  void setPermissionGranted(bool granted) {
    _permissionGranted = granted;
    notifyListeners();
    if (granted) {
      loadFolder(_currentPath);
    }
  }

  /// Loads [path]'s listing on the shared background isolate. Two-phase: the
  /// directory list returns instantly (stats null); the visible page's file
  /// stats then stream in via [loadStats] so the first render is fast.
  ///
  /// [resetPage] defaults to true (navigating into a different folder should
  /// start at page 1). [reloadAfterMutation] passes false so a rename/delete/
  /// paste in the current folder doesn't bump the user back to page 1.
  Future<void> loadFolder(String path, {bool resetPage = true}) async {
    final token = ++_loadToken;
    _currentPath = path;
    _status = 'Loading…';
    _selecting = false;
    _selectedPaths.clear();
    notifyListeners();

    try {
      final entries = await FolderLoaderService.instance.loadFolder(path);
      if (token != _loadToken) return;

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
      if (token != _loadToken) return;
      _entries = [];
      _currentPage = 0;
      _status = 'Error reading folder: $e';
      notifyListeners();
    }
  }

  /// Reports the real on-screen page size once [PaginatedList] has laid out,
  /// so [loadStatsForCurrentPage] can scope stat-loading to what's actually
  /// visible instead of the whole folder. Returns true if the value changed
  /// (first layout, rotation, keyboard open/close) so the caller knows to
  /// re-trigger stat loading for the now-differently-sized page.
  bool setItemsPerPageHint(int itemsPerPage) {
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
    if (_itemsPerPage <= 0) return;
    final token = _loadToken;
    final start = _currentPage * _itemsPerPage;
    if (start >= _entries.length) return;
    final end = (start + _itemsPerPage).clamp(0, _entries.length);
    final toStat = _entries
        .sublist(start, end)
        .where((e) => !e.isDirectory && e.stat == null)
        .toList();
    if (toStat.isEmpty) return;

    final stats = await FolderLoaderService.instance.loadStats(
      toStat.map((e) => e.path).toList(),
    );
    if (token != _loadToken) return;

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
}

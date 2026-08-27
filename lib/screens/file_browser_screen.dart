import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:open_filex/open_filex.dart';
import '../constants.dart';
import '../controllers/file_browser_controller.dart';
import '../models/file_entry.dart';
import '../widgets/clock_text.dart';
import '../widgets/file_action_dialogs.dart';
import '../widgets/file_entry_tile.dart';
import '../widgets/paginated_list.dart';
import '../widgets/search_overlay.dart';
import 'app_drawer_screen.dart';

/// Home-screen file browser.
///
/// Pure UI shell: all state and file logic lives in [FileBrowserController].
/// The screen only wires controller state to widgets and orchestrates
/// BuildContext-dependent interactions (dialogs, snackbars, launching).
class FileBrowserScreen extends StatefulWidget {
  const FileBrowserScreen({super.key});

  @override
  State<FileBrowserScreen> createState() => _FileBrowserScreenState();
}

class _FileBrowserScreenState extends State<FileBrowserScreen> {
  late final FileBrowserController _controller;

  @override
  void initState() {
    super.initState();
    _controller = FileBrowserController();
    _controller.init();
    _checkPermission();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _checkPermission() async {
    final status = await Permission.manageExternalStorage.status;
    if (status.isGranted) {
      _controller.setPermissionGranted(true);
    } else {
      final result = await Permission.manageExternalStorage.request();
      if (result.isGranted) {
        _controller.setPermissionGranted(true);
      } else {
        final storageStatus = await Permission.storage.status;
        if (storageStatus.isGranted) {
          _controller.setPermissionGranted(true);
        } else {
          final storageResult = await Permission.storage.request();
          _controller.setPermissionGranted(storageResult.isGranted);
        }
      }
    }
  }

  // Zero-animation SnackBar (e-ink: no slide-in). Used for all new feedback.
  void _showSnack(String message) {
    if (message.isEmpty || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        animation: const AlwaysStoppedAnimation(1.0),
      ),
    );
  }

  // Await a controller operation's snack message and surface it (or its error).
  Future<void> _showSnackFrom(Future<String> future) async {
    if (!mounted) return;
    try {
      _showSnack(await future);
    } catch (e) {
      _showSnack('Something went wrong: $e');
    }
  }

  // Lists per-item failures from a bulk operation (paste/delete) instead of
  // collapsing them into one generic snack message.
  void _showErrorsDialog(String title, List<String> errors) {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Text(errors.join('\n')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _openEntry(FileEntry entry) async {
    if (entry.isDirectory) {
      _controller.loadFolder(entry.path);
      return;
    }
    final result = await OpenFilex.open(entry.path);
    if (result.type != ResultType.done && mounted) {
      _showSnack('Could not open ${entry.name}: ${result.message}');
    }
  }

  Future<void> _openAppDrawer() async {
    await Navigator.of(context).push(
      noTransitionRoute(const AppDrawerScreen()),
    );
  }
Future<void> _promptNewFolder() async {
    final existing = _controller.entries.map((e) => e.name).toList();
    final name = await showNewFolderDialog(context, existing);
    if (name == null || !mounted) return;
    try {
      await _controller.createFolder(name);
      _showSnack('Created folder');
    } catch (e) {
      _showSnack('Could not create folder: $e');
    }
  }

  Future<void> _renameSelected() async {
    if (_controller.selectedPaths.length != 1) return;
    final path = _controller.selectedPaths.first;
    final currentName = path.split('/').last;
    final existing = _controller.entries.map((e) => e.name).toList();
    final newName = await showRenameDialog(context, currentName, existing);
    if (newName == null || !mounted) return;
    try {
      await _controller.renameEntry(path, newName);
      _showSnack('Renamed');
    } catch (e) {
      _showSnack('Could not rename: $e');
    }
  }

  Future<void> _confirmDeleteSelected() async {
    final count = _controller.selectedPaths.length;
    final confirmed = await showDeleteConfirmDialog(context, count);
    if (!confirmed || !mounted) return;
    final msg = await _controller.deleteSelectedPaths(
      _controller.selectedPaths.toList(),
      onErrors: (errors) => _showErrorsDialog('Delete errors', errors),
    );
    _showSnack(msg);
  }

  Future<void> _confirmSetHome() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Set Home Folder'),
        content: Text('Make this your home folder?\n\n${_controller.currentPath}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Set as Home'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final msg = await _controller.setCurrentAsHome();
      _showSnack(msg);
    }
  }

  // Friendly label for the app bar. The raw last path segment of the shared
  // storage root is literally "0" (Android's per-user storage id), which is
  // meaningless to look at, so special-case it.
  String _displayName(String path) {
    if (path == kStorageRoot) return 'Internal Storage';
    final segments = path.split('/').where((s) => s.isNotEmpty);
    return segments.isEmpty ? path : segments.last;
  }
// One row of the file list. While selecting, the row is inverted (black bg /
  // white text — e-ink friendly, no color) to mark selection.
  Widget _buildRow(FileEntry entry) {
    final isSelected = _controller.selectedPaths.contains(entry.path);
    return SizedBox(
      height: kRowHeight,
      child: FileEntryTile(
        entry: entry,
        isSelected: isSelected,
        onTap: () {
          if (_controller.selecting) {
            _controller.toggleSelect(entry.path);
          } else {
            _openEntry(entry);
          }
        },
        onLongPress: () {
          if (!_controller.selecting) {
            _controller.enterSelectionFor(entry.path);
          }
        },
      ),
    );
  }

  Widget _buildTopBar() {
    if (!_controller.permissionGranted) {
      return SizedBox(
        width: double.infinity,
        child: TextButton.icon(
          key: const Key('request-permission-button'),
          style: TextButton.styleFrom(
            foregroundColor: Colors.black,
            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          ),
          onPressed: _checkPermission,
          icon: const Icon(Icons.folder_open),
          label: const Text('Grant storage access'),
        ),
      );
    }
    final onPressed =
        (_controller.atRoot || _controller.selecting) ? null : _controller.goUp;
    return SizedBox(
      width: double.infinity,
      child: InkWell(
        key: const Key('up-button'),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.arrow_upward,
                  color: onPressed == null ? Colors.grey : Colors.black),
              const SizedBox(width: 8),
              Text(
                'Up a folder',
                style: TextStyle(
                  fontSize: 14,
                  color: onPressed == null ? Colors.grey : Colors.black,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // A single action in the selection-mode app bar.
  Widget _barAction(
    IconData icon,
    String label,
    VoidCallback onPressed, {
    bool enabled = true,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: TextButton(
        style: TextButton.styleFrom(
          foregroundColor: enabled ? Colors.black : Colors.grey,
          minimumSize: const Size(0, 0),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        ),
        onPressed: enabled ? onPressed : null,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }
@override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (_controller.selecting) {
          _controller.exitSelection();
          return;
        }
        if (_controller.searchOpen) {
          _controller.setSearchOpen(false);
          return;
        }
        if (!_controller.atRoot) {
          _controller.goUp();
        }
      },
      child: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          return Scaffold(
            appBar: _controller.selecting
                ? AppBar(
                    leading: InkResponse(
                      onTap: _controller.exitSelection,
                      radius: 24,
                      child: const Padding(
                        padding: EdgeInsets.all(12),
                        child: Icon(Icons.close),
                      ),
                    ),
                    title: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Text(
                                '${_controller.selectedPaths.length} selected'),
                          ),
                          _barAction(Icons.copy, 'Copy', () {
                            _showSnackFrom(_controller.copySelected());
                          },
                              enabled: _controller.hasSelection),
                          _barAction(Icons.content_cut, 'Cut', () {
                            _showSnackFrom(_controller.cutSelected());
                          },
                              enabled: _controller.hasSelection),
                          _barAction(Icons.content_paste, 'Paste', () {
                            _showSnackFrom(_controller.paste(
                              onErrors: (errors) =>
                                  _showErrorsDialog('Paste errors', errors),
                            ));
                          }, enabled: _controller.ops.hasClipboard),
                          _barAction(Icons.drive_file_move, 'Rename',
                              _renameSelected,
                              enabled: _controller.selectedPaths.length == 1),
                          _barAction(
                              Icons.create_new_folder, 'New folder', () async {
                                await _promptNewFolder();
                              }),
                          _barAction(Icons.delete_outline, 'Delete',
                              _confirmDeleteSelected,
                              enabled: _controller.hasSelection),
                        ],
                      ),
                    ),
                    centerTitle: true,
                    actions: const [SizedBox(width: 56)],
                  )
                : AppBar(
                    leading: Tooltip(
                      message: 'Home (long-press to set as Home)',
                      child: InkResponse(
                        onTap: _controller.goHome,
                        onLongPress: _confirmSetHome,
                        radius: 24,
                        child: const Padding(
                          padding: EdgeInsets.all(12),
                          child: Icon(Icons.home),
                        ),
                      ),
                    ),
                    title: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_displayName(_controller.currentPath)),
                        if (_controller.status.isNotEmpty)
                          Text(
                            _controller.status,
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                    centerTitle: true,
                    actions: [
                      const Padding(
                        padding: EdgeInsets.only(right: 12),
                        child: Center(child: ClockText()),
                      ),
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.add),
                        tooltip: 'More options',
                        onSelected: (value) {
                          switch (value) {
                            case 'search':
                              _controller.setSearchOpen(true);
                              break;
                            case 'apps':
                              _openAppDrawer();
                              break;
                            case 'newFolder':
                              _promptNewFolder();
                              break;
                            case 'paste':
                              _showSnackFrom(_controller.paste(
                                onErrors: (errors) => _showErrorsDialog(
                                    'Paste errors', errors),
                              ));
                              break;
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                              value: 'search', child: Text('Search')),
                          const PopupMenuItem(
                              value: 'apps', child: Text('Apps')),
                          const PopupMenuItem(
                              value: 'newFolder', child: Text('New Folder')),
                          PopupMenuItem(
                            value: 'paste',
                            enabled: _controller.ops.hasClipboard,
                            child: const Text('Paste'),
                          ),
                        ],
                      ),
                    ],
                  ),
body: Stack(
              children: [
                Column(
                  children: [
                    SizedBox(
                      height: 44,
                      child: _buildTopBar(),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: PaginatedList<FileEntry>(
                        items: _controller.entries,
                        currentPage: _controller.currentPage,
                        onPageChanged: _controller.setPage,
                        itemBuilder: (context, entry) => _buildRow(entry),
                        onItemsPerPageChanged: (n) {
                          if (_controller.setItemsPerPageHint(n)) {
                            _controller.loadStatsForCurrentPage();
                          }
                        },
                      ),
                    ),
                  ],
                ),
                if (_controller.searchOpen) ...[
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _controller.setSearchOpen(false),
                      child: Container(color: Colors.transparent),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: SearchOverlay(
                      initialPath: _controller.currentPath,
                      onClose: () => _controller.setSearchOpen(false),
                      onEntrySelected: (entry) {
                        _controller.setSearchOpen(false);
                        _openEntry(entry);
                      },
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
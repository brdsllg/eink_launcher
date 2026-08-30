import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:open_filex/open_filex.dart';

import '../constants.dart';
import '../controllers/file_browser_controller.dart';
import '../models/file_entry.dart';
import '../reader/models/doc_ref.dart';
import '../reader/screens/reader_screen.dart';
import '../reader/services/doc_identity_service.dart';
import '../services/file_mime_type_service.dart';
import '../services/open_with_service.dart';
import '../widgets/battery_status.dart';
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
  String? _openingPath;

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
      animationStyle: AnimationStyle.noAnimation,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: Text(errors.join('\n'))),
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
    if (_openingPath != null) return;
    final path = entry.path;
    setState(() => _openingPath = path);
    // Guarantee that the inverted row reaches the e-ink panel before a folder
    // load or external Android activity starts replacing the current view.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || _openingPath != path) return;

    try {
      if (entry.isDirectory) {
        await _controller.loadFolder(path);
        return;
      }
      final dotIndex = entry.name.lastIndexOf('.');
      final extension = dotIndex < 0
          ? ''
          : entry.name.substring(dotIndex).toLowerCase();
      final format = DocFormat.tryFromExtension(extension);
      if (kReadableExtensions.contains(extension) && format != null) {
        final doc = await DocIdentityService.createDocRef(path);
        if (!mounted) return;
        await Navigator.of(context)
            .push(noTransitionRoute(ReaderScreen(doc: doc)));
        return;
      }
      final result = await OpenFilex.open(
        path,
        type: FileMimeTypeService.forPath(path),
      );
      if (result.type != ResultType.done && mounted) {
        _showSnack('Could not open ${entry.name}: ${result.message}');
      }
    } catch (error) {
      _showSnack('Could not open ${entry.name}: $error');
    } finally {
      if (mounted && _openingPath == path) {
        setState(() => _openingPath = null);
      }
    }
  }

  Future<void> _openAppDrawer() async {
    await Navigator.of(context)
        .push(noTransitionRoute(const AppDrawerScreen()));
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
      animationStyle: AnimationStyle.noAnimation,
      builder: (context) => AlertDialog(
        title: const Text('Set Home Folder'),
        content: Text(
          'Make this your home folder?\n\n${_controller.currentPath}',
        ),
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
  Widget _buildRow(FileEntry entry, double barHeight) {
    final isSelected = _controller.selectedPaths.contains(entry.path);
    return SizedBox(
      height: barHeight,
      child: FileEntryTile(
        entry: entry,
        isSelected: isSelected,
        isOpening: _openingPath == entry.path,
        height: barHeight,
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

  Widget _buildEmptyRow(double barHeight) {
    return Container(
      height: barHeight,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.black, width: 0.5)),
      ),
    );
  }

  Widget _buildTopBar(double barHeight) {
    final textSize = (barHeight * 0.44).clamp(16.0, 26.0).toDouble();
    final iconSize = (barHeight * 0.48).clamp(22.0, 30.0).toDouble();
    if (!_controller.permissionGranted) {
      return SizedBox(
        width: double.infinity,
        child: TextButton.icon(
          key: const Key('request-permission-button'),
          style: TextButton.styleFrom(
            foregroundColor: Colors.black,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.zero,
            ),
          ),
          onPressed: _checkPermission,
          icon: Icon(Icons.folder_open, size: iconSize),
          label: Text(
            'Grant storage access',
            style: TextStyle(fontSize: textSize, height: 1),
          ),
        ),
      );
    }
    final onPressed = (_controller.atRoot || _controller.selecting)
        ? null
        : _controller.goUp;
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
              Icon(
                Icons.arrow_upward,
                size: iconSize,
                color: onPressed == null ? Colors.grey : Colors.black,
              ),
              const SizedBox(width: 8),
              Text(
                'Up a folder',
                style: TextStyle(
                  fontSize: textSize,
                  height: 1,
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
    bool compact = false,
    double barHeight = kToolbarHeight,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: compact ? 2 : 6),
      child: TextButton(
        style: TextButton.styleFrom(
          foregroundColor: Colors.black,
          minimumSize: const Size(0, 0),
          padding: EdgeInsets.symmetric(horizontal: compact ? 4 : 6),
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        ),
        onPressed: onPressed,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: (barHeight * 0.4).clamp(20.0, 24.0).toDouble()),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: (barHeight * 0.3).clamp(14.0, 18.0).toDouble(),
                height: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  FileEntry? get _singleSelectedFile {
    if (_controller.selectedPaths.length != 1) return null;
    final selectedPath = _controller.selectedPaths.first;
    for (final entry in _controller.entries) {
      if (entry.path == selectedPath && !entry.isDirectory) return entry;
    }
    return null;
  }

  Future<void> _openSelectedWith() async {
    final file = _singleSelectedFile;
    if (file == null) return;
    try {
      await OpenWithService.open(file.path);
      if (mounted) _controller.exitSelection();
    } catch (error) {
      _showSnack('Could not show apps for ${file.name}: $error');
    }
  }

  double _textWidth(BuildContext context, String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    return painter.width;
  }

  bool _selectionBarNeedsTwoRows(BuildContext context, double barHeight) {
    final theme = Theme.of(context);
    final titleStyle =
        theme.appBarTheme.titleTextStyle ??
        theme.textTheme.titleLarge ??
        const TextStyle(fontSize: 20);
    final actionStyle = TextStyle(
      fontSize: (barHeight * 0.3).clamp(14.0, 18.0).toDouble(),
    );
    final selectedLabel = '${_controller.selectedPaths.length} selected';
    final actionLabels = [
      if (_singleSelectedFile != null) 'Open with',
      'Copy',
      'Cut',
      if (_controller.selectedPaths.length == 1) 'Rename',
      'Delete',
    ];

    // Each action uses a 22 px icon, 4 px gap, 24 px of horizontal padding,
    // and its label. The remaining width accounts for the leading close
    // button, the balancing trailing space, and the AppBar's title spacing.
    final requiredWidth =
        16 +
        _textWidth(context, selectedLabel, titleStyle) +
        actionLabels.fold<double>(
          0,
          (width, label) =>
              width + 50 + _textWidth(context, label, actionStyle),
        );
    final availableWidth =
        MediaQuery.sizeOf(context).width -
        (kToolbarHeight * 2) -
        NavigationToolbar.kMiddleSpacing * 2;
    return requiredWidth > availableWidth;
  }

  List<Widget> _selectionActions(double barHeight, {bool compact = false}) {
    return [
      if (_singleSelectedFile != null)
        _barAction(
          Icons.open_in_new,
          'Open with',
          _openSelectedWith,
          compact: compact,
          barHeight: barHeight,
        ),
      _barAction(
        Icons.copy,
        'Copy',
        () {
          _showSnackFrom(_controller.copySelected());
        },
        compact: compact,
        barHeight: barHeight,
      ),
      _barAction(
        Icons.content_cut,
        'Cut',
        () {
          _showSnackFrom(_controller.cutSelected());
        },
        compact: compact,
        barHeight: barHeight,
      ),
      if (_controller.selectedPaths.length == 1)
        _barAction(
          Icons.drive_file_move,
          'Rename',
          _renameSelected,
          compact: compact,
          barHeight: barHeight,
        ),
      _barAction(
        Icons.delete_outline,
        'Delete',
        _confirmDeleteSelected,
        compact: compact,
        barHeight: barHeight,
      ),
    ];
  }

  PreferredSizeWidget _buildSelectionBar(
    BuildContext context,
    double barHeight, {
    required bool twoRows,
  }) {
    final actions = _selectionActions(barHeight, compact: twoRows);
    final topActionCount = actions.length >= 5 ? 2 : 1;
    final selectedCount = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        '${_controller.selectedPaths.length} selected',
        style: TextStyle(
          fontSize: (barHeight * 0.38).clamp(17.0, 22.0).toDouble(),
          height: 1,
        ),
      ),
    );

    return AppBar(
      toolbarHeight: twoRows ? barHeight * 2 : barHeight,
      leading: InkResponse(
        onTap: _controller.exitSelection,
        radius: 24,
        child: const Padding(
          padding: EdgeInsets.all(12),
          child: Icon(Icons.close),
        ),
      ),
      titleSpacing: twoRows ? 0 : NavigationToolbar.kMiddleSpacing,
      title: twoRows
          ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  height: barHeight,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [selectedCount, ...actions.take(topActionCount)],
                  ),
                ),
                SizedBox(
                  height: barHeight,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: actions.skip(topActionCount).toList(),
                  ),
                ),
              ],
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [selectedCount, ...actions],
            ),
      centerTitle: !twoRows,
      actions: twoRows ? null : const [SizedBox(width: kToolbarHeight)],
      shape: const Border(bottom: BorderSide(color: Colors.black, width: 0.5)),
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
          final mediaQuery = MediaQuery.of(context);
          final totalBars = mediaQuery.orientation == Orientation.portrait
              ? kPortraitBarCount
              : kLandscapeBarCount;
          final barHeight = mediaQuery.size.height / totalBars;
          final selectionUsesTwoRows =
              _controller.selecting &&
              _selectionBarNeedsTwoRows(context, barHeight);
          final topBarUnits = selectionUsesTwoRows ? 2 : 1;
          final fileRowCount = totalBars - topBarUnits - 2;
          return Scaffold(
            appBar: _controller.selecting
                ? _buildSelectionBar(
                    context,
                    barHeight,
                    twoRows: selectionUsesTwoRows,
                  )
                : AppBar(
                    toolbarHeight: barHeight,
                    leadingWidth: kToolbarHeight + 82,
                    leading: Row(
                      children: [
                        SizedBox(
                          width: kToolbarHeight,
                          child: Tooltip(
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
                        ),
                        Expanded(
                          child: Center(
                            child: ClockText(
                              style: TextStyle(
                                fontSize: (barHeight * 0.25)
                                    .clamp(11.0, 15.0)
                                    .toDouble(),
                                height: 1,
                                color: Colors.black,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    title: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _displayName(_controller.currentPath),
                          style: TextStyle(
                            fontSize: (barHeight * 0.4)
                                .clamp(17.0, 24.0)
                                .toDouble(),
                            height: 1,
                          ),
                        ),
                        if (_controller.status.isNotEmpty)
                          Text(
                            _controller.status,
                            style: TextStyle(
                              fontSize: (barHeight * 0.21)
                                  .clamp(10.0, 13.0)
                                  .toDouble(),
                              height: 1,
                              color: Colors.grey,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                    centerTitle: true,
                    actions: [
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Center(
                          child: BatteryStatus(
                            style: TextStyle(
                              fontSize: (barHeight * 0.25)
                                  .clamp(11.0, 15.0)
                                  .toDouble(),
                              height: 1,
                              color: Colors.black,
                            ),
                            iconSize: (barHeight * 0.46)
                                .clamp(21.0, 28.0)
                                .toDouble(),
                          ),
                        ),
                      ),
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.add),
                        tooltip: 'More options',
                        popUpAnimationStyle: AnimationStyle.noAnimation,
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
                              _showSnackFrom(
                                _controller.paste(
                                  onErrors: (errors) =>
                                      _showErrorsDialog('Paste errors', errors),
                                ),
                              );
                              break;
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'search',
                            child: Text('Search'),
                          ),
                          const PopupMenuItem(
                            value: 'apps',
                            child: Text('Apps'),
                          ),
                          const PopupMenuItem(
                            value: 'newFolder',
                            child: Text('New Folder'),
                          ),
                          PopupMenuItem(
                            value: 'paste',
                            enabled: _controller.ops.hasClipboard,
                            child: const Text('Paste'),
                          ),
                        ],
                      ),
                    ],
                    shape: const Border(
                      bottom: BorderSide(color: Colors.black, width: 0.5),
                    ),
                  ),
            body: Stack(
              children: [
                Column(
                  children: [
                    Container(
                      height: barHeight,
                      decoration: const BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: Colors.black, width: 0.5),
                        ),
                      ),
                      child: _buildTopBar(barHeight),
                    ),
                    Expanded(
                      child: PaginatedList<FileEntry>(
                        items: _controller.entries,
                        currentPage: _controller.currentPage,
                        onPageChanged: _controller.setPage,
                        itemBuilder: (context, entry) =>
                            _buildRow(entry, barHeight),
                        rowHeight: barHeight,
                        navBarHeight: barHeight,
                        preferredItemsPerPage: fileRowCount,
                        emptyItemBuilder: (context) =>
                            _buildEmptyRow(barHeight),
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

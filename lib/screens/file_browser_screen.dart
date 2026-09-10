import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:open_filex/open_filex.dart';

import '../constants.dart';
import '../controllers/file_browser_controller.dart';
import '../models/file_entry.dart';
import '../reader/controllers/reader_session_registry.dart';
import '../reader/models/doc_ref.dart';
import '../reader/screens/reader_screen.dart';
import '../reader/services/doc_identity_service.dart';
import '../services/file_mime_type_service.dart';
import '../services/open_with_service.dart';
import '../services/startup_health_service.dart';
import '../widgets/adaptive_grid.dart';
import '../widgets/battery_status.dart';
import '../widgets/clock_text.dart';
import '../widgets/control_bar_row.dart';
import '../widgets/file_action_dialogs.dart';
import '../widgets/file_entry_tile.dart';
import '../widgets/inverting_ink_well.dart';
import '../widgets/paginated_list.dart';
import '../widgets/search_overlay.dart';
import 'app_drawer_screen.dart';
import 'launcher_recovery_screen.dart';

/// Home-screen file browser.
///
/// Pure UI shell: all state and file logic lives in [FileBrowserController].
/// The screen only wires controller state to widgets and orchestrates
/// BuildContext-dependent interactions (dialogs, snackbars, launching).
class FileBrowserScreen extends StatefulWidget {
  final FileBrowserController? controller;
  final StartupHealthService? startupHealth;
  final Future<bool> Function()? checkPermission;
  final ReaderSessionRegistry? registry;

  const FileBrowserScreen({
    super.key,
    this.controller,
    this.startupHealth,
    this.checkPermission,
    this.registry,
  });

  @override
  State<FileBrowserScreen> createState() => _FileBrowserScreenState();
}

class _FileBrowserScreenState extends State<FileBrowserScreen> {
  late final FileBrowserController _controller;
  late final StartupHealthService _startupHealth;
  late final ReaderSessionRegistry _registry;
  bool _healthChecked = false;
  bool _initializing = false;
  String? _openingPath;
  bool _openingTabs = false;
  bool? _browserLandscape;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? FileBrowserController();
    _startupHealth = widget.startupHealth ?? StartupHealthService.instance;
    _registry = widget.registry ?? ReaderSessionRegistry.instance;
    _initialize();
  }

  @override
  void dispose() {
    _controller.dispose();
    unawaited(SystemChrome.setPreferredOrientations(const []));
    super.dispose();
  }

  Future<void> _toggleBrowserOrientation() async {
    final currentlyLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final landscape = !currentlyLandscape;
    _browserLandscape = landscape;
    await _applyBrowserOrientation(landscape);
  }

  Future<void> _applyBrowserOrientation(bool landscape) {
    return SystemChrome.setPreferredOrientations(
      landscape
          ? const [DeviceOrientation.landscapeLeft]
          : const [DeviceOrientation.portraitUp],
    );
  }

  Future<void> _restoreBrowserOrientation() async {
    final landscape = _browserLandscape;
    if (landscape != null) await _applyBrowserOrientation(landscape);
  }

  Future<void> _initialize({bool useStorageRoot = false}) async {
    if (_initializing) return;
    _initializing = true;
    try {
      if (!_healthChecked) {
        final recover = await _startupHealth.shouldRecover();
        if (!mounted) return;
        _healthChecked = true;
        if (recover) {
          _controller.showRecovery(
            'Startup safety checks need attention. Your settings have not been changed.',
          );
          return;
        }
      }
      if (!mounted) return;
      await _controller.initialize(
        checkPermission: widget.checkPermission ?? _checkPermission,
        useStorageRoot: useStorageRoot,
        onError: _startupHealth.recordError,
      );
    } finally {
      _initializing = false;
    }
  }

  Future<bool> _checkPermission() async {
    final status = await Permission.manageExternalStorage.status;
    if (!mounted) return false;
    if (status.isGranted) return true;
    final result = await Permission.manageExternalStorage.request();
    if (!mounted) return false;
    if (result.isGranted) return true;
    final storageStatus = await Permission.storage.status;
    if (!mounted) return false;
    if (storageStatus.isGranted) return true;
    return (await Permission.storage.request()).isGranted;
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
      builder: (context) => GridDialog(
        title: Text(title),
        content: Text(errors.join('\n')),
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
    if (_openingPath != null || _openingTabs) return;
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
        await Navigator.of(
          context,
        ).push(noTransitionRoute(ReaderScreen(doc: doc, registry: _registry)));
        if (mounted) await _restoreBrowserOrientation();
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

  void _openAppDrawerFromPaste() {
    // Remove the popup route before opening Apps so returning to the browser
    // cannot reveal the old menu underneath it.
    Navigator.of(context).pop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_openAppDrawer());
    });
  }

  Future<void> _openTabs() async {
    if (_openingPath != null || _openingTabs) return;
    _openingTabs = true;
    try {
      await _registry.restoreTabs();
      if (!mounted) return;
      final doc = _registry.mostRecentlyReadTab;
      if (doc == null) {
        _showSnack('No open tabs');
        return;
      }
      await Navigator.of(context)
          .push(noTransitionRoute(ReaderScreen(doc: doc, registry: _registry)));
      if (mounted) await _restoreBrowserOrientation();
    } catch (_) {
      _showSnack('Could not restore open tabs. Please try again.');
    } finally {
      _openingTabs = false;
    }
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
      builder: (context) => GridDialog(
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
        onTap: _openingPath != null || _openingTabs
            ? null
            : () {
                if (_controller.selecting) {
                  _controller.toggleSelect(entry.path);
                } else {
                  _openEntry(entry);
                }
              },
        onLongPress: _openingPath != null || _openingTabs
            ? null
            : () {
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
        border: Border(bottom: BorderSide(color: Colors.black)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) => Align(
          alignment: Alignment.centerRight,
          child: Container(
            width: FileEntryTile.metadataWidthFor(constraints.maxWidth),
            decoration: const BoxDecoration(
              border: Border(left: BorderSide(color: Colors.black)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(double barHeight) {
    if (_controller.startupMessage != null) {
      return Row(
        children: [
          const SizedBox(width: 8),
          Expanded(child: Text(_controller.startupMessage!, maxLines: 2)),
          IconButton(
            onPressed: _controller.dismissStartupMessage,
            tooltip: 'Dismiss warning',
            icon: const Icon(Icons.close),
          ),
        ],
      );
    }
    final textSize = (barHeight * 0.44).clamp(16.0, 26.0).toDouble();
    final iconSize = (barHeight * 0.48).clamp(22.0, 30.0).toDouble();
    if (!_controller.permissionGranted) {
      return SizedBox(
        width: double.infinity,
        child: TextButton.icon(
          key: const Key('request-permission-button'),
          style: TextButton.styleFrom(
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.zero,
            ),
          ),
          onPressed: _initialize,
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
      child: InvertingInkWell(
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

  // Action cells use equal widths within a row, with enough room for the
  // longest label (Open with). Text can scale down without changing the bands.
  Widget _barAction(
    IconData icon,
    String label,
    VoidCallback onPressed, {
    double barHeight = kToolbarHeight,
  }) {
    return TextButton(
      style: TextButton.styleFrom(
        minimumSize: Size.zero,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      ),
      onPressed: onPressed,
      child: FittedBox(
        fit: BoxFit.scaleDown,
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

  List<Widget> _selectionActions(double barHeight) => [
    if (_singleSelectedFile != null)
      _barAction(
        Icons.open_in_new,
        'Open with',
        _openSelectedWith,
        barHeight: barHeight,
      ),
    _barAction(
      Icons.copy,
      'Copy',
      () => _showSnackFrom(_controller.copySelected()),
      barHeight: barHeight,
    ),
    _barAction(
      Icons.content_cut,
      'Cut',
      () => _showSnackFrom(_controller.cutSelected()),
      barHeight: barHeight,
    ),
    if (_controller.selectedPaths.length == 1)
      _barAction(
        Icons.drive_file_move,
        'Rename',
        _renameSelected,
        barHeight: barHeight,
      ),
    _barAction(
      Icons.delete_outline,
      'Delete',
      _confirmDeleteSelected,
      barHeight: barHeight,
    ),
  ];

  int _selectionColumns(double width, int actionCount) =>
      (width / 120).floor().clamp(1, actionCount);

  PreferredSizeWidget _buildSelectionBar(
    double barHeight,
    List<Widget> actions,
    int columns,
  ) {
    final actionRows = (actions.length / columns).ceil();
    return AppBar(
      toolbarHeight: barHeight * (actionRows + 1),
      automaticallyImplyLeading: false,
      titleSpacing: 0,
      title: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ControlBarRow(
            height: barHeight,
            children: [
              SizedBox(
                width: 48,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  onPressed: _controller.exitSelection,
                  tooltip: 'Cancel selection',
                  icon: const Icon(Icons.close),
                ),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    '${_controller.selectedPaths.length} selected',
                    style: TextStyle(
                      fontSize: (barHeight * 0.38).clamp(17.0, 22.0),
                      height: 1,
                    ),
                  ),
                ),
              ),
            ],
          ),
          for (var row = 0; row < actionRows; row++)
            DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Colors.black)),
              ),
              child: ControlBarRow(
                height: barHeight,
                children: [
                  for (var column = 0; column < columns; column++)
                    Expanded(
                      child: row * columns + column < actions.length
                          ? actions[row * columns + column]
                          : const SizedBox(),
                    ),
                ],
              ),
            ),
        ],
      ),
      shape: const Border(bottom: BorderSide(color: Colors.black)),
    );
  }

  PreferredSizeWidget _buildBrowserBar(double barHeight) {
    Widget statusCell(
      Key key,
      double width,
      Widget child, {
      bool fill = false,
    }) => SizedBox(
      key: key,
      width: width,
      child: fill
          ? Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              child: child,
            )
          : Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: FittedBox(fit: BoxFit.scaleDown, child: child),
              ),
            ),
    );
    return AppBar(
      toolbarHeight: barHeight,
      automaticallyImplyLeading: false,
      titleSpacing: 0,
      centerTitle: false,
      shape: const Border(bottom: BorderSide(color: Colors.black)),
      title: LayoutBuilder(
        builder: (context, constraints) {
          // At normal widths each unit is 64px. On very narrow screens all
          // four side cells shrink together, preserving the requested
          // 1:2:1:1 relationship while leaving a readable folder-title cell.
          final unitWidth = ((constraints.maxWidth - 76) / 5).clamp(0.0, 64.0);
          return ControlBarRow(
            height: barHeight,
            children: [
              SizedBox(
                key: const Key('browser-home-cell'),
                width: unitWidth,
                child: Tooltip(
                  message: 'Home (long-press to set as Home)',
                  child: InvertingInkWell(
                    onTap: _controller.goHome,
                    onLongPress: _confirmSetHome,
                    child: const Icon(Icons.home, size: kReaderChromeIconSize),
                  ),
                ),
              ),
              statusCell(
                const Key('browser-clock-cell'),
                unitWidth * 2,
                const ClockText(
                  fillAvailableSpace: true,
                  style: TextStyle(color: Colors.black),
                ),
                fill: true,
              ),
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _displayName(_controller.currentPath),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: (barHeight * 0.4).clamp(17.0, 24.0),
                          height: 1,
                        ),
                      ),
                      if (_controller.status.isNotEmpty)
                        Text(
                          _controller.status,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: (barHeight * 0.21).clamp(10.0, 13.0),
                            height: 1,
                            color: Colors.grey,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              statusCell(
                const Key('browser-battery-cell'),
                unitWidth,
                const BatteryStatus(
                  style: TextStyle(fontSize: 12, height: 1),
                  iconSize: kReaderChromeIconSize,
                ),
              ),
              SizedBox(
                key: const Key('browser-options-cell'),
                width: unitWidth,
                child: PopupMenuButton<String>(
                  icon: const Icon(Icons.add, size: kReaderChromeIconSize),
                  tooltip: 'More options',
                  padding: EdgeInsets.zero,
                  popUpAnimationStyle: AnimationStyle.noAnimation,
                  position: PopupMenuPosition.under,
                  menuPadding: EdgeInsets.zero,
                  elevation: 0,
                  constraints: const BoxConstraints.tightFor(width: 216),
                  shape: const RoundedRectangleBorder(
                    side: BorderSide(color: Colors.black),
                  ),
                  onSelected: (value) {
                    switch (value) {
                      case 'search':
                        _controller.setSearchOpen(true);
                      case 'tabs':
                        _openTabs();
                      case 'newFolder':
                        _promptNewFolder();
                      case 'orientation':
                        _toggleBrowserOrientation();
                      case 'paste':
                        _showSnackFrom(
                          _controller.paste(
                            onErrors: (errors) =>
                                _showErrorsDialog('Paste errors', errors),
                          ),
                        );
                    }
                  },
                  itemBuilder: (context) => [
                    _boxedMenuItem('search', 'Search'),
                    _boxedMenuItem('tabs', 'Tabs'),
                    _boxedMenuItem('newFolder', 'New Folder'),
                    _boxedMenuItem(
                      'orientation',
                      MediaQuery.orientationOf(context) == Orientation.landscape
                          ? 'Portrait'
                          : 'Landscape',
                    ),
                    _boxedMenuItem(
                      'paste',
                      'Paste',
                      enabled: _controller.ops.hasClipboard,
                      onLongPress: _openAppDrawerFromPaste,
                      last: true,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  PopupMenuItem<String> _boxedMenuItem(
    String value,
    String label, {
    bool enabled = true,
    bool last = false,
    VoidCallback? onLongPress,
  }) {
    return PopupMenuItem(
      value: value,
      enabled: enabled,
      padding: EdgeInsets.zero,
      height: kReaderChromeRowHeight,
      child: InvertingPressListener(
        enabled: enabled || onLongPress != null,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onLongPress: onLongPress,
          child: Container(
            height: kReaderChromeRowHeight,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            foregroundDecoration: BoxDecoration(
              border: last
                  ? null
                  : const Border(bottom: BorderSide(color: Colors.black)),
            ),
            child: Text(label),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (_controller.startupState != LauncherStartupState.ready ||
            !_controller.permissionGranted) {
          return;
        }
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
          final state = _controller.startupState;
          if (state != LauncherStartupState.loading) {
            final errorEpoch = _startupHealth.errorEpoch;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted &&
                  _controller.startupState != LauncherStartupState.loading &&
                  errorEpoch == _startupHealth.errorEpoch) {
                _startupHealth.markHealthy();
              }
            });
          }
          if (state != LauncherStartupState.ready) {
            return LauncherRecoveryScreen(
              loading: state == LauncherStartupState.loading,
              message: _controller.startupMessage,
              onRetry: _initialize,
              onUseRoot: () => _initialize(useStorageRoot: true),
              onOpenApps: _openAppDrawer,
            );
          }
          final mediaQuery = MediaQuery.of(context);
          final totalBars = mediaQuery.orientation == Orientation.portrait
              ? kPortraitBarCount
              : kLandscapeBarCount;
          final barHeight = mediaQuery.size.height / totalBars;
          final selectionActions = _controller.selecting
              ? _selectionActions(barHeight)
              : const <Widget>[];
          final selectionColumns = _selectionColumns(
            mediaQuery.size.width,
            selectionActions.isEmpty ? 1 : selectionActions.length,
          );
          final topBarUnits = _controller.selecting
              ? 1 + (selectionActions.length / selectionColumns).ceil()
              : 1;
          final fileRowCount = totalBars - topBarUnits - 2;
          return Scaffold(
            appBar: _controller.selecting
                ? _buildSelectionBar(
                    barHeight,
                    selectionActions,
                    selectionColumns,
                  )
                : _buildBrowserBar(barHeight),
            body: Stack(
              children: [
                Column(
                  children: [
                    Container(
                      height: barHeight,
                      decoration: const BoxDecoration(
                        border: Border(bottom: BorderSide(color: Colors.black)),
                      ),
                      child: _buildTopBar(barHeight),
                    ),
                    Expanded(
                      child: PaginatedList<FileEntry>(
                        pageButtonsEnabled:
                            !_controller.searchOpen &&
                            _openingPath == null &&
                            !_openingTabs,
                        boxedNavigation: true,
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
                    bottom: 0,
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

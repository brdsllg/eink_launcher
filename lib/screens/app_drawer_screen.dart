import 'package:flutter/material.dart';

import '../constants.dart';
import '../models/launcher_app.dart';
import '../services/app_list_service.dart';
import '../widgets/clock_text.dart';
import '../widgets/paginated_list.dart';

class AppDrawerScreen extends StatefulWidget {
  const AppDrawerScreen({super.key});

  @override
  State<AppDrawerScreen> createState() => _AppDrawerScreenState();
}

class _AppDrawerScreenState extends State<AppDrawerScreen> {
  List<LauncherApp>? _apps;
  List<LauncherApp>? _filteredApps;
  int _currentPage = 0;
  bool _includeSystemApps = false;
  bool _searchOpen = false;
  String? _error;
  int _loadGeneration = 0;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadApps();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadApps({bool forceRefresh = false}) async {
    final generation = ++_loadGeneration;
    try {
      final apps = await AppListService.getLaunchableApps(
        forceRefresh: forceRefresh,
        includeSystemApps: _includeSystemApps,
      );
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _error = null;
        _apps = apps;
        _filterApps(_searchController.text);
      });
    } catch (_) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _apps = const [];
        _filteredApps = null;
        _error = 'Could not load apps. Tap Refresh to retry.';
      });
    }
  }

  Future<void> _launchApp(String packageName) async {
    try {
      await AppListService.launch(packageName);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open this app.'),
          animation: AlwaysStoppedAnimation(1.0),
        ),
      );
    }
  }

  void _refresh() {
    setState(() {
      _currentPage = 0;
      _apps = null;
      _filteredApps = null;
    });
    _loadApps(forceRefresh: true);
  }

  void _toggleSystemApps() {
    setState(() {
      _includeSystemApps = !_includeSystemApps;
      _currentPage = 0;
      _apps = null;
      _filteredApps = null;
    });
    _loadApps();
  }

  // Substring matching a few hundred in-memory app names is cheap enough to do
  // as the query changes, and gives immediate results without a search button.
  void _filterApps(String rawQuery) {
    final query = rawQuery.trim().toLowerCase();
    _filteredApps = query.isEmpty
        ? null
        : _apps?.where((app) {
            return app.name.toLowerCase().contains(query);
          }).toList();
  }

  void _onSearchChanged(String query) {
    setState(() {
      _currentPage = 0;
      _filterApps(query);
    });
  }

  void _openSearch() {
    setState(() => _searchOpen = true);
  }

  void _closeSearch() {
    setState(() {
      _searchOpen = false;
      _searchController.clear();
      _filteredApps = null;
      _currentPage = 0;
    });
  }

  List<LauncherApp> get _displayedApps => _filteredApps ?? _apps ?? const [];

  Widget _buildAppRow(LauncherApp app, double barHeight) {
    return Container(
      height: barHeight,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.black, width: 0.5)),
      ),
      child: InkWell(
        onTap: () => _launchApp(app.packageName),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              app.name,
              style: TextStyle(
                fontSize: (barHeight * 0.44).clamp(16.0, 26.0).toDouble(),
                height: 1,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
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

  Widget _buildAppGrid({
    required double barHeight,
    required int appRowCount,
    String? message,
  }) {
    return Stack(
      children: [
        PaginatedList<LauncherApp>(
          items: _displayedApps,
          currentPage: _currentPage,
          onPageChanged: (page) => setState(() => _currentPage = page),
          itemBuilder: (context, app) => _buildAppRow(app, barHeight),
          rowHeight: barHeight,
          navBarHeight: barHeight,
          preferredItemsPerPage: appRowCount,
          emptyItemBuilder: (context) => _buildEmptyRow(barHeight),
        ),
        if (message != null)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: barHeight,
            child: IgnorePointer(
              child: Center(
                child: Text(
                  message,
                  style: TextStyle(
                    fontSize: (barHeight * 0.36).clamp(15.0, 22.0).toDouble(),
                    height: 1,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final loading = _apps == null;
    final mediaQuery = MediaQuery.of(context);
    final totalBars = mediaQuery.orientation == Orientation.portrait
        ? kPortraitBarCount
        : kLandscapeBarCount;
    final barHeight = mediaQuery.size.height / totalBars;
    final appRowCount = totalBars - 2;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: barHeight,
        leading: _searchOpen
            ? IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Close search',
                onPressed: _closeSearch,
              )
            : null,
        title: _searchOpen
            ? TextField(
                controller: _searchController,
                autofocus: true,
                onChanged: _onSearchChanged,
                style: TextStyle(
                  fontSize: (barHeight * 0.4).clamp(17.0, 24.0).toDouble(),
                  height: 1,
                ),
                decoration: const InputDecoration(
                  hintText: 'Search apps',
                  border: InputBorder.none,
                ),
              )
            : Text(
                'Apps',
                style: TextStyle(
                  fontSize: (barHeight * 0.4).clamp(17.0, 24.0).toDouble(),
                  height: 1,
                ),
              ),
        centerTitle: !_searchOpen,
        actions: [
          if (!_searchOpen)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: ClockText(
                  style: TextStyle(
                    fontSize: (barHeight * 0.25).clamp(11.0, 15.0).toDouble(),
                    height: 1,
                    color: Colors.black,
                  ),
                ),
              ),
            ),
          if (!_searchOpen)
            IconButton(
              icon: const Icon(Icons.search),
              tooltip: 'Search apps',
              onPressed: _openSearch,
            ),
          if (!_searchOpen) ...[
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh apps',
              onPressed: _refresh,
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              tooltip: 'More options',
              popUpAnimationStyle: AnimationStyle.noAnimation,
              onSelected: (value) {
                if (value == 'toggleSystem') _toggleSystemApps();
              },
              itemBuilder: (context) => [
                CheckedPopupMenuItem<String>(
                  value: 'toggleSystem',
                  checked: _includeSystemApps,
                  child: const Text('Show system apps'),
                ),
              ],
            ),
          ],
        ],
        shape: const Border(
          bottom: BorderSide(color: Colors.black, width: 0.5),
        ),
      ),
      body: _buildAppGrid(
        barHeight: barHeight,
        appRowCount: appRowCount,
        message:
            _error ??
            (loading
                ? 'Loading…'
                : _displayedApps.isEmpty
                ? 'No matching apps'
                : null),
      ),
    );
  }
}

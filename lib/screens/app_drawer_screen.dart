import 'package:flutter/material.dart';
import 'package:installed_apps/app_info.dart';
import '../constants.dart';
import '../services/app_list_service.dart';
import '../widgets/clock_text.dart';
import '../widgets/paginated_list.dart';

class AppDrawerScreen extends StatefulWidget {
  const AppDrawerScreen({super.key});

  @override
  State<AppDrawerScreen> createState() => _AppDrawerScreenState();
}

class _AppDrawerScreenState extends State<AppDrawerScreen> {
  List<AppInfo>? _apps;
  List<AppInfo>? _filteredApps;
  int _currentPage = 0;
  bool _includeSystemApps = false;
  bool _searchOpen = false;
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
    final apps = await AppListService.getLaunchableApps(
      forceRefresh: forceRefresh,
      includeSystemApps: _includeSystemApps,
    );
    if (!mounted) return;
    setState(() => _apps = apps);
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

  // Substring match against the already-loaded list — no isolate needed, it's
  // at most a few hundred items. Triggered on submit/tap rather than on every
  // keystroke, matching the file browser's own search: e-ink panels redraw
  // slowly, so re-filtering (and repainting the list) on every keypress would
  // be distracting rather than helpful.
  void _runSearch() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      _currentPage = 0;
      _filteredApps = query.isEmpty
          ? null
          : _apps?.where((a) => a.name.toLowerCase().contains(query)).toList();
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

  List<AppInfo> get _displayedApps => _filteredApps ?? _apps ?? const [];

  @override
  Widget build(BuildContext context) {
    final loading = _apps == null;
    return Scaffold(
      appBar: AppBar(
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
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _runSearch(),
                decoration: const InputDecoration(
                  hintText: 'Search apps',
                  border: InputBorder.none,
                ),
              )
            : const Text('Apps'),
        centerTitle: !_searchOpen,
        actions: [
          if (!_searchOpen)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Center(child: ClockText()),
            ),
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: _searchOpen ? 'Run search' : 'Search apps',
            onPressed: _searchOpen ? _runSearch : _openSearch,
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
      ),
      body: loading
          ? const Center(child: Text('Loading…'))
          : _displayedApps.isEmpty
              ? const Center(child: Text('No matching apps'))
              : PaginatedList<AppInfo>(
                  items: _displayedApps,
                  currentPage: _currentPage,
                  onPageChanged: (page) => setState(() => _currentPage = page),
                  itemBuilder: (context, app) => SizedBox(
                    height: kRowHeight,
                    child: ListTile(
                      title: Text(app.name),
                      onTap: () => AppListService.launch(app.packageName),
                    ),
                  ),
                ),
    );
  }
}

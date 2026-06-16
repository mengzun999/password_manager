import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/services/app_list_service.dart';
import '../providers/settings_provider.dart';
import '../app.dart';

class AppListPage extends ConsumerStatefulWidget {
  const AppListPage({super.key});

  @override
  ConsumerState<AppListPage> createState() => _AppListPageState();
}

class _AppListPageState extends ConsumerState<AppListPage> {
  String _searchKeyword = '';
  List<AppInfo> _displayApps = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  String? _error;
  bool _showUserApps = true;
  bool _allLoaded = false;

  @override
  void initState() {
    super.initState();
    // ✅ 使用 Future.microtask 让 UI 先渲染
    Future.microtask(() => _loadApps());
  }

  Future<void> _loadApps() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // ✅ 后台获取，UI 会显示加载状态
      final apps = await AppListService.getInstalledApps(initialCount: 30);
      setState(() {
        _displayApps = apps;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  /// 加载更多
  void _loadMore() {
    if (_isLoadingMore || _allLoaded) return;

    final allApps = AppListService.getAllApps();
    if (_displayApps.length >= allApps.length) {
      setState(() => _allLoaded = true);
      return;
    }

    setState(() => _isLoadingMore = true);

    final nextBatch = allApps.sublist(
      _displayApps.length,
      (_displayApps.length + 20).clamp(0, allApps.length),
    );

    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        setState(() {
          _displayApps.addAll(nextBatch);
          _isLoadingMore = false;
          if (_displayApps.length >= allApps.length) {
            _allLoaded = true;
          }
        });
      }
    });
  }

  bool _isSystemApp(String packageName) {
    final systemPrefixes = [
      'android',
      'com.android',
      'com.google.android',
      'com.google.android.gms',
      'com.google.android.apps',
      'com.oplus',
      'com.coloros',
      'com.heytap',
      'com.nearme',
      'com.oppo',
      'com.oneplus',
    ];
    return systemPrefixes.any(packageName.startsWith);
  }

  List<AppInfo> get _filteredApps {
    List<AppInfo> filtered;
    if (_showUserApps) {
      filtered = _displayApps.where((app) => !_isSystemApp(app.packageName)).toList();
    } else {
      filtered = _displayApps.where((app) => _isSystemApp(app.packageName)).toList();
    }

    if (_searchKeyword.isEmpty) {
      return filtered;
    }

    final keyword = _searchKeyword.toLowerCase();
    return filtered.where((app) {
      return app.appName.toLowerCase().contains(keyword) ||
          app.packageName.toLowerCase().contains(keyword);
    }).toList();
  }

  Future<void> _toggleViewMode() async {
    final settings = ref.read(settingsProvider);
    final newMode = settings.appListViewMode == 'grid' ? 'list' : 'grid';
    await ref.read(settingsProvider.notifier).setAppListViewMode(newMode);
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final viewMode = settings.appListViewMode;

    return Scaffold(
      appBar: AppBar(
        title: const Text('选择应用'),
        centerTitle: false,
        actions: [
          IconButton(
            icon: Icon(viewMode == 'grid' ? Icons.list : Icons.grid_view),
            onPressed: _toggleViewMode,
            tooltip: viewMode == 'grid' ? '切换为列表' : '切换为网格',
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(110),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: '搜索应用...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchKeyword.isNotEmpty
                        ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        setState(() {
                          _searchKeyword = '';
                        });
                      },
                    )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    filled: true,
                    fillColor: Theme.of(context).brightness == Brightness.light
                        ? Colors.white
                        : Colors.grey[800],
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  ),
                  onChanged: (value) {
                    setState(() {
                      _searchKeyword = value;
                    });
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _showUserApps = !_showUserApps;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColor,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Center(
                      child: Text(
                        _showUserApps ? '用户应用' : '系统应用',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _buildErrorState()
          : _displayApps.isEmpty
          ? _buildEmptyState()
          : _filteredApps.isEmpty
          ? _buildNoResultState()
          : viewMode == 'grid'
          ? _buildGridView()
          : _buildListView(),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red.shade300),
            const SizedBox(height: 16),
            Text(
              '加载失败',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadApps,
              icon: const Icon(Icons.refresh),
              label: const Text('重新加载'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.apps, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            '没有找到已安装的应用',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '请确认已安装第三方应用',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade500,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _loadApps,
            icon: const Icon(Icons.refresh),
            label: const Text('重新加载'),
          ),
        ],
      ),
    );
  }

  Widget _buildNoResultState() {
    final typeName = _showUserApps ? '用户应用' : '系统应用';
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            _searchKeyword.isNotEmpty
                ? '没有找到 "$_searchKeyword"'
                : '没有找到$typeName',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _searchKeyword.isNotEmpty
                ? '试试其他关键词'
                : '请确认应用已安装',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGridView() {
    final filteredApps = _filteredApps;

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.8,
      ),
      itemCount: filteredApps.length + (_isLoadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= filteredApps.length) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        final app = filteredApps[index];
        return _buildAppItem(app);
      },
    );
  }

  Widget _buildListView() {
    final filteredApps = _filteredApps;

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.pixels >= notification.metrics.maxScrollExtent - 200) {
          _loadMore();
        }
        return false;
      },
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: filteredApps.length + (_isLoadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= filteredApps.length) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }
          final app = filteredApps[index];
          return _buildAppItem(app);
        },
      ),
    );
  }

  Widget _buildAppItem(AppInfo app) {
    final settings = ref.watch(settingsProvider);
    final isGrid = settings.appListViewMode == 'grid';

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: () {
          Navigator.pushNamed(
            context,
            AppRoutes.addEdit,
            arguments: app.appName,
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: EdgeInsets.all(isGrid ? 16 : 12),
          child: isGrid
              ? _buildGridItemContent(app)
              : _buildListItemContent(app),
        ),
      ),
    );
  }

  Widget _buildGridItemContent(AppInfo app) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: Colors.grey.shade100,
            ),
            child: FutureBuilder<Uint8List?>(
              future: AppListService.loadAppIcon(app.packageName),
              builder: (context, snapshot) {
                final iconBytes = snapshot.data;
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Icon(
                    Icons.apps,
                    color: Colors.grey.shade400,
                    size: 32,
                  );
                }
                if (iconBytes != null) {
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(
                      iconBytes,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Icon(
                        Icons.apps,
                        color: Theme.of(context).primaryColor,
                        size: 32,
                      ),
                    ),
                  );
                }
                return Icon(
                  Icons.apps,
                  color: Theme.of(context).primaryColor.withValues(alpha: 0.5),
                  size: 32,
                );
              },
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: Text(
              app.appName,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildListItemContent(AppInfo app) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: Colors.grey.shade100,
          ),
          child: FutureBuilder<Uint8List?>(
            future: AppListService.loadAppIcon(app.packageName),
            builder: (context, snapshot) {
              final iconBytes = snapshot.data;
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Icon(
                  Icons.apps,
                  color: Colors.grey.shade400,
                  size: 24,
                );
              }
              if (iconBytes != null) {
                return ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(
                    iconBytes,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Icon(
                      Icons.apps,
                      color: Theme.of(context).primaryColor,
                      size: 24,
                    ),
                  ),
                );
              }
              return Icon(
                Icons.apps,
                color: Theme.of(context).primaryColor.withValues(alpha: 0.5),
                size: 24,
              );
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                app.appName,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                app.packageName,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              ),
            ],
          ),
        ),
        Icon(Icons.chevron_right, color: Colors.grey.shade400),
      ],
    );
  }
}
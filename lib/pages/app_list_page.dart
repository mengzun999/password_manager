import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/services/app_list_service.dart';
import '../providers/settings_provider.dart';
import '../app.dart';

/// 应用列表页面
///
/// 显示手机中已安装的应用（目前用模拟数据）
/// 用户点击某个应用后，自动跳转到添加密码页面
/// 并把选中的应用名称作为标题预设
class AppListPage extends ConsumerStatefulWidget {
  const AppListPage({super.key});

  @override
  ConsumerState<AppListPage> createState() => _AppListPageState();
}

class _AppListPageState extends ConsumerState<AppListPage> {
  // ========== 状态变量 ==========

  /// 搜索关键词（用户在搜索框输入的文字）
  String _searchKeyword = '';

  // ========== 辅助方法 ==========

  /// 获取过滤后的应用列表
  List<AppInfo> get _filteredApps {
    if (_searchKeyword.isEmpty) {
      return AppListService.getCommonApps();
    }

    final keyword = _searchKeyword.toLowerCase();
    return AppListService.getCommonApps().where((app) {
      return app.appName.toLowerCase().contains(keyword) ||
          app.packageName.toLowerCase().contains(keyword);
    }).toList();
  }

  /// 切换视图模式
  Future<void> _toggleViewMode() async {
    final settings = ref.read(settingsProvider);
    final newMode = settings.appListViewMode == 'grid' ? 'list' : 'grid';
    await ref.read(settingsProvider.notifier).setAppListViewMode(newMode);
  }

  // ========== 界面构建方法 ==========

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
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
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
        ),
      ),
      body: viewMode == 'grid' ? _buildGridView() : _buildListView(),
    );
  }

  /// 网格视图（3列）
  Widget _buildGridView() {
    final filteredApps = _filteredApps;

    if (filteredApps.isEmpty) {
      return _buildEmptyState();
    }

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.9,
      ),
      itemCount: filteredApps.length,
      itemBuilder: (context, index) {
        final app = filteredApps[index];
        return _buildAppItem(app);
      },
    );
  }

  /// 列表视图（1列）
  Widget _buildListView() {
    final filteredApps = _filteredApps;

    if (filteredApps.isEmpty) {
      return _buildEmptyState();
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: filteredApps.length,
      itemBuilder: (context, index) {
        final app = filteredApps[index];
        return _buildAppItem(app);
      },
    );
  }

  /// 空状态页面
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            '没有找到相关应用',
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  /// 单个应用项
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

  /// 网格视图的内容
  Widget _buildGridItemContent(AppInfo app) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            Icons.apps,
            color: Theme.of(context).primaryColor,
            size: 32,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          app.appName,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12),
        ),
      ],
    );
  }

  /// 列表视图的内容
  Widget _buildListItemContent(AppInfo app) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            Icons.apps,
            color: Theme.of(context).primaryColor,
            size: 24,
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
                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              ),
            ],
          ),
        ),
        Icon(Icons.chevron_right, color: Colors.grey[400]),
      ],
    );
  }
}
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mtbbs/api/forum/forumdisplay/export.dart' as forum_api;
import 'package:mtbbs/core/site_store.dart';
import 'package:mtbbs/services/api_service.dart';
import '../../controllers/thread_list_controller.dart';
import '../../widgets/thread_grid.dart';
import '../../widgets/tab_page_layout.dart';

/// 版块页面
///
/// 路径: /forum?fid=xxx
/// - 带 fid：显示对应版块的帖子列表，标题为版块名
/// - 不带 fid：显示所有版块标签页（仅通过直接导航访问）
class CommunityPage extends StatefulWidget {
  final String fid;

  const CommunityPage({super.key, this.fid = ''});

  @override
  State<CommunityPage> createState() => _CommunityPageState();
}

class _CommunityPageState extends State<CommunityPage> {
  static final Map<String, ThreadListController> _ctrlMap = {};
  final Map<String, String> _orderbyMap = {};
  final Map<String, String> _filterMap = {};
  String _activeKey = '';

  List<TabInfo> get _tabs => SiteStore.instance.defaultForumOrder
      .where((fid) => SiteStore.instance.forums.containsKey(fid))
      .map((fid) => TabInfo(SiteStore.instance.forums[fid]!, fid))
      .toList();

  void _ensureCtls() {
    for (final t in _tabs) {
      _ctrlMap.putIfAbsent(
        t.key,
        () => ThreadListController(
          fetchFn: ({required int page}) => forum_api.getForumThreads(
            ApiService().dio,
            fid: t.key,
            orderby: _orderbyMap[t.key] ?? '',
            filter: _filterMap[t.key] ?? '',
            page: page,
          ),
        ),
      );
    }
  }

  void _loadTab(String key) {
    final ctrl = _ctrlMap[key];
    if (ctrl != null && ctrl.state == LoadState.initial) ctrl.loadInitial();
  }

  void _showFilterDialog() {
    final activeKey = _activeKey;
    String tO = _orderbyMap[activeKey] ?? '';
    String tF = _filterMap[activeKey] ?? '';
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('筛选排序'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '排序',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  _chip('默认', tO == '', () => setD(() => tO = '')),
                  _chip(
                    '发布时间',
                    tO == 'dateline',
                    () => setD(() => tO = 'dateline'),
                  ),
                  _chip(
                    '回复数',
                    tO == 'replies',
                    () => setD(() => tO = 'replies'),
                  ),
                  _chip('浏览次数', tO == 'views', () => setD(() => tO = 'views')),
                  _chip(
                    '推荐数',
                    tO == 'recommends',
                    () => setD(() => tO = 'recommends'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '筛选',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  _chip('全部', tF == '', () => setD(() => tF = '')),
                  _chip('精华', tF == 'digest', () => setD(() => tF = 'digest')),
                  _chip('热门', tF == 'hot', () => setD(() => tF = 'hot')),
                  _chip(
                    '推荐',
                    tF == 'recommend',
                    () => setD(() => tF = 'recommend'),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                _orderbyMap[activeKey] = tO;
                _filterMap[activeKey] = tF;
                Navigator.of(ctx).pop();
                _ctrlMap.remove(activeKey);
                _ensureCtls();
                setState(() {});
                WidgetsBinding.instance.addPostFrameCallback(
                  (_) => _loadTab(activeKey),
                );
              },
              child: const Text('应用'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return FilterChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: selected,
      onSelected: (_) => onTap(),
    );
  }

  // ==================== 单版块模式 ====================

  Widget _buildSingleForum() {
    final fid = widget.fid;
    _activeKey = fid;
    _ensureCtls();
    final ctrl = _ctrlMap[fid];
    if (ctrl != null && ctrl.state == LoadState.initial) {
      WidgetsBinding.instance.addPostFrameCallback((_) => ctrl.loadInitial());
    }
    if (ctrl == null) {
      return const Center(child: Text('版块不存在'));
    }
    return ThreadGrid(controller: ctrl, visible: true);
  }

  // ==================== 标签页模式 ====================

  Widget _buildTabs() {
    final tabs = _tabs;
    if (_activeKey.isEmpty && tabs.isNotEmpty) _activeKey = tabs.first.key;
    _ensureCtls();
    return TabPageLayout(
      tabs: tabs,
      initialKey: tabs.isNotEmpty ? tabs.first.key : '',
      tabTuneIcon: Icons.filter_list,
      onTabTune: _showFilterDialog,
      onFocusChanged: (key) => _activeKey = key,
      buildPage: (key, _, isActive) {
        final ctrl = _ctrlMap[key];
        if (ctrl == null) return const SizedBox.shrink();
        return ThreadGrid(controller: ctrl, visible: isActive);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // 监听 SiteStore 变化（如论坛列表加载完成后重建标签页）
    context.watch<SiteStore>();
    final cs = Theme.of(context).colorScheme;
    // 带 fid 时使用单版块模式
    if (widget.fid.isNotEmpty) {
      final ctrl = _ctrlMap[widget.fid];
      return Scaffold(
        appBar: AppBar(
          title: Text(SiteStore.instance.forums[widget.fid] ?? widget.fid),
          surfaceTintColor: cs.surface,
          elevation: 0.5,
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh, size: 20),
              tooltip: '刷新',
              onPressed: ctrl != null ? () => ctrl.refresh() : null,
            ),
            IconButton(
              icon: const Icon(Icons.filter_list, size: 20),
              tooltip: '筛选排序',
              onPressed: _showFilterDialog,
            ),
          ],
        ),
        body: _buildSingleForum(),
      );
    }
    // 不带 fid 时显示所有版块标签页
    return Scaffold(
      appBar: AppBar(
        title: const Text('社区'),
        surfaceTintColor: cs.surface,
        elevation: 0.5,
      ),
      body: _buildTabs(),
    );
  }
}

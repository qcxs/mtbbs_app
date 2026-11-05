import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:mtbbs/core/app/site_scope.dart';
import 'package:mtbbs/core/app/site_store.dart';
import 'package:mtbbs/providers/history_provider.dart';
import 'package:mtbbs/providers/settings_provider.dart';
import 'package:mtbbs/models/browse_record.dart';
import 'package:mtbbs/core/utils/formatters.dart';
import 'package:mtbbs/widgets/dialog/confirm_dialog.dart';
import 'package:mtbbs/widgets/layout/state_views.dart';

/// 浏览历史记录页面
///
/// 默认展示**全部站点**的记录，可按站点筛选；支持按类型过滤（全部/帖子/用户/我的帖子/回复），
/// 点击查看详情，滑动删除。
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  /// 站点筛选：null = 全部站点；否则为目标站点 host
  String? _siteFilter;

  static const _tabs = ['全部', '帖子', '用户', '我的帖子', '回复'];

  /// 支持带 `site=` 在 App 内打开的页面类型。
  ///
  /// 「我的帖子 / 回复」走 `/my-threads`，页面未接入站点作用域，跨站打开会显示
  /// 当前站点的数据，故不允许跨站跳转（见 `_RecordDetailSheet`）。
  static const _crossSiteTypes = {'thread', 'user'};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _typeForIndex(int index) {
    switch (index) {
      case 1:
        return 'thread';
      case 2:
        return 'user';
      case 3:
        return 'mythread';
      case 4:
        return 'reply';
      default:
        return '';
    }
  }

  Future<void> _confirmClear(BuildContext context, int tabIndex) async {
    final history = context.read<HistoryProvider>();
    final type = _typeForIndex(tabIndex);
    final label = _tabs[tabIndex];
    final scopeLabel = _siteFilter == null
        ? '全部站点'
        : history.siteLabel(_siteFilter!);
    final confirmed = await showConfirmDialog(
      context,
      title: '清空记录',
      message: _siteFilter == null
          ? '确定清空「全部站点 · $label」的浏览记录吗？会删除所有站点的同类记录，且不可恢复。'
          : '确定清空「$scopeLabel · $label」的浏览记录吗？',
      confirmText: '清空',
      maxWidth: 400,
    );
    if (confirmed == true && context.mounted) {
      await history.clearFiltered(host: _siteFilter, type: type);
      // 该站点已无任何记录时自动回到「全部站点」，避免停在空列表
      if (mounted &&
          _siteFilter != null &&
          !history.recordHosts.contains(_siteFilter)) {
        setState(() => _siteFilter = null);
      }
    }
  }

  /// 显示浏览记录详情底部弹窗
  void _showDetail(BrowseRecord record) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => _RecordDetailSheet(record: record),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final history = context.watch<HistoryProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _siteFilter == null
              ? '浏览记录'
              : '浏览记录 · ${history.siteLabel(_siteFilter!)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        surfaceTintColor: cs.surface,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelPadding: const EdgeInsets.symmetric(horizontal: 12),
            indicatorPadding: EdgeInsets.zero,
            tabs: [
              Tab(text: '全部 (${history.count(host: _siteFilter)})'),
              Tab(
                text: '帖子 (${history.count(type: 'thread', host: _siteFilter)})',
              ),
              Tab(
                text: '用户 (${history.count(type: 'user', host: _siteFilter)})',
              ),
              Tab(
                text:
                    '我的帖子 (${history.count(type: 'mythread', host: _siteFilter)})',
              ),
              Tab(
                text: '回复 (${history.count(type: 'reply', host: _siteFilter)})',
              ),
            ],
            labelColor: Theme.of(context).colorScheme.onSurfaceVariant,
            unselectedLabelColor: cs.onSurfaceVariant,
            indicatorColor: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        actions: [
          // 站点筛选：默认「全部站点」，切换站点后计数与列表一起变化
          PopupMenuButton<String>(
            tooltip: _siteFilter == null
                ? '站点筛选：全部站点'
                : '站点筛选：${history.siteLabel(_siteFilter!)}',
            icon: const Icon(Icons.language, size: 20),
            padding: EdgeInsets.zero,
            onSelected: (v) =>
                setState(() => _siteFilter = v.isEmpty ? null : v),
            itemBuilder: (_) {
              final hosts = history.recordHosts;
              return [
                CheckedPopupMenuItem<String>(
                  value: '',
                  checked: _siteFilter == null,
                  child: Text('全部站点 (${history.count()})'),
                ),
                if (hosts.isNotEmpty) const PopupMenuDivider(),
                for (final host in hosts)
                  CheckedPopupMenuItem<String>(
                    value: host,
                    checked: _siteFilter == host,
                    child: Text(
                      '${history.siteLabel(host)} (${history.count(host: host)})',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ];
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 20),
            padding: EdgeInsets.zero,
            onSelected: (v) {
              if (v == 'clear') _confirmClear(context, _tabController.index);
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'clear',
                child: Text(
                  _siteFilter == null
                      ? '清空当前Tab（全部站点）'
                      : '清空当前Tab（${history.siteLabel(_siteFilter!)}）',
                ),
              ),
            ],
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _RecordList(type: '', host: _siteFilter, onShowDetail: _showDetail),
          _RecordList(
            type: 'thread',
            host: _siteFilter,
            onShowDetail: _showDetail,
          ),
          _RecordList(type: 'user', host: _siteFilter, onShowDetail: _showDetail),
          _RecordList(
            type: 'mythread',
            host: _siteFilter,
            onShowDetail: _showDetail,
          ),
          _RecordList(
            type: 'reply',
            host: _siteFilter,
            onShowDetail: _showDetail,
          ),
        ],
      ),
    );
  }
}

// ==================== 详情底部弹窗 ====================

/// 根据记录类型获取标题模板
String _titleTemplateFor(SettingsProvider s, String type) => switch (type) {
  'thread' => s.historyTitleFormatThread,
  'user' => s.historyTitleFormatUser,
  'mythread' => s.historyTitleFormatMythread,
  'reply' => s.historyTitleFormatReply,
  _ => '{typeLabel}',
};

class _RecordDetailSheet extends StatelessWidget {
  final BrowseRecord record;
  const _RecordDetailSheet({required this.record});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final info = record.info;
    final title = record.displayTitle(
      _titleTemplateFor(context.read<SettingsProvider>(), record.type),
    );

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 标题栏
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    '记录详情',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // 信息列表（可滚动区域，仅内容超出时显示滚动条）
          Flexible(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                _infoRow(context, '标题', title),
                _infoRow(context, '类型', _RecordList._typeLabel(record.type)),
                if (record.effectiveHost.isNotEmpty)
                  _infoRow(
                    context,
                    '站点',
                    context.read<HistoryProvider>().siteLabel(
                      record.effectiveHost,
                    ),
                  ),
                _infoRow(context, '路由', record.routePath),
                _infoRow(context, 'ID', record.id),
                _infoRow(context, '时间', formatDateTimeFull(record.timestamp)),
                if (info.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Divider(height: 1),
                  const SizedBox(height: 8),
                  Text(
                    '原始数据',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  for (final entry in info.entries)
                    _infoRow(context, entry.key, entry.value?.toString() ?? ''),
                ],
              ],
            ),
          ),

          // 操作按钮
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      context.read<HistoryProvider>().remove(record.id);
                      Navigator.of(context).pop();
                    },
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('删除'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: cs.error,
                      side: BorderSide(color: cs.error),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () {
                      final host = record.effectiveHost;
                      final foreign =
                          host.isNotEmpty && host != SiteStore.instance.host;
                      // 只允许带 `site=` 在 App 内打开的类型；「我的帖子 / 回复」
                      // 走 `/my-threads`，页面未接入站点作用域，跨站会看到当前站点数据
                      final canOpen =
                          !foreign ||
                          _HistoryPageState._crossSiteTypes.contains(
                            record.type,
                          );
                      // 先取路由与 ScaffoldMessenger：pop 之后本 context 已失效
                      final router = GoRouter.of(context);
                      final messenger = ScaffoldMessenger.of(context);
                      Navigator.of(context).pop();
                      if (!canOpen) {
                        messenger.showSnackBar(
                          const SnackBar(content: Text('该记录来自其它站点，暂不支持跨站打开')),
                        );
                        return;
                      }
                      router.push(
                        foreign
                            ? withSiteParam(record.routePath, host)
                            : record.routePath,
                      );
                    },
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: const Text('前往查看'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(BuildContext context, String label, String value) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 56,
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
            ),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}

// ==================== 记录列表 ====================

/// 记录列表（点击查看详情）
class _RecordList extends StatelessWidget {
  final String type;

  /// 站点筛选：null = 全部站点（同时展示站点标签）
  final String? host;

  final void Function(BrowseRecord) onShowDetail;
  const _RecordList({
    required this.type,
    this.host,
    required this.onShowDetail,
  });

  static IconData _typeIcon(String t) => switch (t) {
    'thread' => Icons.article_outlined,
    'user' => Icons.person_outline,
    'mythread' => Icons.list_alt,
    'reply' => Icons.reply,
    _ => Icons.history,
  };

  static String _typeLabel(String t) => switch (t) {
    'thread' => '帖子',
    'user' => '用户',
    'mythread' => '我的帖子',
    'reply' => '回复',
    _ => t,
  };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final history = context.watch<HistoryProvider>();
    final records = history.query(type: type, host: host);

    if (records.isEmpty) {
      return const EmptyView(icon: Icons.history, text: '暂无浏览记录');
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: records.length,
      separatorBuilder: (_, __) =>
          Divider(height: 1, indent: 56, color: cs.outlineVariant),
      itemBuilder: (context, index) {
        final record = records[index];
        final title = record.displayTitle(
          _titleTemplateFor(context.read<SettingsProvider>(), record.type),
        );
        // 「全部站点」模式下用站点标签区分同号记录（筛选单站点时无意义，省略）
        final showSite = host == null && record.effectiveHost.isNotEmpty;
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: cs.onSurfaceVariant.withValues(alpha: 0.1),
            child: Icon(
              _typeIcon(record.type),
              color: cs.onSurfaceVariant,
              size: 20,
            ),
          ),
          title: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14),
          ),
          subtitle: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  _typeLabel(record.type),
                  style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                formatRelativeTime(record.timestamp),
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
              if (showSite) ...[
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    history.siteLabel(record.effectiveHost),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                ),
              ],
            ],
          ),
          trailing: Icon(
            Icons.chevron_right,
            size: 18,
            color: cs.onSurfaceVariant,
          ),
          onTap: () => onShowDetail(record),
        );
      },
    );
  }
}

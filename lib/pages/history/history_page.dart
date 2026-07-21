import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../providers/history_provider.dart';
import '../../models/browse_record.dart';

/// 浏览历史记录页面
///
/// 支持按类型过滤（全部/帖子/用户），点击查看详情，滑动删除。
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  static const _tabs = ['全部', '帖子', '用户'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
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
      default:
        return '';
    }
  }

  Future<void> _confirmClear(BuildContext context, int tabIndex) async {
    final type = _typeForIndex(tabIndex);
    final label = _tabs[tabIndex];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        constraints: const BoxConstraints(maxWidth: 400),
        title: const Text('清空记录'),
        content: Text('确定清空「$label」的浏览记录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      final history = context.read<HistoryProvider>();
      if (type.isEmpty) {
        await history.clear();
      } else {
        await history.clearByType(type);
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
        title: const Text('浏览记录'),
        surfaceTintColor: cs.surface,
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: '全部 (${history.totalCount})'),
            Tab(text: '帖子 (${history.getByType('thread').length})'),
            Tab(text: '用户 (${history.getByType('user').length})'),
          ],
          labelColor: Theme.of(context).colorScheme.onSurfaceVariant,
          unselectedLabelColor: cs.onSurfaceVariant,
          indicatorColor: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 20),
            padding: EdgeInsets.zero,
            onSelected: (v) {
              if (v == 'clear') _confirmClear(context, _tabController.index);
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'clear', child: Text('清空当前Tab')),
            ],
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _RecordList(type: '', onShowDetail: _showDetail),
          _RecordList(type: 'thread', onShowDetail: _showDetail),
          _RecordList(type: 'user', onShowDetail: _showDetail),
        ],
      ),
    );
  }
}

// ==================== 详情底部弹窗 ====================

class _RecordDetailSheet extends StatelessWidget {
  final BrowseRecord record;
  const _RecordDetailSheet({required this.record});

  String _formatTime(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final info = record.info;

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
                _infoRow(context, '标题', record.title),
                _infoRow(context, '类型', record.type == 'thread' ? '帖子' : '用户'),
                _infoRow(context, '路由', record.routePath),
                _infoRow(context, 'ID', record.id),
                _infoRow(context, '时间', _formatTime(record.timestamp)),
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
                      Navigator.of(context).pop();
                      context.push(record.routePath);
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

/// 记录列表（支持滑动删除 + 点击查看详情）
class _RecordList extends StatelessWidget {
  final String type;
  final void Function(BrowseRecord) onShowDetail;
  const _RecordList({required this.type, required this.onShowDetail});

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
    if (diff.inDays < 1) return '${diff.inHours} 小时前';
    if (diff.inDays < 7) return '${diff.inDays} 天前';
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$m-$d $h:$min';
  }

  IconData _typeIcon(String t) =>
      t == 'thread' ? Icons.article_outlined : Icons.person_outline;

  Color _typeColor(String t, ColorScheme cs) =>
      t == 'thread' ? cs.onSurfaceVariant : cs.onSurfaceVariant;

  String _typeLabel(String t) => t == 'thread' ? '帖子' : '用户';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final history = context.watch<HistoryProvider>();
    final records = type.isEmpty ? history.getAll() : history.getByType(type);

    if (records.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history, size: 48, color: cs.outlineVariant),
            const SizedBox(height: 8),
            Text(
              '暂无浏览记录',
              style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: records.length,
      separatorBuilder: (_, __) =>
          Divider(height: 1, indent: 56, color: cs.outlineVariant),
      itemBuilder: (context, index) {
        final record = records[index];
        return Dismissible(
          key: ValueKey(record.id),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            color: cs.errorContainer,
            child: Icon(Icons.delete_outline, color: cs.error),
          ),
          onDismissed: (_) {
            context.read<HistoryProvider>().remove(record.id);
          },
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: _typeColor(
                record.type,
                cs,
              ).withValues(alpha: 0.1),
              child: Icon(
                _typeIcon(record.type),
                color: _typeColor(record.type, cs),
                size: 20,
              ),
            ),
            title: Text(
              record.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14),
            ),
            subtitle: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: _typeColor(record.type, cs).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    _typeLabel(record.type),
                    style: TextStyle(
                      fontSize: 10,
                      color: _typeColor(record.type, cs),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _formatTime(record.timestamp),
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ],
            ),
            trailing: Icon(
              Icons.chevron_right,
              size: 18,
              color: cs.onSurfaceVariant,
            ),
            onTap: () => onShowDetail(record),
          ),
        );
      },
    );
  }
}

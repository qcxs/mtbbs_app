import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/history_provider.dart';
import '../models/browse_record.dart';

/// 历史记录选择器 — 用于编辑器弹窗
///
/// 显示浏览记录列表，支持 Tab 过滤（全部/帖子/用户），
/// 选中后通过 [onPick] 回调返回 [BrowseRecord]。
class HistoryPicker extends StatefulWidget {
  final void Function(BrowseRecord record) onPick;

  const HistoryPicker({super.key, required this.onPick});

  @override
  State<HistoryPicker> createState() => _HistoryPickerState();
}

class _HistoryPickerState extends State<HistoryPicker>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

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

  @override
  Widget build(BuildContext context) {
    final history = context.watch<HistoryProvider>();

    return Column(
      children: [
        TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: '全部 (${history.totalCount})'),
            Tab(text: '帖子 (${history.getByType('thread').length})'),
            Tab(text: '用户 (${history.getByType('user').length})'),
          ],
          labelColor: Theme.of(context).colorScheme.onSurfaceVariant,
          unselectedLabelColor: Theme.of(context).colorScheme.onSurfaceVariant,
          indicatorColor: Theme.of(context).colorScheme.onSurfaceVariant,
          tabAlignment: TabAlignment.fill,
          labelStyle: const TextStyle(fontSize: 12),
        ),
        const Divider(height: 1),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _PickerList(type: '', onPick: widget.onPick),
              _PickerList(type: 'thread', onPick: widget.onPick),
              _PickerList(type: 'user', onPick: widget.onPick),
            ],
          ),
        ),
      ],
    );
  }
}

/// 选择器内部列表
class _PickerList extends StatelessWidget {
  final String type;
  final void Function(BrowseRecord) onPick;

  const _PickerList({required this.type, required this.onPick});

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
        child: Text(
          '暂无浏览记录',
          style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 2),
      itemCount: records.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 56),
      itemBuilder: (_, index) {
        final record = records[index];
        final typeColor = _typeColor(record.type, cs);
        return ListTile(
          dense: true,
          leading: CircleAvatar(
            radius: 16,
            backgroundColor: typeColor.withValues(alpha: 0.1),
            child: Icon(_typeIcon(record.type), color: typeColor, size: 16),
          ),
          title: Text(
            record.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13),
          ),
          subtitle: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 0),
                decoration: BoxDecoration(
                  color: typeColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(2),
                ),
                child: Text(
                  _typeLabel(record.type),
                  style: TextStyle(fontSize: 9, color: typeColor),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                _formatTime(record.timestamp),
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              ),
            ],
          ),
          onTap: () => onPick(record),
        );
      },
    );
  }
}

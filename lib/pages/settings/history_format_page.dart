import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mtbbs/providers/settings_provider.dart';
import 'package:mtbbs/widgets/common/toast_utils.dart';

/// 浏览历史 — 插入格式设置页
///
/// 编辑器中选择历史记录时，使用此格式生成插入文本。
/// 占位符来自记录 info 字段，如 {title}、{author}、{time}、{nickname}、{uid} 等。
class HistoryFormatPage extends StatefulWidget {
  const HistoryFormatPage({super.key});

  @override
  State<HistoryFormatPage> createState() => _HistoryFormatPageState();
}

class _HistoryFormatPageState extends State<HistoryFormatPage> {
  late TextEditingController _threadCtl;
  late TextEditingController _userCtl;
  late TextEditingController _titleThreadCtl;
  late TextEditingController _titleUserCtl;
  late TextEditingController _titleMythreadCtl;
  late TextEditingController _titleReplyCtl;

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsProvider>();
    _threadCtl = TextEditingController(text: settings.historyFormatThread);
    _userCtl = TextEditingController(text: settings.historyFormatUser);
    _titleThreadCtl = TextEditingController(
      text: settings.historyTitleFormatThread,
    );
    _titleUserCtl = TextEditingController(
      text: settings.historyTitleFormatUser,
    );
    _titleMythreadCtl = TextEditingController(
      text: settings.historyTitleFormatMythread,
    );
    _titleReplyCtl = TextEditingController(
      text: settings.historyTitleFormatReply,
    );
  }

  @override
  void dispose() {
    _threadCtl.dispose();
    _userCtl.dispose();
    _titleThreadCtl.dispose();
    _titleUserCtl.dispose();
    _titleMythreadCtl.dispose();
    _titleReplyCtl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final settings = context.read<SettingsProvider>();
    await settings.setHistoryFormatThread(_threadCtl.text.trim());
    await settings.setHistoryFormatUser(_userCtl.text.trim());
    await settings.setHistoryTitleFormatThread(_titleThreadCtl.text.trim());
    await settings.setHistoryTitleFormatUser(_titleUserCtl.text.trim());
    await settings.setHistoryTitleFormatMythread(_titleMythreadCtl.text.trim());
    await settings.setHistoryTitleFormatReply(_titleReplyCtl.text.trim());
    if (mounted) {
      showToast('已保存', duration: const Duration(seconds: 1));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('插入格式'),
        surfaceTintColor: cs.surface,
        actions: [TextButton(onPressed: _save, child: const Text('保存'))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '在编辑器中选择历史记录时，使用此格式生成插入文本。',
            style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          Text(
            '可用占位符会自动替换为对应的内容，找不到的占位符保留原样。',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 20),

          // ---- 帖子 ----
          Text(
            '帖子格式',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          _buildPlaceholderHint('thread'),
          const SizedBox(height: 8),
          TextField(
            controller: _threadCtl,
            decoration: const InputDecoration(
              hintText: '{title}',
              border: OutlineInputBorder(),
              isDense: true,
              helperText: '最终插入为 [url=url]格式化文本[/url]',
              helperMaxLines: 2,
            ),
          ),

          const SizedBox(height: 24),

          // ---- 用户 ----
          Text(
            '用户格式',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          _buildPlaceholderHint('user'),
          const SizedBox(height: 8),
          TextField(
            controller: _userCtl,
            decoration: const InputDecoration(
              hintText: '{nickname}',
              border: OutlineInputBorder(),
              isDense: true,
              helperText: '最终插入为 [url=url]格式化文本[/url]',
              helperMaxLines: 2,
            ),
          ),

          const SizedBox(height: 32),

          // ---- 示例预览 ----
          Text(
            '预览',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _previewLine('帖子', _threadCtl.text, {
                  'title': '求助帖',
                  'author': '小明',
                  'time': '2024-01-01',
                }),
                const SizedBox(height: 8),
                _previewLine('用户', _userCtl.text, {
                  'nickname': '张三',
                  'uid': '123',
                }),
              ],
            ),
          ),

          const SizedBox(height: 32),
          const Divider(height: 1),
          const SizedBox(height: 16),

          // ==================== 列表标题格式 ====================
          Text(
            '列表标题格式',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            '浏览历史列表中每条记录的标题格式，修改后立刻生效。',
            style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          Text(
            '可用占位符会根据记录类型自动替换。{typeLabel} 自动显示为帖子/用户/我的帖子/回复。',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 20),

          // -- 帖子 --
          Text(
            '帖子格式',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          _buildTitlePlaceholderHint('thread'),
          const SizedBox(height: 8),
          TextField(
            controller: _titleThreadCtl,
            decoration: const InputDecoration(
              hintText: '{title}',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 4),
          _buildTitlePreview(cs, '帖子', _titleThreadCtl.text, {
            'title': '求助帖',
            'author': '小明',
            'tid': '123',
          }),

          const SizedBox(height: 20),

          // -- 用户 --
          Text(
            '用户格式',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          _buildTitlePlaceholderHint('user'),
          const SizedBox(height: 8),
          TextField(
            controller: _titleUserCtl,
            decoration: const InputDecoration(
              hintText: '{nickname}',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 4),
          _buildTitlePreview(cs, '用户', _titleUserCtl.text, {
            'nickname': '张三',
            'uid': '123',
          }),

          const SizedBox(height: 20),

          // -- 我的帖子 --
          Text(
            '我的帖子格式',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          _buildTitlePlaceholderHint('mythread'),
          const SizedBox(height: 8),
          TextField(
            controller: _titleMythreadCtl,
            decoration: const InputDecoration(
              hintText: '{typeLabel}(UID={uid}, 第{page}页)',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 4),
          _buildTitlePreview(cs, '我的帖子', _titleMythreadCtl.text, {
            'uid': '33',
            'page': '1',
            'typeLabel': '我的帖子',
          }),

          const SizedBox(height: 20),

          // -- 回复 --
          Text(
            '回复格式',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          _buildTitlePlaceholderHint('reply'),
          const SizedBox(height: 8),
          TextField(
            controller: _titleReplyCtl,
            decoration: const InputDecoration(
              hintText: '{typeLabel}(UID={uid}, 第{page}页)',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 4),
          _buildTitlePreview(cs, '回复', _titleReplyCtl.text, {
            'uid': '33',
            'page': '1',
            'typeLabel': '回复',
          }),
        ],
      ),
    );
  }

  Widget _buildPlaceholderHint(String type) {
    final cs = Theme.of(context).colorScheme;
    final placeholders = type == 'thread'
        ? ['{title}', '{author}', '{authorUid}', '{time}', '{tid}']
        : ['{nickname}', '{uid}'];
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: placeholders.map((p) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            p,
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTitlePlaceholderHint(String type) {
    final cs = Theme.of(context).colorScheme;
    final placeholders = switch (type) {
      'thread' => ['{title}', '{tid}', '{author}', '{authorUid}', '{page}'],
      'user' => ['{nickname}', '{uid}'],
      'mythread' || 'reply' => ['{uid}', '{page}', '{typeLabel}'],
      _ => ['{typeLabel}'],
    };
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: placeholders.map((p) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            p,
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTitlePreview(
    ColorScheme cs,
    String label,
    String format,
    Map<String, String> sample,
  ) {
    final result = _formatPlaceholders(format, sample);
    return Text(
      '预览: $result',
      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
    );
  }

  Widget _previewLine(String label, String format, Map<String, String> sample) {
    final cs = Theme.of(context).colorScheme;
    final result = _formatPlaceholders(format, sample);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label: "$format" → "$result"',
          style: const TextStyle(fontSize: 12, height: 1.4),
        ),
        Text(
          '最终: [url=https://...]$result[/url]',
          style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
        ),
      ],
    );
  }

  String _formatPlaceholders(String format, Map<String, String> info) {
    return format.replaceAllMapped(RegExp(r'\{(\w+)\}'), (m) {
      final key = m.group(1)!;
      return info[key]?.toString() ?? m.group(0)!;
    });
  }
}

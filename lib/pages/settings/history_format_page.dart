import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/settings_provider.dart';

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

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsProvider>();
    _threadCtl = TextEditingController(text: settings.historyFormatThread);
    _userCtl = TextEditingController(text: settings.historyFormatUser);
  }

  @override
  void dispose() {
    _threadCtl.dispose();
    _userCtl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final settings = context.read<SettingsProvider>();
    await settings.setHistoryFormatThread(_threadCtl.text.trim());
    await settings.setHistoryFormatUser(_userCtl.text.trim());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已保存'), duration: Duration(seconds: 1)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('插入格式'),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('保存'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '在编辑器中选择历史记录时，使用此格式生成插入文本。',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 4),
          Text(
            '可用占位符会自动替换为对应的内容，找不到的占位符保留原样。',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
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
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _previewLine(
                  '帖子',
                  _threadCtl.text,
                  {'title': '求助帖', 'author': '小明', 'time': '2024-01-01'},
                ),
                const SizedBox(height: 8),
                _previewLine(
                  '用户',
                  _userCtl.text,
                  {'nickname': '张三', 'uid': '123'},
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholderHint(String type) {
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
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            p,
            style: TextStyle(fontSize: 11, color: Colors.blue.shade700),
          ),
        );
      }).toList(),
    );
  }

  Widget _previewLine(String label, String format, Map<String, String> sample) {
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
          style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
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

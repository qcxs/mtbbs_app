import 'package:flutter/material.dart';
import 'package:mtbbs/config/toolbar_config.dart';
import 'package:mtbbs/models/managed_item.dart';

/// 工具栏「模板项」编辑弹窗。
///
/// 模板项 = 一段含 `${selectText}` 占位符的 BBCode 文本，用于包裹选中文字
/// （无选中时占位符为空）。用户可新增自己的模板，也可修改内置模板。
///
/// 返回编辑后的 [ManagedItem]；取消返回 null。
Future<ManagedItem?> showToolbarTemplateDialog(
  BuildContext context, {
  ManagedItem? initial,
}) {
  return showDialog<ManagedItem>(
    context: context,
    builder: (_) => _ToolbarTemplateDialog(initial: initial),
  );
}

class _ToolbarTemplateDialog extends StatefulWidget {
  final ManagedItem? initial;
  const _ToolbarTemplateDialog({this.initial});

  @override
  State<_ToolbarTemplateDialog> createState() => _ToolbarTemplateDialogState();
}

class _ToolbarTemplateDialogState extends State<_ToolbarTemplateDialog> {
  late final TextEditingController _nameCtl;
  late final TextEditingController _labelCtl;
  late final TextEditingController _templateCtl;
  String? _error;

  bool get _isCustom =>
      widget.initial == null || isCustomToolbarItem(widget.initial!);
  bool get _isEditing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _nameCtl = TextEditingController(text: initial?.name ?? '');
    _labelCtl = TextEditingController(
      text: initial?.data?['label']?.toString() ?? '',
    );
    _templateCtl = TextEditingController(
      text: initial == null ? '' : (toolbarTemplateOf(initial) ?? ''),
    );
  }

  @override
  void dispose() {
    _nameCtl.dispose();
    _labelCtl.dispose();
    _templateCtl.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameCtl.text.trim();
    final template = _templateCtl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = '请填写名称');
      return;
    }
    if (template.isEmpty) {
      setState(() => _error = '请填写模板内容');
      return;
    }

    final initial = widget.initial;
    final data = <String, dynamic>{
      ...?initial?.data,
      'template': template,
      'label': _labelCtl.text.trim(),
      // 新增项统一归入 custom 分组；编辑项沿用原分组
      if (initial == null) 'group': 'custom',
    };
    final item = ManagedItem(
      id: initial?.id ?? 'custom_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      visible: initial?.visible ?? true,
      data: data,
    );
    Navigator.of(context).pop(item);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(_isEditing ? '编辑工具栏项' : '新增工具栏项'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _nameCtl,
                enabled: _isCustom,
                decoration: const InputDecoration(
                  labelText: '名称',
                  helperText: '显示在 tooltip 与设置列表',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _labelCtl,
                decoration: const InputDecoration(
                  labelText: '按钮文字',
                  helperText: '工具栏按钮上显示的文字，如 H1；留空则用名称',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _templateCtl,
                maxLines: 4,
                minLines: 2,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                decoration: const InputDecoration(
                  labelText: '模板',
                  helperText: r'用 ${selectText} 代表选中文字（无选中时为空）',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '示例：[size=4][b]\${selectText}[/b][/size]',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(color: cs.error, fontSize: 12)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('保存')),
      ],
    );
  }
}

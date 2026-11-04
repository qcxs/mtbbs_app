import 'package:flutter/material.dart';
import 'package:mtbbs/widgets/bbcode/code_highlight_languages.dart';

/// 语言选择抽屉：搜索 + 块状排列（一行多个），常用语言自动前移。
class CodeLanguagePickerSheet extends StatefulWidget {
  /// 当前语言 key（空字符串 = 纯文本）
  final String current;
  final ValueChanged<String> onPick;

  const CodeLanguagePickerSheet({
    super.key,
    required this.current,
    required this.onPick,
  });

  @override
  State<CodeLanguagePickerSheet> createState() =>
      _CodeLanguagePickerSheetState();
}

class _CodeLanguagePickerSheetState extends State<CodeLanguagePickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  Map<String, int> _usage = const {};

  @override
  void initState() {
    super.initState();
    _loadUsage();
  }

  Future<void> _loadUsage() async {
    await CodeLanguageUsage.instance.loadIfNeeded();
    if (!mounted) return;
    setState(() => _usage = CodeLanguageUsage.instance.counts);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _pick(String key) {
    Navigator.of(context).pop();
    widget.onPick(key);
  }

  bool _matches(String key, String label, String query) {
    if (query.isEmpty) return true;
    return key.toLowerCase().contains(query) ||
        label.toLowerCase().contains(query);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final query = _searchController.text.trim().toLowerCase();
    final entries = <(String, String)>[
      if (_matches(kAutoLanguageKey, '自动检测', query))
        (kAutoLanguageKey, '自动检测'),
      if (_matches('plain', '纯文本', query)) (kPlainLanguageKey, '纯文本'),
      for (final key in orderedCodeLanguageKeys(_usage))
        if (_matches(key, codeLanguageLabel(key), query))
          (key, codeLanguageLabel(key)),
    ];

    return Padding(
      // isScrollControlled 下自行避让键盘
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: cs.outlineVariant)),
            ),
            child: Row(
              children: [
                const Icon(Icons.translate, size: 18),
                const SizedBox(width: 8),
                const Text(
                  '切换高亮语言',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 6),
                Text(
                  '${allCodeLanguageKeys.length} 种',
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: const Icon(Icons.close, size: 20),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
            child: TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                hintText: '搜索语言（中文名或英文名）',
                hintStyle: const TextStyle(fontSize: 12),
                prefixIcon: const Icon(Icons.search, size: 18),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear, size: 16),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {});
                        },
                      ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          Flexible(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
              children: [
                if (entries.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        '没有匹配的语言',
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final entry in entries)
                        _LanguageChip(
                          label: entry.$2,
                          selected: entry.$1 == widget.current,
                          onTap: () => _pick(entry.$1),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 语言选择器里的单个块（一行可排多个）
class _LanguageChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _LanguageChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? cs.primary.withValues(alpha: 0.12)
              : cs.surfaceContainerHighest.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? cs.primary : cs.outlineVariant,
            width: selected ? 1 : 0.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            height: 1.2,
            color: selected ? cs.primary : cs.onSurface,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

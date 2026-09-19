import 'package:flutter/material.dart';
import 'package:mtbbs/models/managed_item.dart';
import 'package:mtbbs/providers/settings_provider.dart';
import 'package:provider/provider.dart';

/// 首页区块面板 — 调顺序、显隐、默认展开的唯一入口。
///
/// 首页里当场折叠与这里改的"默认"是同一份持久化状态，
/// 所以面板里的值始终就是首页当前的表现。
Future<void> showHomeSectionsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 560, maxHeight: 560),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
    ),
    builder: (_) => const _HomeSectionsSheet(),
  );
}

class _HomeSectionsSheet extends StatelessWidget {
  const _HomeSectionsSheet();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final settings = context.watch<SettingsProvider>();
    final sections = settings.homeSections;

    return Column(
      children: [
        // 拖拽手柄
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Center(
            child: Container(
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                color: cs.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  '首页区块',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                tooltip: '关闭',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: cs.outlineVariant),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            '拖动调整顺序；「默认展开」决定进入首页时是否展开；'
            '关闭显示后该区块不再出现，可随时重新开启。',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
        ),
        Expanded(
          child: ReorderableListView.builder(
            itemCount: sections.length,
            onReorderItem: settings.moveHomeSection,
            buildDefaultDragHandles: false,
            itemBuilder: (_, i) => _sectionTile(context, settings, sections[i], i),
          ),
        ),
      ],
    );
  }

  Widget _sectionTile(
    BuildContext context,
    SettingsProvider settings,
    ManagedItem item,
    int index,
  ) {
    final cs = Theme.of(context).colorScheme;
    final expanded = SettingsProvider.homeSectionExpanded(item);

    return ListTile(
      key: ValueKey(item.id),
      leading: ReorderableDragStartListener(
        index: index,
        child: const Padding(
          padding: EdgeInsets.all(2),
          child: Icon(Icons.drag_handle, size: 18),
        ),
      ),
      title: Text(
        item.name,
        style: TextStyle(color: item.visible ? null : cs.onSurfaceVariant),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '默认展开',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
          const SizedBox(width: 4),
          Switch(
            value: expanded,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            // 隐藏的区块不参与展开行为，避免设置出无意义的状态
            onChanged: item.visible
                ? (v) => settings.setHomeSectionExpanded(item.id, v)
                : null,
          ),
          IconButton(
            icon: Icon(
              item.visible ? Icons.visibility : Icons.visibility_off,
              size: 18,
              color: cs.onSurfaceVariant,
            ),
            tooltip: item.visible ? '隐藏' : '显示',
            onPressed: () => settings.toggleHomeSectionVisibility(item.id),
          ),
        ],
      ),
      visualDensity: VisualDensity.compact,
    );
  }
}

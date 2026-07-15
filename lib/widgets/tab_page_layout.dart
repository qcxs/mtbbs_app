import 'package:flutter/material.dart';

/// Tab 条 + PageView 布局组件
///
/// 供 GuidePage / CommunityPage 等需要多标签页 + 左右滑动切换的页面复用。
/// 职责：Tab 条（可水平滚动 + 选中高亮）、PageView 联动、可选右侧按钮。
///
/// 使用示例：
/// ```dart
/// TabPageLayout(
///   tabs: [TabInfo('最新发表', 'newthread')],
///   tabTuneIcon: Icons.tune,
///   onTabTune: () => _showOrderDialog(),
///   buildPage: (key) => ThreadGrid(controller: _ctrlMap[key]),
/// )
/// ```
class TabPageLayout extends StatefulWidget {
  final List<TabInfo> tabs;
  final String initialKey;
  final String Function(String key)? labelOf;
  final Widget Function(String key, int index, bool isActive) buildPage;
  final IconData? tabTuneIcon;
  final VoidCallback? onTabTune;
  final void Function(String key)? onFocusChanged;

  const TabPageLayout({
    super.key,
    required this.tabs,
    required this.initialKey,
    required this.buildPage,
    this.labelOf,
    this.tabTuneIcon,
    this.onTabTune,
    this.onFocusChanged,
  });

  @override
  State<TabPageLayout> createState() => _TabPageLayoutState();
}

class _TabPageLayoutState extends State<TabPageLayout> {
  final _pageController = PageController();
  String _focusKey = '';
  int _tabLen = 0;

  @override
  void initState() {
    super.initState();
    _focusKey = _tabs.isNotEmpty ? widget.initialKey : '';
    _tabLen = _tabs.length;
    if (_focusKey.isNotEmpty) {
      widget.onFocusChanged?.call(_focusKey);
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  List<TabInfo> get _tabs => widget.tabs;

  @override
  Widget build(BuildContext context) {
    final tabs = _tabs;
    final focusIdx = tabs.indexWhere((t) => t.key == _focusKey);

    // tabs 数量变化时修正 _focusKey
    if (tabs.length != _tabLen) {
      _tabLen = tabs.length;
      if (!tabs.any((t) => t.key == _focusKey)) {
        _focusKey = tabs.isNotEmpty ? tabs.first.key : '';
      }
      // 下一帧跳转
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_pageController.hasClients) {
          final i = tabs.indexWhere((t) => t.key == _focusKey);
          if (i >= 0) _pageController.jumpToPage(i);
        }
      });
    }

    return Column(
      children: [
        // === Tab 条 ===
        if (tabs.isNotEmpty)
          SizedBox(
            height: 38,
            child: Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      children: tabs.asMap().entries.map((e) {
                        final i = e.key;
                        final t = e.value;
                        final label = widget.labelOf?.call(t.key) ?? t.label;
                        return _buildTabChip(label, i == focusIdx, () {
                          setState(() {
                            _focusKey = t.key;
                            widget.onFocusChanged?.call(t.key);
                          });
                          _pageController.jumpToPage(i);
                        });
                      }).toList(),
                    ),
                  ),
                ),
                if (widget.onTabTune != null)
                  IconButton(
                    icon: Icon(
                      widget.tabTuneIcon ?? Icons.tune,
                      size: 20,
                      color: Colors.grey.shade600,
                    ),
                    onPressed: widget.onTabTune,
                  ),
              ],
            ),
          ),
        // === PageView ===
        Expanded(
          child: tabs.isEmpty
              ? const Center(child: Text('暂无可用标签'))
              : PageView(
                  key: ValueKey(tabs.map((t) => t.key).join(',')),
                  controller: _pageController,
                  onPageChanged: (i) {
                    if (i >= 0 && i < tabs.length) {
                      final key = tabs[i].key;
                      setState(() => _focusKey = key);
                      widget.onFocusChanged?.call(key);
                    }
                  },
                  children: tabs.asMap().entries.map((e) {
                    return widget.buildPage(
                      e.value.key,
                      e.key,
                      e.value.key == _focusKey,
                    );
                  }).toList(),
                ),
        ),
      ],
    );
  }

  Widget _buildTabChip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: selected
              ? Theme.of(context).colorScheme.primary.withOpacity(0.1)
              : null,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Colors.grey.shade600,
          ),
        ),
      ),
    );
  }
}

/// Tab 信息
class TabInfo {
  final String label;
  final String key;
  const TabInfo(this.label, this.key);
}

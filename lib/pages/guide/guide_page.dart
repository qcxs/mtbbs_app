import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:mtbbs/api/forum/guide/export.dart' as guide_api;
import 'package:mtbbs/services/api_service.dart';
import 'package:mtbbs/providers/settings_provider.dart';
import 'package:mtbbs/core/shortcut_helper.dart';
import 'package:mtbbs/auth/providers/auth_provider.dart';
import 'package:mtbbs/auth/widgets/login_sheet.dart';
import 'package:mtbbs/models/managed_item.dart';
import 'package:mtbbs/widgets/managed_list_dialog.dart';
import '../../controllers/thread_list_controller.dart';
import '../../widgets/thread_grid.dart';

/// 导读首页
///
/// 由 _AppShell 提供 Scaffold 外壳，本组件只返回 Column(tab条 + PageView)。
class GuidePage extends StatefulWidget {
  const GuidePage({super.key});

  @override
  State<GuidePage> createState() => _GuidePageState();
}

class _GuidePageState extends State<GuidePage> {
  final _pageController = PageController();
  String _focusView = 'newthread';
  static final Map<String, ThreadListController> _ctrlMap = {};

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  List<String> _views(bool loggedIn) {
    final order = List<String>.from(context.read<SettingsProvider>().tabOrder);
    if (loggedIn && !order.contains('my')) order.add('my');
    return order;
  }

  void _ensureCtrls(Iterable<String> views) {
    for (final v in views) {
      _ctrlMap.putIfAbsent(
        v,
        () => ThreadListController(
          fetchFn: ({required int page}) =>
              guide_api.getThreadList(ApiService().dio, view: v, page: page),
        ),
      );
    }
  }

  void _showOrderDialog() {
    final settings = context.read<SettingsProvider>();
    const all = ['newthread', 'hot', 'new', 'digest', 'sofa'];
    final items = all
        .map(
          (v) => ManagedItem(
            id: v,
            name: SettingsProvider.tabLabels[v] ?? v,
            visible: settings.tabOrder.contains(v),
          ),
        )
        .toList();

    showManagedListDialog(
      context: context,
      title: 'Tab 排序',
      items: items,
      allowAdd: false,
      allowDelete: false,
      allowEdit: false,
      allowReorder: true,
      allowToggleVisibility: true,
      onReorder: (from, to) => settings.moveTab(from, to),
      onToggleVisibility: (id) => settings.toggleTab(id),
      emptyHint: '暂无 Tab',
    ).then((_) {
      if (!context.mounted) return;
      final views = _views(context.read<AuthProvider>().isLoggedIn);
      if (!views.contains(_focusView)) {
        setState(
          () => _focusView = views.isNotEmpty ? views.first : 'newthread',
        );
      }
    });
  }

  void _selectView(String view) {
    final views = _views(context.read<AuthProvider>().isLoggedIn);
    final i = views.indexOf(view);
    if (i < 0 || view == _focusView) return;
    setState(() => _focusView = view);
    _pageController.jumpToPage(i);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final auth = context.watch<AuthProvider>();
    final settings = context.watch<SettingsProvider>();
    final views = _views(auth.isLoggedIn);
    _ensureCtrls(views);
    if (!views.contains(_focusView))
      _focusView = views.isNotEmpty ? views.first : '';
    final focusIdx = views.indexOf(_focusView);
    final hasTabs = views.isNotEmpty;

    final shortcutsMap = <ShortcutActivator, Intent>{};
    final actionsList = <Type, Action<Intent>>{};

    final _refreshKey = ShortcutHelper.parse(settings.shortcut('refresh'));
    if (_refreshKey != null) {
      shortcutsMap[_refreshKey] = RefreshIntent();
      actionsList[RefreshIntent] = CallbackAction<RefreshIntent>(
        onInvoke: (_) {
          _ctrlMap[_focusView]?.refresh();
          return null;
        },
      );
    }
    if (views.isNotEmpty) {
      final nextKey = ShortcutHelper.parse(settings.shortcut('switchTabNext'));
      if (nextKey != null) {
        shortcutsMap[nextKey] = SwitchTabNextIntent();
        actionsList[SwitchTabNextIntent] = CallbackAction<SwitchTabNextIntent>(
          onInvoke: (_) {
            final i = views.indexOf(_focusView);
            _selectView(views[(i + 1) % views.length]);
            return null;
          },
        );
      }
    }
    if (views.length > 1) {
      final prevKey = ShortcutHelper.parse(settings.shortcut('switchTabPrev'));
      if (prevKey != null) {
        shortcutsMap[prevKey] = SwitchTabPrevIntent();
        actionsList[SwitchTabPrevIntent] = CallbackAction<SwitchTabPrevIntent>(
          onInvoke: (_) {
            final i = views.indexOf(_focusView);
            _selectView(views[(i - 1 + views.length) % views.length]);
            return null;
          },
        );
      }
    }

    return Actions(
      actions: actionsList,
      child: Shortcuts(
        shortcuts: shortcutsMap,
        child: Focus(
          autofocus: true,
          child: Column(
            children: [
              // === Tab 条 ===
              if (hasTabs)
                SizedBox(
                  height: 38,
                  child: Row(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Row(
                            children: views
                                .asMap()
                                .entries
                                .map(
                                  (e) => _chip(
                                    SettingsProvider.tabLabels[e.value] ??
                                        e.value,
                                    e.key == focusIdx,
                                    () => _selectView(e.value),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.tune,
                          size: 20,
                          color: cs.onSurfaceVariant,
                        ),
                        tooltip: 'Tab 排序',
                        onPressed: _showOrderDialog,
                      ),
                    ],
                  ),
                ),
              // === 内容 ===
              Expanded(
                child: !hasTabs
                    ? const Center(child: Text('暂无可用标签'))
                    : PageView(
                        key: ValueKey(views.join(',')),
                        controller: _pageController,
                        onPageChanged: (i) {
                          if (i >= 0 && i < views.length)
                            setState(() => _focusView = views[i]);
                        },
                        children: views.map((v) {
                          final ctrl = _ctrlMap[v];
                          if (ctrl == null) return const SizedBox.shrink();
                          if (v == 'my' && !auth.isLoggedIn)
                            return _buildLoginPrompt();
                          return ThreadGrid(
                            controller: ctrl,
                            visible: v == _focusView,
                          );
                        }).toList(),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: selected ? cs.onSurfaceVariant.withOpacity(0.1) : null,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            color: selected ? cs.onSurfaceVariant : cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _buildLoginPrompt() {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 48, color: cs.outlineVariant),
            const SizedBox(height: 12),
            Text(
              '登录后可查看自己的帖子',
              style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => showLoginSheet(context),
              icon: const Icon(Icons.login, size: 16),
              label: const Text('立即登录'),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mtbbs/config/site_config.dart';
import 'package:mtbbs/core/app/site_store.dart';
import 'package:mtbbs/providers/settings_provider.dart';
import 'package:mtbbs/auth/providers/auth_provider.dart';
import 'package:mtbbs/core/app/app_orchestrator.dart';
import 'package:mtbbs/widgets/common/toast_utils.dart';

/// 站点管理 — 切换、添加、删除站点
class SiteManagement {
  static void showPicker(BuildContext context, SettingsProvider settings) {
    final cs = Theme.of(context).colorScheme;
    final current = settings.currentSiteIndex;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          constraints: const BoxConstraints(maxWidth: 400),
          title: Row(
            children: [
              const Expanded(child: Text('切换站点')),
              GestureDetector(
                onTap: () => _confirmReset(context, settings, setD),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  child: Icon(
                    Icons.restart_alt,
                    size: 18,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () {
                  Navigator.of(ctx).pop();
                  showAddDialog(context, settings);
                },
                child: Container(
                  padding: const EdgeInsets.all(6),
                  child: Icon(Icons.add, size: 18, color: cs.onSurfaceVariant),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: List.generate(SiteStore.instance.sites.length, (i) {
                final site = SiteStore.instance.sites[i];
                final subtitle = StringBuffer(site.baseUrl);
                if (site.cdn != null && site.cdn!.isNotEmpty) {
                  subtitle.write('\nCDN: ${site.cdn}');
                }
                if (site.avatarTemplate != null &&
                    site.avatarTemplate!.isNotEmpty) {
                  subtitle.write('\n头像: 自定义模板');
                }
                return RadioListTile<int>(
                  title: Text(site.name),
                  subtitle: Text(
                    subtitle.toString(),
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                  ),
                  value: i,
                  groupValue: current,
                  onChanged: (v) async {
                    if (v == null) return;
                    final orchestrator = AppOrchestrator(
                      settings: settings,
                      auth: context.read<AuthProvider>(),
                    );
                    await orchestrator.switchSite(v);
                    if (ctx.mounted) Navigator.of(ctx).pop();
                    if (context.mounted) {
                      showToast(
                        '已切换到 ${site.name}',
                        duration: const Duration(seconds: 1),
                      );
                    }
                  },
                  secondary: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(
                          Icons.edit_outlined,
                          size: 18,
                          color: cs.onSurfaceVariant,
                        ),
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          _editSite(context, settings, i);
                        },
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.delete_outline,
                          size: 18,
                          color: cs.error,
                        ),
                        onPressed: () =>
                            _deleteSite(context, settings, site.name, i),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('关闭'),
            ),
          ],
        ),
      ),
    );
  }

  /// 重置站点配置确认框：从 defaults.json 恢复内置站点配置
  static void _confirmReset(
    BuildContext context,
    SettingsProvider settings,
    void Function(VoidCallback) setD,
  ) {
    showDialog(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('重置站点配置'),
        content: const Text(
          '将把内置站点（MT论坛、吾爱破解等）的配置恢复为默认，'
          '并补回缺失的内置站点。自定义添加的站点不受影响。确定继续吗？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(dctx).pop();
              final count = await settings.restoreDefaultSites();
              if (context.mounted) {
                showToast('已重置 $count 个站点配置');
                setD(() {});
              }
            },
            child: const Text('重置'),
          ),
        ],
      ),
    );
  }

  static void _deleteSite(
    BuildContext context,
    SettingsProvider settings,
    String name,
    int index,
  ) {
    if (SiteStore.instance.sites.length <= 1) {
      showToast('至少保留一个站点');
      return;
    }
    final cs = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除站点'),
        content: Text('确定要删除「$name」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: cs.error),
            onPressed: () async {
              final wasCurrent = index == settings.currentSiteIndex;
              await settings.deleteSite(index);
              if (ctx.mounted) Navigator.of(ctx).pop();
              // 关闭父级站点选择器对话框
              if (context.mounted) Navigator.of(context).pop();
              if (wasCurrent && context.mounted) {
                await context.read<AuthProvider>().onSiteChanged();
              }
              if (context.mounted) {
                showToast('已删除');
              }
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  static void _editSite(
    BuildContext context,
    SettingsProvider settings,
    int index,
  ) {
    final site = SiteStore.instance.sites[index];
    showDialog(
      context: context,
      builder: (_) => _EditSiteDialog(
        settings: settings,
        index: index,
        site: site,
      ),
    );
  }

  static void showAddDialog(BuildContext context, SettingsProvider settings) {
    showDialog(
      context: context,
      builder: (_) => _AddSiteDialog(settings: settings),
    );
  }
}

/// 编辑站点弹窗内容
///
/// 控制器由本 State 持有、随弹窗子树卸载才释放：showDialog 返回的 Future 在
/// pop 时即完成，此时弹窗仍在退场动画中、子树仍会重建（保存站点会触发
/// notifyListeners → MaterialApp 重建），在 pop 前后提前 dispose 会抛
/// 「A TextEditingController was used after being disposed」；完全不 dispose
/// 则控制器泄漏。
class _EditSiteDialog extends StatefulWidget {
  const _EditSiteDialog({
    required this.settings,
    required this.index,
    required this.site,
  });

  final SettingsProvider settings;
  final int index;
  final Site site;

  @override
  State<_EditSiteDialog> createState() => _EditSiteDialogState();
}

class _EditSiteDialogState extends State<_EditSiteDialog> {
  late final TextEditingController _nameCtl = TextEditingController(
    text: widget.site.name,
  );
  late final TextEditingController _urlCtl = TextEditingController(
    text: widget.site.baseUrl,
  );
  late final TextEditingController _cdnCtl = TextEditingController(
    text: widget.site.cdn ?? '',
  );
  late final TextEditingController _loginPathCtl = TextEditingController(
    text: widget.site.loginPagePath,
  );
  late final TextEditingController _avatarCtl = TextEditingController(
    text: widget.site.avatarTemplate ?? '',
  );

  @override
  void dispose() {
    _nameCtl.dispose();
    _urlCtl.dispose();
    _cdnCtl.dispose();
    _loginPathCtl.dispose();
    _avatarCtl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtl.text.trim();
    var url = _urlCtl.text.trim();
    final cdnText = _cdnCtl.text.trim();
    final loginPath = _loginPathCtl.text.trim();
    final avatarTemplate = _avatarCtl.text.trim();
    if (name.isEmpty || url.isEmpty) return;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }
    final cdn = cdnText.isNotEmpty ? cdnText : null;
    await widget.settings.updateSite(
      widget.index,
      Site(
        name: name,
        baseUrl: url,
        cdn: cdn,
        loginPagePath: loginPath,
        forums: widget.site.forums,
        defaultForumOrder: widget.site.defaultForumOrder,
        userAgent: widget.site.userAgent,
        avatarTemplate: avatarTemplate.isEmpty ? null : avatarTemplate,
      ),
    );
    if (!mounted) return;
    Navigator.of(context).pop();
    showToast('已更新「$name」', duration: const Duration(seconds: 1));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('编辑站点'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameCtl,
              decoration: const InputDecoration(
                labelText: '站点名称',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _urlCtl,
              decoration: const InputDecoration(
                labelText: '站点地址',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _cdnCtl,
              decoration: const InputDecoration(
                labelText: 'CDN 地址（可选）',
                hintText: '留空则使用站点地址',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _loginPathCtl,
              decoration: const InputDecoration(
                labelText: '登录页路径（可选）',
                hintText: '留空使用默认 /member.php?mod=logging&action=login',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _avatarCtl,
              decoration: const InputDecoration(
                labelText: '头像 URL 模板（可选）',
                hintText:
                    '留空使用默认 API 方案，例如：\nhttps://avatar.xxx.com/data/avatar/{dir}/{tail}_avatar_{size}.jpg',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              maxLines: 2,
              keyboardType: TextInputType.url,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _save, child: const Text('保存')),
      ],
    );
  }
}

/// 添加站点弹窗内容
///
/// 控制器由本 State 持有，理由同 [_EditSiteDialog]。
class _AddSiteDialog extends StatefulWidget {
  const _AddSiteDialog({required this.settings});

  final SettingsProvider settings;

  @override
  State<_AddSiteDialog> createState() => _AddSiteDialogState();
}

class _AddSiteDialogState extends State<_AddSiteDialog> {
  final _nameCtl = TextEditingController();
  final _urlCtl = TextEditingController();

  @override
  void dispose() {
    _nameCtl.dispose();
    _urlCtl.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final name = _nameCtl.text.trim();
    var url = _urlCtl.text.trim();
    if (name.isEmpty || url.isEmpty) return;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }
    await widget.settings.addSite(
      Site(
        name: name,
        baseUrl: url,
        loginPagePath: '/member.php?mod=logging&action=login',
        forums: {},
        defaultForumOrder: [],
        userAgent: '',
      ),
    );
    if (!mounted) return;
    Navigator.of(context).pop();
    showToast('已添加「$name」');
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('添加站点'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameCtl,
            decoration: const InputDecoration(
              labelText: '站点名称',
              hintText: '例如：我的论坛',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            autofocus: true,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _urlCtl,
            decoration: const InputDecoration(
              labelText: '站点地址',
              hintText: 'https://example.com',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            keyboardType: TextInputType.url,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _add, child: const Text('添加')),
      ],
    );
  }
}

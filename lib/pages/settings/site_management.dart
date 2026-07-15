import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../config/site_config.dart';
import '../../../providers/settings_provider.dart';
import '../../../auth/providers/auth_provider.dart';

/// 站点管理 — 切换、添加、删除站点
class SiteManagement {
  static void showPicker(BuildContext context, SettingsProvider settings) {
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
                onTap: () {
                  Navigator.of(ctx).pop();
                  showAddDialog(context, settings);
                },
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(Icons.add, size: 18, color: Colors.blue.shade600),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: List.generate(SiteConfig.sites.length, (i) {
                final site = SiteConfig.sites[i];
                final subtitle = StringBuffer(site.baseUrl);
                if (site.cdn != null && site.cdn!.isNotEmpty) {
                  subtitle.write('\nCDN: ${site.cdn}');
                }
                return RadioListTile<int>(
                  title: Text(site.name),
                  subtitle: Text(
                    subtitle.toString(),
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                  ),
                  value: i,
                  groupValue: current,
                  onChanged: (v) async {
                    if (v == null) return;
                    context.read<AuthProvider>().saveCurrentSiteState();
                    await settings.switchSite(v);
                    SiteConfig.switchTo(v);
                    await settings.reloadSiteConfig();
                    if (ctx.mounted) Navigator.of(ctx).pop();
                    if (context.mounted) {
                      await context.read<AuthProvider>().onSiteChanged();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('已切换到 ${site.name}'),
                          duration: const Duration(seconds: 1),
                        ),
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
                          color: Colors.grey.shade500,
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
                          color: Colors.red.shade300,
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

  static void _deleteSite(
    BuildContext context,
    SettingsProvider settings,
    String name,
    int index,
  ) {
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
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
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
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('已删除')));
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
    final site = SiteConfig.sites[index];
    final nameCtl = TextEditingController(text: site.name);
    final urlCtl = TextEditingController(text: site.baseUrl);
    final cdnCtl = TextEditingController(text: site.cdn ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑站点'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtl,
              decoration: const InputDecoration(
                labelText: '站点名称',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: urlCtl,
              decoration: const InputDecoration(
                labelText: '站点地址',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: cdnCtl,
              decoration: const InputDecoration(
                labelText: 'CDN 地址（可选）',
                hintText: '留空则使用站点地址',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              keyboardType: TextInputType.url,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final name = nameCtl.text.trim();
              var url = urlCtl.text.trim();
              final cdnText = cdnCtl.text.trim();
              if (name.isEmpty || url.isEmpty) return;
              if (!url.startsWith('http://') && !url.startsWith('https://')) {
                url = 'https://$url';
              }
              final cdn = cdnText.isNotEmpty ? cdnText : null;
              await settings.updateSite(
                index,
                Site(
                  name: name,
                  baseUrl: url,
                  cdn: cdn,
                  loginPagePath: site.loginPagePath,
                  forums: site.forums,
                  defaultForumOrder: site.defaultForumOrder,
                ),
              );
              if (ctx.mounted) Navigator.of(ctx).pop();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('已更新「$name」'),
                    duration: const Duration(seconds: 1),
                  ),
                );
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  static void showAddDialog(BuildContext context, SettingsProvider settings) {
    final nameCtl = TextEditingController();
    final urlCtl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加站点'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtl,
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
              controller: urlCtl,
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
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final name = nameCtl.text.trim();
              var url = urlCtl.text.trim();
              if (name.isEmpty || url.isEmpty) return;
              if (!url.startsWith('http://') && !url.startsWith('https://')) {
                url = 'https://$url';
              }
              await settings.addSite(
                Site(
                  name: name,
                  baseUrl: url,
                  loginPagePath: '/member.php?mod=logging&action=login',
                  forums: {},
                  defaultForumOrder: [],
                ),
              );
              if (ctx.mounted) Navigator.of(ctx).pop();
              if (context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('已添加「$name」')));
              }
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
  }
}

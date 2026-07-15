import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../../auth/pages/web_login_page.dart';
import '../../../auth/widgets/login_sheet.dart' show showLoginSheet;
import '../../../widgets/user_avatar.dart';
import '../../../core/clipboard_helper.dart';

/// 用户管理弹窗 — 账号切换、登录、导出
class UserManagementDialog extends StatelessWidget {
  const UserManagementDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthProvider>();

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 40),
      constraints: const BoxConstraints(maxWidth: 420),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题栏：用户管理 + [添加] [关闭X]
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      '用户管理',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  // 添加账号（直接打开 WebView 登录页，Cookie 功能已集成在内）
                  GestureDetector(
                    onTap: () async {
                      Navigator.of(context).pop();
                      final ok = await Navigator.of(context).push<bool>(
                        MaterialPageRoute(builder: (_) => const WebLoginPage()),
                      );
                      if (ok != true || !context.mounted) return;
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(const SnackBar(content: Text('登录成功')));
                    },
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(
                        Icons.add,
                        size: 18,
                        color: Colors.blue.shade600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
            const Divider(height: 20),

            // 当前账号
            Consumer<AuthProvider>(
              builder: (_, auth, __) {
                final displayName = auth.username.isNotEmpty
                    ? auth.username
                    : '游客';
                final displayUid = auth.uid.isNotEmpty
                    ? 'UID: ${auth.uid}'
                    : '未登录';

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      UserAvatar(
                        uid: auth.uid,
                        nickname: displayName,
                        radius: 22,
                        showBorder: true,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              displayName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                            ),
                            Text(
                              displayUid,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (auth.isLoggedIn)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            GestureDetector(
                              onTap: () async {
                                await auth.refreshCurrentUserInfo();
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('用户信息已刷新')),
                                  );
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Icon(
                                  Icons.refresh,
                                  size: 16,
                                  color: Colors.blue.shade600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            TextButton(
                              onPressed: () => _confirmLogout(context, auth),
                              child: const Text(
                                '退出',
                                style: TextStyle(color: Colors.red),
                              ),
                            ),
                          ],
                        )
                      else
                        TextButton(
                          onPressed: () {
                            Navigator.of(context).pop(); // 先关用户管理弹窗
                            showLoginSheet(context);
                          },
                          child: const Text('登录'),
                        ),
                    ],
                  ),
                );
              },
            ),
            const Divider(height: 16),

            // 切换账号（含游客）
            Consumer<AuthProvider>(
              builder: (_, auth, __) {
                if (auth.accounts.length <= 1) return const SizedBox.shrink();
                return Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '切换账号',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ),
                      ),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 200),
                        child: ListView(
                          shrinkWrap: true,
                          children: [
                            for (int i = 0; i < auth.accounts.length; i++)
                              if (i != auth.activeIndex)
                                ListTile(
                                  leading: UserAvatar(
                                    uid: auth.accounts[i].uid,
                                    nickname: auth.accounts[i].username,
                                    radius: 18,
                                  ),
                                  title: Text(
                                    auth.accounts[i].uid == '0'
                                        ? '游客'
                                        : auth.accounts[i].username,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: auth.accounts[i].uid == '0'
                                          ? Colors.grey
                                          : null,
                                    ),
                                  ),
                                  dense: true,
                                  onTap: () async {
                                    Navigator.of(context).pop();
                                    await auth.switchTo(i);
                                  },
                                ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                    ],
                  ),
                );
              },
            ),

            // 底部：左(导入/导出) 右(关闭)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: () => _import(context, auth),
                    icon: const Icon(Icons.download, size: 16),
                    label: const Text('导入'),
                  ),
                  const SizedBox(width: 4),
                  TextButton.icon(
                    onPressed: () => _export(context, auth),
                    icon: const Icon(Icons.upload, size: 16),
                    label: const Text('导出'),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('关闭'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _export(BuildContext context, AuthProvider auth) {
    Navigator.of(context).pop();
    final jsonStr = auth.exportAccounts();
    if (jsonStr == '[]') {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('没有可导出的账号')));
      return;
    }
    Clipboard.setData(ClipboardData(text: jsonStr));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已导出到剪切板')));
  }

  void _import(BuildContext context, AuthProvider auth) {
    Navigator.of(context).pop(); // 关闭用户管理弹窗
    ClipboardHelper.read().then((text) {
      if (text == null || text.trim().isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('剪切板为空')));
        return;
      }
      _showImportPreview(context, auth, text.trim());
    });
  }

  /// 导入预览弹窗 — 可编辑、校验 JSON、二次确认
  void _showImportPreview(
    BuildContext context,
    AuthProvider auth,
    String initialText,
  ) {
    final ctl = TextEditingController(text: initialText);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('导入账号'),
        constraints: const BoxConstraints(maxWidth: 420),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '请确认或编辑账号 JSON 数据：',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: ctl,
              maxLines: 6,
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final raw = ctl.text.trim();
              // 校验 JSON
              try {
                final parsed = jsonDecode(raw);
                if (parsed is! List) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('JSON 格式错误：应为数组')),
                  );
                  return;
                }
                for (final item in parsed) {
                  if (item is! Map ||
                      !item.containsKey('username') ||
                      !item.containsKey('uid')) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(
                        content: Text('JSON 格式错误：缺少 username 或 uid'),
                      ),
                    );
                    return;
                  }
                }
              } catch (e) {
                ScaffoldMessenger.of(
                  ctx,
                ).showSnackBar(SnackBar(content: Text('JSON 解析失败: $e')));
                return;
              }
              Navigator.of(ctx).pop();
              final result = auth.importAccounts(raw);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      result['success'] == true
                          ? '成功导入'
                          : '导入失败: ${result['message']}',
                    ),
                  ),
                );
              }
            },
            child: const Text('导入'),
          ),
        ],
      ),
    );
  }

  void _confirmLogout(BuildContext context, AuthProvider auth) {
    Navigator.of(context).pop();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出登录'),
        content: Text('确定退出 ${auth.username} 吗？\n将清除该账号的登录状态。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              auth.logout();
              Navigator.of(ctx).pop();
            },
            child: const Text('退出'),
          ),
        ],
      ),
    );
  }
}

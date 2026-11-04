import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mtbbs/auth/providers/auth_provider.dart';
import 'package:mtbbs/auth/pages/web_login_page.dart';
import 'package:mtbbs/auth/widgets/login_sheet.dart' show showLoginSheet;
import 'package:mtbbs/widgets/common/user_avatar.dart';
import 'package:mtbbs/core/utils/clipboard_helper.dart';
import 'package:mtbbs/widgets/common/toast_utils.dart';
import 'package:mtbbs/widgets/dialog/confirm_dialog.dart';

/// 用户管理弹窗 — 账号切换、登录、导出
class UserManagementDialog extends StatelessWidget {
  const UserManagementDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthProvider>();
    final cs = Theme.of(context).colorScheme;

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
                  IconButton(
                    icon: const Icon(Icons.add, size: 18),
                    tooltip: '添加账号',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () async {
                      Navigator.of(context).pop();
                      final ok = await Navigator.of(context).push<bool>(
                        MaterialPageRoute(builder: (_) => const WebLoginPage()),
                      );
                      if (ok != true || !context.mounted) return;
                      showToast('登录成功');
                    },
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
                final expiredTag = auth.isExpired ? '（已过期）' : '';

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      UserAvatar(
                        uid: auth.uid,
                        nickname: displayName,
                        radius: 22,
                        showBorder: true,
                        tapAction: AvatarTapAction.none,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$displayName$expiredTag',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                            ),
                            Text(
                              displayUid,
                              style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (auth.isLoggedIn)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.refresh, size: 16),
                              tooltip: '刷新用户信息',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () async {
                                await auth.refreshCurrentUserInfo();
                                if (context.mounted) {
                                  showToast('用户信息已刷新');
                                }
                              },
                            ),
                            const SizedBox(width: 4),
                            TextButton(
                              onPressed: () => _confirmLogout(context, auth),
                              child: Text(
                                '退出',
                                style: TextStyle(color: cs.error),
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
                                    tapAction: AvatarTapAction.none,
                                  ),
                                  title: Text(
                                    auth.accounts[i].uid == '0'
                                        ? '游客'
                                        : auth.accounts[i].expired
                                        ? '${auth.accounts[i].username}（已过期）'
                                        : auth.accounts[i].username,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color:
                                          auth.accounts[i].uid == '0' ||
                                              auth.accounts[i].expired
                                          ? cs.onSurfaceVariant
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

            const Divider(height: 1),

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

  Future<void> _export(BuildContext context, AuthProvider auth) async {
    Navigator.of(context).pop();
    final jsonStr = auth.exportAccounts();
    if (jsonStr == '[]') {
      showToast('没有可导出的账号');
      return;
    }
    final ok = await ClipboardHelper.write(jsonStr);
    showToast(ok ? '已导出到剪切板' : '复制到剪切板失败');
  }

  Future<void> _import(BuildContext context, AuthProvider auth) async {
    // 先取 Navigator 再 pop：弹窗自身 context 在 pop 后处于退场动画中，
    // 用它继续 showDialog 属于"在已销毁的子树下找祖先"，改用 Navigator 的 context。
    final navigator = Navigator.of(context, rootNavigator: true);
    navigator.pop(); // 关闭用户管理弹窗
    final text = await ClipboardHelper.read();
    final trimmed = text?.trim() ?? '';
    // 降级：读取失败或剪切板为空时仍打开导入弹窗，让用户手动粘贴，
    // 而不是只提示「剪切板为空」后把流程结束掉。
    _showImportPreview(
      navigator.context,
      auth,
      trimmed,
      clipboardEmpty: trimmed.isEmpty,
    );
  }

  /// 导入预览弹窗 — 可编辑、校验 JSON、二次确认
  void _showImportPreview(
    BuildContext context,
    AuthProvider auth,
    String initialText, {
    bool clipboardEmpty = false,
  }) {
    showDialog(
      context: context,
      builder: (_) => _ImportAccountsDialog(
        initialText: initialText,
        auth: auth,
        notice: clipboardEmpty ? '未能从剪切板读取内容（为空或不可用），请手动粘贴账号 JSON。' : null,
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context, AuthProvider auth) async {
    Navigator.of(context).pop();
    final ok = await showConfirmDialog(
      context,
      title: '退出登录',
      message: '确定退出 ${auth.username} 吗？\n将清除该账号的登录状态。',
      confirmText: '退出',
    );
    if (ok == true) {
      auth.logout();
    }
  }
}

/// 导入账号预览弹窗内容
///
/// 控制器由本 State 持有、随弹窗子树卸载才释放：showDialog 返回的 Future 在 pop
/// 时即完成，而弹窗退场动画期间子树仍会重建（导入成功会触发 AuthProvider
/// notifyListeners 重建整棵树），在 pop 前后提前 dispose 会抛
/// 「A TextEditingController was used after being disposed」。
class _ImportAccountsDialog extends StatefulWidget {
  const _ImportAccountsDialog({
    required this.initialText,
    required this.auth,
    this.notice,
  });

  final String initialText;
  final AuthProvider auth;

  /// 顶部提示（如剪切板读取失败的降级说明）
  final String? notice;

  @override
  State<_ImportAccountsDialog> createState() => _ImportAccountsDialogState();
}

class _ImportAccountsDialogState extends State<_ImportAccountsDialog> {
  late final TextEditingController _ctl = TextEditingController(
    text: widget.initialText,
  );

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _submit() {
    final raw = _ctl.text.trim();
    // 校验 JSON
    try {
      final parsed = jsonDecode(raw);
      if (parsed is! List) {
        showToast('JSON 格式错误：应为数组');
        return;
      }
      for (final item in parsed) {
        if (item is! Map ||
            !item.containsKey('username') ||
            !item.containsKey('uid')) {
          showToast('JSON 格式错误：缺少 username 或 uid');
          return;
        }
      }
    } catch (e) {
      showToast('JSON 解析失败: $e');
      return;
    }
    Navigator.of(context).pop();
    final result = widget.auth.importAccounts(raw);
    if (mounted) {
      showToast(
        result['success'] == true ? '成功导入' : '导入失败: ${result['message']}',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('导入账号'),
      constraints: const BoxConstraints(maxWidth: 420),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '请确认或编辑账号 JSON 数据：',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
          if (widget.notice != null) ...[
            const SizedBox(height: 6),
            Text(
              widget.notice!,
              style: TextStyle(fontSize: 12, color: cs.error),
            ),
          ],
          const SizedBox(height: 8),
          TextField(
            controller: _ctl,
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
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('导入')),
      ],
    );
  }
}

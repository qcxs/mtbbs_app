import 'package:flutter/material.dart';
import 'package:mtbbs/widgets/bbcode/post_html_widget.dart';
import 'package:mtbbs/widgets/common/user_avatar.dart';

/// 单条消息气泡：自己发的靠右（头像在右），对方的靠左（头像在左）
class PmMessageBubble extends StatelessWidget {
  final Map<String, dynamic> item;

  /// 发送失败时点击叹号的处理（弹「重新发送 / 删除」）；非失败态为 null
  final VoidCallback? onFailedTap;

  const PmMessageBubble({required this.item, this.onFailedTap, super.key});

  /// 气泡头像：用通用组件 [UserAvatar]（默认点击进入该用户个人空间）
  Widget _avatar(String uid, String nickname) {
    if (uid.isEmpty) return const SizedBox(width: 32);
    return UserAvatar(uid: uid, nickname: nickname, radius: 16);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isMine = item['isMine'] == true;
    final bbcode = item['bbcode'] as String? ?? '';
    final time = item['time'] as String? ?? '';
    final senderUid = item['senderUid'] as String? ?? '';
    final senderName = item['senderName'] as String? ?? '';
    final status = item['_status'] as String?;

    final bubble = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isMine ? cs.primaryContainer : cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: PostHtmlWidget(bbcode: bbcode, fontSize: 14),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: isMine
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isMine) ...[
            _avatar(senderUid, senderName),
            const SizedBox(width: 8),
          ] else ...[
            // 固定占位：状态指示器出现/消失不改变气泡可用宽度，
            // 避免"发送中→发送成功"过渡时气泡因 LayoutBuilder 可用宽变化而横向抖动
            _SendStatusIndicator(
              status: status,
              error: item['_error'] as String? ?? '',
              onFailedTap: onFailedTap,
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: constraints.maxWidth * 0.78,
                  ),
                  child: Column(
                    crossAxisAlignment: isMine
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start,
                    children: [
                      bubble,
                      const SizedBox(height: 2),
                      // 固定占位：本地"发送中"气泡与服务端气泡高度一致，
                      // 避免替换（本地占位 → 服务端消息）时列表因高度变化而纵向抖动
                      Text(
                        time,
                        style: TextStyle(
                          fontSize: 10,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          // 自己发的：头像在气泡右侧（与对方镜像）
          if (isMine) ...[
            const SizedBox(width: 8),
            _avatar(senderUid, senderName),
          ],
        ],
      ),
    );
  }
}

/// 自己的消息左侧的固定状态槽：转圈（发送中）／叹号（失败，点击弹操作）／空。
///
/// 槽位尺寸恒定，不随状态出现或消失——否则 `Flexible` 分给气泡的可用宽会变，
/// 气泡在"发送中→发送成功"过渡时会左右抖动。
class _SendStatusIndicator extends StatelessWidget {
  final String? status;
  final String error;
  final VoidCallback? onFailedTap;

  const _SendStatusIndicator({
    required this.status,
    required this.error,
    this.onFailedTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget child;
    if (status == 'sending') {
      child = const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    } else if (status == 'failed') {
      child = Tooltip(
        message: error.isNotEmpty ? '$error（点击重发或删除）' : '发送失败，点击重发或删除',
        child: InkWell(
          onTap: onFailedTap,
          borderRadius: BorderRadius.circular(12),
          child: Icon(Icons.error_outline, size: 18, color: cs.error),
        ),
      );
    } else {
      child = const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: SizedBox(width: 20, height: 20, child: Center(child: child)),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mtbbs/api/home/pm/export.dart' as pm_api;
import 'package:mtbbs/pages/message/paged_list_state.dart';
import 'package:mtbbs/services/api_service.dart';
import 'package:mtbbs/widgets/common/user_avatar.dart';
import 'package:mtbbs/widgets/layout/state_views.dart';

/// 私人消息 Tab
class PmTab extends StatefulWidget {
  const PmTab({super.key});

  @override
  State<PmTab> createState() => _PmTabState();
}

class _PmTabState extends State<PmTab> with PagedListStateMixin<PmTab> {
  @override
  Future<Map<String, dynamic>> fetchPage(int page) =>
      pm_api.getPmList(ApiService().dio, page: page);

  /// 打开与某用户的聊天页
  void _openChat(Map<String, dynamic> item) {
    final uid = item['uid'] as String? ?? '';
    if (uid.isEmpty || uid == '0') return;
    final username = item['username'] as String? ?? '';
    context.push(
      '/pm/chat?touid=$uid&username=${Uri.encodeComponent(username)}',
    );
  }

  @override
  Widget build(BuildContext context) {
    return buildPagedList(
      emptyView: const EmptyView(icon: Icons.forum_outlined, text: '暂无消息'),
      itemBuilder: (_, i) => _buildItem(items[i]),
    );
  }

  Widget _buildItem(Map<String, dynamic> item) {
    final cs = Theme.of(context).colorScheme;
    final uid = item['uid'] as String? ?? '';
    final username = item['username'] as String? ?? '';
    final isNew = item['isNew'] as bool? ?? false;
    final lastMessage = item['lastMessage'] as String? ?? '';
    final messageCount = item['messageCount'] as String? ?? '';
    final time = item['time'] as String? ?? '';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: cs.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openChat(item),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  UserAvatar(uid: uid, radius: 20),
                  if (isNew)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.error,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          username,
                          style: TextStyle(
                            fontWeight: isNew
                                ? FontWeight.w600
                                : FontWeight.normal,
                            fontSize: 14,
                            color: cs.onSurface,
                          ),
                        ),
                        if (messageCount.isNotEmpty) ...[
                          const SizedBox(width: 4),
                          Text(
                            '$messageCount 条',
                            style: TextStyle(
                              fontSize: 11,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                        const Spacer(),
                        Text(
                          time,
                          style: TextStyle(
                            fontSize: 11,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      lastMessage,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: cs.onSurfaceVariant,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerRight,
                      child: GestureDetector(
                        onTap: () => _openChat(item),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '回复',
                            style: TextStyle(
                              fontSize: 11,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

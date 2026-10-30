import 'package:flutter/material.dart';
import 'package:mtbbs/api/home/notice/export.dart' as notice_api;
import 'package:mtbbs/config/notice_config.dart';
import 'package:mtbbs/pages/message/notice_segments.dart';
import 'package:mtbbs/pages/message/notice_subtype_state.dart';
import 'package:mtbbs/pages/message/paged_list_state.dart';
import 'package:mtbbs/services/api_service.dart';
import 'package:mtbbs/widgets/common/user_avatar.dart';
import 'package:mtbbs/widgets/layout/state_views.dart';

/// 提醒列表 Tab —— 承载 `do=notice` 的一个「分组」（系统提醒 / 管理工作 / 坛友互动…）
///
/// 分组与子类型来自 [noticeGroups]（唯一数据源）：
/// - 分组有子类型（如坛友互动：打招呼/好友/留言…）→ 顶部渲染子类型 chip，请求带 `type`
/// - 无子类型（系统提醒 / 管理工作）→ 直接列表，服务端一次返回全量
class NoticeTab extends StatefulWidget {
  const NoticeTab({super.key, this.view = 'system', this.emptyText = '暂无提醒'});

  /// 站内 `do=notice&view=*` 的视图名（= [NoticeGroup.id]）
  final String view;

  /// 无提醒时的空态文案
  final String emptyText;

  @override
  State<NoticeTab> createState() => _NoticeTabState();
}

class _NoticeTabState extends State<NoticeTab>
    with PagedListStateMixin<NoticeTab>, NoticeSubtypeStateMixin<NoticeTab> {
  late final NoticeGroup? _group = noticeGroupOf(widget.view);

  @override
  String get noticeView => widget.view;

  @override
  List<NoticeType> get configuredTypes => _group?.types ?? const [];

  @override
  Future<Map<String, dynamic>> fetchPage(int page) => notice_api.getNoticeList(
    ApiService().dio,
    page: page,
    view: widget.view,
    type: noticeType,
  );

  @override
  void onPageFetched(Map<String, dynamic> result) =>
      applyNoticeNav(result['nav']);

  @override
  Widget build(BuildContext context) {
    return buildNoticeTab(body: _body);
  }

  Widget _body() => buildPagedList(
    emptyView: EmptyView(
      icon: Icons.notifications_none,
      text: widget.emptyText,
    ),
    itemBuilder: (_, i) => _buildItem(items[i]),
  );

  Widget _buildItem(Map<String, dynamic> item) {
    final cs = Theme.of(context).colorScheme;
    final time = item['time'] as String? ?? '';
    final timeTitle = item['timeTitle'] as String? ?? '';
    final segments = item['segments'] as List<dynamic>? ?? [];
    final fromNum = item['fromNum'] == true;
    // 站点在 authorid 非空时渲染的是对方头像（坛友互动/我的帖子）；
    // 系统提醒/管理工作是 systempm.png 系统图标 → 这里用图标兜底
    final avatarUid = item['avatarUid'] as String? ?? '';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (avatarUid.isNotEmpty)
                  UserAvatar(uid: avatarUid, radius: 18)
                else
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Icon(
                      Icons.notifications_active,
                      size: 20,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                const SizedBox(width: 10),
                const Spacer(),
                if (time.isNotEmpty)
                  Tooltip(
                    message: timeTitle.isNotEmpty ? timeTitle : time,
                    child: Text(
                      time,
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (segments.isNotEmpty)
              buildNoticeSegments(context, segments, includeQuote: true)
            else
              Text(
                item['message'] as String? ?? '',
                style: TextStyle(
                  fontSize: 13,
                  color: cs.onSurface,
                  height: 1.4,
                ),
              ),
            if (fromNum)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '已折叠同类型提醒',
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

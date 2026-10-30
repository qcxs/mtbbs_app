import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mtbbs/api/home/mypost/export.dart' as mypost_api;
import 'package:mtbbs/config/notice_config.dart';
import 'package:mtbbs/core/utils/url_router.dart';
import 'package:mtbbs/core/utils/url_util.dart';
import 'package:mtbbs/models/post_preview.dart';
import 'package:mtbbs/pages/message/notice_segments.dart';
import 'package:mtbbs/pages/message/notice_subtype_state.dart';
import 'package:mtbbs/pages/message/paged_list_state.dart';
import 'package:mtbbs/providers/settings_provider.dart';
import 'package:mtbbs/services/api_service.dart';
import 'package:mtbbs/widgets/bbcode/post_html_widget.dart';
import 'package:mtbbs/widgets/common/user_avatar.dart';
import 'package:mtbbs/widgets/layout/state_views.dart';
import 'package:provider/provider.dart';

/// 「我的帖子」分组配置（唯一数据源：lib/config/notice_config.dart）
final NoticeGroup _mypostGroup = noticeGroupOf('mypost')!;

/// 我的帖子 Tab
class MypostTab extends StatefulWidget {
  const MypostTab({super.key});

  @override
  State<MypostTab> createState() => _MypostTabState();
}

class _MypostTabState extends State<MypostTab>
    with PagedListStateMixin<MypostTab>, NoticeSubtypeStateMixin<MypostTab> {
  @override
  String get noticeView => 'mypost';

  @override
  List<NoticeType> get configuredTypes => _mypostGroup.types;

  final Map<int, PostPreviewData?> _previews = {};
  final Set<int> _previewLoading = {};

  @override
  Future<Map<String, dynamic>> fetchPage(int page) =>
      mypost_api.getMypostList(ApiService().dio, page: page, type: noticeType);

  @override
  void onPageFetched(Map<String, dynamic> result) =>
      applyNoticeNav(result['nav']);

  @override
  void onItemsReplaced() {
    _previews.clear();
    _previewLoading.clear();
    // 自动触发预览请求
    for (int i = 0; i < items.length; i++) {
      _tryFetchPreview(i);
    }
  }

  @override
  void onItemsAppended(int start) {
    // 只给新追加的条目拉预览
    for (int i = start; i < items.length; i++) {
      _tryFetchPreview(i);
    }
  }

  @override
  void onSubtypeChanged(String type) {
    _previews.clear();
    _previewLoading.clear();
  }

  // ==================== 预览逻辑 ====================

  Future<void> _tryFetchPreview(int index) async {
    if (index >= items.length) return;
    if (_previews.containsKey(index)) return;

    final item = items[index];
    final viewUrl = item['viewUrl'] as String? ?? '';
    final ids = parseViewUrl(viewUrl);
    if (ids == null) return;

    // 先查缓存
    final cached = PostPreviewManager.instance.getCached(ids.tid, ids.pid);
    if (cached != null) {
      if (mounted) setState(() => _previews[index] = cached);
      return;
    }

    setState(() => _previewLoading.add(index));
    final data = await PostPreviewManager.instance.fetch(ids.tid, ids.pid);
    if (!mounted) return;
    setState(() {
      _previews[index] = data;
      _previewLoading.remove(index);
    });
  }

  // ==================== Build ====================

  @override
  Widget build(BuildContext context) {
    // 子类型 chip 常驻：某个子类型为空时也要能切到别的类型（7 个子类型尤其需要）
    return buildNoticeTab(body: _body, alwaysShowHeader: true);
  }

  Widget _body() => buildPagedList(
    emptyView: const EmptyView(icon: Icons.forum_outlined, text: '暂无提醒'),
    itemBuilder: (_, i) => _buildItem(items[i], i),
  );

  // ==================== Item ====================

  Widget _buildItem(Map<String, dynamic> item, int index) {
    final cs = Theme.of(context).colorScheme;
    final uid = item['uid'] as String? ?? '';
    final username = item['username'] as String? ?? '';
    final time = item['time'] as String? ?? '';
    final timeTitle = item['timeTitle'] as String? ?? '';
    final segments = item['segments'] as List<dynamic>? ?? [];
    final viewUrl = item['viewUrl'] as String? ?? '';
    final ids = parseViewUrl(viewUrl);
    final isPreviewLoading = _previewLoading.contains(index);
    final preview = _previews[index];

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
            // 头部：头像 + 用户名 + 时间
            Row(
              children: [
                UserAvatar(uid: uid, radius: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    username,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
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
            const SizedBox(height: 6),
            // 通知消息体（结构化段落，标题可点击）
            if (segments.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: buildNoticeSegments(context, segments),
              ),
            const SizedBox(height: 8),
            // 预览区
            if (isPreviewLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Center(
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else if (preview != null && preview.bbcode.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: PostHtmlWidget(
                  bbcode: preview.bbcode,
                  disabledTags: const {},
                  autoDetectUrls: context
                      .read<SettingsProvider>()
                      .autoDetectUrls,
                ),
              ),
            // 操作按钮行
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // 查看按钮
                if (viewUrl.isNotEmpty)
                  _actionBtn(
                    label: '查看',
                    onTap: () {
                      final fullUrl = normalizeUrl(viewUrl);
                      final result = UrlRouter.parse(fullUrl);
                      if (result.appPath != null && !result.isOtherSite) {
                        context.push(result.appPath!);
                      } else {
                        context.push(
                          '/browser?url=${Uri.encodeComponent(fullUrl)}&intercept=false',
                        );
                      }
                    },
                  ),
                const SizedBox(width: 6),
                // 回复按钮
                if (ids != null)
                  _actionBtn(
                    label: '回复',
                    onTap: () => context.push(
                      '/editor?type=reply&tid=${ids.tid}&pid=${ids.pid}',
                    ),
                  ),
                if (preview != null && preview.bbcode.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  PopupMenuButton<String>(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                    icon: Icon(
                      Icons.more_horiz,
                      size: 16,
                      color: cs.onSurfaceVariant,
                    ),
                    onSelected: (v) {
                      if (v == 'showBbcode') {
                        showDialog(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            constraints: const BoxConstraints(
                              maxWidth: 500,
                              maxHeight: 400,
                            ),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'BBCode - $username',
                                    style: const TextStyle(fontSize: 15),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.close, size: 20),
                                  onPressed: () => Navigator.of(ctx).pop(),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                              ],
                            ),
                            content: SingleChildScrollView(
                              child: SelectableText(
                                preview.bbcode,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: cs.onSurface,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ),
                        );
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'showBbcode',
                        child: Text(
                          '查看 BBCode',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionBtn({required String label, required VoidCallback onTap}) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:mtbbs/api/home/mypost/export.dart' as mypost_api;
import 'package:mtbbs/services/api_service.dart';
import 'package:mtbbs/core/url_router.dart';
import 'package:mtbbs/core/emoji_loader.dart';
import 'package:mtbbs/models/post_preview.dart';
import 'package:mtbbs/providers/settings_provider.dart';
import 'package:mtbbs/widgets/user_avatar.dart';
import 'package:mtbbs/widgets/post_html_widget.dart';

/// 我的帖子 Tab
class MypostTab extends StatefulWidget {
  const MypostTab({super.key});

  @override
  State<MypostTab> createState() => _MypostTabState();
}

class _MypostTabState extends State<MypostTab> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;
  int _page = 1;
  int _totalPages = 1;
  String _type = 'post'; // post / at

  final Map<int, PostPreviewData?> _previews = {};
  final Set<int> _previewLoading = {};

  @override
  void initState() {
    super.initState();
    _load(1);
  }

  Future<void> _load(int page) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await mypost_api.getMypostList(
        ApiService().dio,
        page: page,
        type: _type,
      );
      if (!mounted) return;
      if (result['success'] != true) {
        setState(() {
          _error = result['message'] as String? ?? '加载失败';
          _loading = false;
        });
        return;
      }
      setState(() {
        _items = (result['items'] as List<dynamic>)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _page = result['currentPage'] as int? ?? page;
        _totalPages = result['totalPages'] as int? ?? 1;
        _loading = false;
        _previews.clear();
        _previewLoading.clear();
      });
      // 自动触发预览请求
      for (int i = 0; i < _items.length; i++) {
        _tryFetchPreview(i);
      }
    } catch (e) {
      if (mounted)
        setState(() {
          _error = e.toString();
          _loading = false;
        });
    }
  }

  void _goToPage(int p) {
    if (p < 1 || p > _totalPages || p == _page) return;
    _load(p);
  }

  void _switchType(String type) {
    if (type == _type) return;
    setState(() {
      _type = type;
      _previews.clear();
      _previewLoading.clear();
    });
    _load(1);
  }

  void _showPicker() {
    final tc = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('跳转页'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('共 $_totalPages 页，当前第 $_page 页'),
              const SizedBox(height: 8),
              TextField(
                controller: tc,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  hintText: '输入页码 (1-$_totalPages)',
                  border: const OutlineInputBorder(),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final p = int.tryParse(tc.text);
              if (p != null && p >= 1 && p <= _totalPages) {
                Navigator.of(ctx).pop();
                _goToPage(p);
              }
            },
            child: const Text('跳转'),
          ),
        ],
      ),
    );
  }

  // ==================== 预览逻辑 ====================

  Future<void> _tryFetchPreview(int index) async {
    if (index >= _items.length) return;
    if (_previews.containsKey(index)) return;

    final item = _items[index];
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
    final cs = Theme.of(context).colorScheme;
    if (_loading)
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: cs.onSurfaceVariant),
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: cs.onSurfaceVariant)),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () => _load(1),
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('重试'),
            ),
          ],
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.forum_outlined, size: 48, color: cs.onSurfaceVariant),
            const SizedBox(height: 8),
            Text('暂无提醒', style: TextStyle(color: cs.onSurfaceVariant)),
          ],
        ),
      );
    }

    return Column(
      children: [
        _buildHeader(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => _load(1),
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              itemCount: _items.length,
              itemBuilder: (_, i) => _buildItem(_items[i], i),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: cs.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _subTab('帖子', 'post'),
              const SizedBox(width: 4),
              _subTab('提到我的', 'at'),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.chevron_left, size: 20),
                onPressed: _page > 1 ? () => _goToPage(_page - 1) : null,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                padding: EdgeInsets.zero,
                tooltip: '上一页',
              ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: _showPicker,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$_page / $_totalPages',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.chevron_right, size: 20),
                onPressed: _page < _totalPages
                    ? () => _goToPage(_page + 1)
                    : null,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                padding: EdgeInsets.zero,
                tooltip: '下一页',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _subTab(String label, String type) {
    final cs = Theme.of(context).colorScheme;
    final active = _type == type;
    return GestureDetector(
      onTap: () => _switchType(type),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: active ? cs.surfaceContainerLow : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: active ? FontWeight.w600 : FontWeight.normal,
            color: active ? cs.onSurfaceVariant : cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

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
                child: _buildSegments(segments),
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
                  emojiMap: EmojiService().map,
                  smilieIdMap: EmojiService().smilieIdMap,
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
                      final fullUrl = viewUrl.startsWith('http')
                          ? viewUrl
                          : 'https://bbs.binmt.cc/$viewUrl';
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

  Widget _buildSegments(List<dynamic> segments) {
    final cs = Theme.of(context).colorScheme;
    final spans = <InlineSpan>[];
    final style = TextStyle(fontSize: 13, color: cs.onSurface, height: 1.4);

    for (final seg in segments) {
      final map = seg as Map<String, dynamic>;
      final type = map['type'] as String;
      final text = map['text'] as String? ?? '';
      if (text.isEmpty) continue;

      switch (type) {
        case 'thread':
          final url = map['url'] as String? ?? '';
          spans.add(
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: GestureDetector(
                onTap: url.isNotEmpty
                    ? () {
                        final fullUrl = url.startsWith('http')
                            ? url
                            : 'https://bbs.binmt.cc/$url';
                        final result = UrlRouter.parse(fullUrl);
                        if (result.appPath != null && !result.isOtherSite) {
                          context.push(result.appPath!);
                        } else {
                          context.push(
                            '/browser?url=${Uri.encodeComponent(fullUrl)}&intercept=false',
                          );
                        }
                      }
                    : null,
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: 13,
                    color: cs.onSurfaceVariant,
                    decoration: TextDecoration.underline,
                    height: 1.4,
                  ),
                ),
              ),
            ),
          );
        default:
          spans.add(TextSpan(text: text, style: style));
      }
    }
    return RichText(text: TextSpan(children: spans));
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

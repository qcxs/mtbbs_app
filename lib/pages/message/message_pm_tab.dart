import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mtbbs/api/home/pm/export.dart' as pm_api;
import 'package:mtbbs/services/api_service.dart';
import 'package:mtbbs/core/utils/url_util.dart';
import 'package:mtbbs/widgets/common/user_avatar.dart';
import 'package:mtbbs/widgets/layout/page_error_widget.dart';
import 'package:mtbbs/widgets/layout/pagination_bar.dart';
import 'package:mtbbs/widgets/layout/state_views.dart';

/// 私人消息 Tab
class PmTab extends StatefulWidget {
  const PmTab({super.key});

  @override
  State<PmTab> createState() => _PmTabState();
}

class _PmTabState extends State<PmTab> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;
  int _page = 1;
  int _totalPages = 1;

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
      final result = await pm_api.getPmList(ApiService().dio, page: page);
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
      });
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

  @override
  Widget build(BuildContext context) {
    if (_loading) return const LoadingView();
    if (_error != null) {
      return PageErrorWidget(
        message: _error!,
        onRetry: () => _load(1),
        showBack: false,
      );
    }
    if (_items.isEmpty) {
      return const EmptyView(icon: Icons.forum_outlined, text: '暂无消息');
    }

    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => _load(1),
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              itemCount: _items.length,
              itemBuilder: (_, i) => _buildItem(_items[i]),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: Theme.of(context).colorScheme.surface,
          child: PaginationBar(
            page: _page,
            totalPages: _totalPages,
            onGoToPage: _goToPage,
          ),
        ),
      ],
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
    final replyUrl = item['replyUrl'] as String? ?? '';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: cs.outlineVariant),
      ),
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
                      decoration: const BoxDecoration(
                        color: Colors.red,
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
                  if (replyUrl.isNotEmpty)
                    Align(
                      alignment: Alignment.centerRight,
                      child: GestureDetector(
                        onTap: () {
                          final fullUrl = normalizeUrl(replyUrl);
                          context.push(
                            '/browser?url=${Uri.encodeComponent(fullUrl)}&intercept=false',
                          );
                        },
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
    );
  }
}

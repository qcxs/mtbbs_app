import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mtbbs/api/home/system/export.dart' as system_api;
import 'package:mtbbs/services/api_service.dart';
import 'package:mtbbs/core/utils/url_router.dart';
import 'package:mtbbs/core/utils/url_util.dart';
import 'package:mtbbs/widgets/layout/page_error_widget.dart';
import 'package:mtbbs/widgets/layout/pagination_bar.dart';
import 'package:mtbbs/widgets/layout/state_views.dart';

/// 系统提醒 Tab
class SystemTab extends StatefulWidget {
  const SystemTab({super.key});

  @override
  State<SystemTab> createState() => _SystemTabState();
}

class _SystemTabState extends State<SystemTab> {
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
      final result = await system_api.getSystemList(
        ApiService().dio,
        page: page,
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
      return const EmptyView(icon: Icons.notifications_none, text: '暂无系统提醒');
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
    final time = item['time'] as String? ?? '';
    final segments = item['segments'] as List<dynamic>? ?? [];

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
                  Text(
                    time,
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (segments.isNotEmpty)
              _buildSegments(segments)
            else
              Text(
                item['message'] as String? ?? '',
                style: TextStyle(
                  fontSize: 13,
                  color: cs.onSurface,
                  height: 1.4,
                ),
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
    final quoteStyle = TextStyle(
      fontSize: 12,
      color: cs.onSurfaceVariant,
      height: 1.4,
      fontStyle: FontStyle.italic,
    );

    for (final seg in segments) {
      final map = seg as Map<String, dynamic>;
      final type = map['type'] as String;
      final text = map['text'] as String? ?? '';
      if (text.isEmpty) continue;

      switch (type) {
        case 'quote':
          spans.add(TextSpan(text: '\n留言：', style: quoteStyle));
          spans.add(TextSpan(text: text, style: quoteStyle));
        case 'user':
          final uid = map['uid'] as String? ?? '';
          spans.add(
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: GestureDetector(
                onTap: uid.isNotEmpty ? () => context.push('/user/$uid') : null,
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
        case 'thread':
          final url = map['url'] as String? ?? '';
          spans.add(
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: GestureDetector(
                onTap: url.isNotEmpty
                    ? () {
                        final fullUrl = normalizeUrl(url);
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
}

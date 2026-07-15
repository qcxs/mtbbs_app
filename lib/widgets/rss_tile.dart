import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../core/url_router.dart';
import '../core/logger.dart';

/// RSS 条目卡片
///
/// 接收 `item` Map，包含 title/link/description/pubDate/author 字段。
/// 点击后优先使用 [UrlRouter] 解析为 App 路由，不支持的链接走内置浏览器兜底。
class RssTile extends StatelessWidget {
  final Map<String, dynamic> item;

  const RssTile({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final title = item['title']?.toString() ?? '';
    final link = item['link']?.toString() ?? '';
    final description = item['description']?.toString() ?? '';
    final pubDate = item['pubDate']?.toString() ?? '';
    final author = item['author']?.toString() ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          final result = UrlRouter.parse(link);
          if (result.appPath != null) {
            context.push(result.appPath!);
          } else {
            AppLogger.w(
              'PAGE',
              'RSS link not recognized: $link, opening in browser',
            );
            if (link.isNotEmpty) {
              context.push('/browser?url=${Uri.encodeComponent(link)}');
            }
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  height: 1.3,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (description.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    description.replaceAll(RegExp(r'<[^>]+>'), ''),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              if (pubDate.isNotEmpty || author.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    children: [
                      if (author.isNotEmpty)
                        Text(
                          author,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      if (author.isNotEmpty && pubDate.isNotEmpty)
                        Text(
                          ' · ',
                          style: TextStyle(color: Colors.grey.shade300),
                        ),
                      if (pubDate.isNotEmpty)
                        Text(
                          pubDate,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade500,
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

import 'dart:convert';
import 'package:xml/xml.dart';
import 'package:mtbbs/core/logger.dart';

/// RSS 订阅条目
class RssItem {
  final String title;
  final String link;
  final String? description;
  final String? pubDate;
  final String? author;

  const RssItem({
    required this.title,
    required this.link,
    this.description,
    this.pubDate,
    this.author,
  });

  Map<String, dynamic> toJson() => {
    'title': title,
    'link': link,
    if (description != null) 'description': description,
    if (pubDate != null) 'pubDate': pubDate,
    if (author != null) 'author': author,
  };
}

/// 解析 RSS XML 响应
///
/// Discuz forum.php?mod=rss 返回标准 RSS 2.0 XML。
/// 使用 package:xml 解析（非 package:html），因为 HTML 解析器会将
/// <link> 当作 void 元素（自闭合），导致其文本内容被丢弃。
///
/// 返回 JSON 结构：
/// {
///   "success": true,
///   "channelTitle": "论坛名称",
///   "items": [RssItem, ...],
///   "count": 20,
/// }
Map<String, dynamic> parseResponse(String body, int statusCode) {
  if (statusCode != 200) {
    return {'success': false, 'message': 'HTTP $statusCode'};
  }

  if (body.trim().isEmpty) {
    return {'success': false, 'message': '响应为空'};
  }

  // 使用 XML 解析器，避免 HTML 解析器将 <link> 当作 void 元素
  XmlDocument doc;
  try {
    doc = XmlDocument.parse(body);
  } catch (e) {
    return {'success': false, 'message': 'XML 解析失败: $e'};
  }

  // 检查是否为有效的 RSS
  final rssRoot = doc.findAllElements('rss');
  if (rssRoot.isEmpty) {
    return {'success': false, 'message': '不是有效的 RSS 订阅'};
  }

  // 提取频道信息
  final channels = doc.findAllElements('channel');
  final channelTitle = channels.isNotEmpty
      ? (channels.first.getElement('title')?.innerText.trim() ?? '')
      : '';
  final rawItems = doc.findAllElements('item');

  final items = rawItems.map((el) {
    return RssItem(
      title: el.getElement('title')?.innerText.trim() ?? '',
      link: el.getElement('link')?.innerText.trim() ?? '',
      description: el.getElement('description')?.innerText.trim(),
      pubDate: el.getElement('pubDate')?.innerText.trim(),
      author:
          el.getElement('author')?.innerText.trim() ??
          el.getElement('dc:creator')?.innerText.trim(),
    );
  }).toList();

  AppLogger.i('PARSE', 'rss: "${channelTitle}" — ${items.length} items');
  if (items.isNotEmpty) {
    AppLogger.list(
      'PARSE',
      items,
      3,
      labelFn: (i) => jsonEncode(i.toJson()),
      summary: '${items.length} RSS items',
    );
  }

  return {
    'success': true,
    'channelTitle': channelTitle,
    'items': items.map((e) => e.toJson()).toList(),
    'count': items.length,
  };
}

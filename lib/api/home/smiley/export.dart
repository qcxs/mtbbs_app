import 'package:dio/dio.dart';
import 'package:mtbbs/core/site_store.dart';
import '../../helpers.dart';
import 'http.dart' as http;
import 'parse.dart' as parse;

/// 获取论坛表情数据
///
/// 内部流程：
/// 1. GET {cdnUrl}/data/cache/common_smilies_var.js
/// 2. 解析 JS 为结构化数据（图片 URL 基于 CDN 构建）
///
/// 返回包含：
/// - groups: 分组列表（用于表情选择器 UI）
/// - smilieIdMap: smilieId → insertText（用于 HTML→BBCode 转换）
/// - insertTextMap: insertText → imageUrl（用于 BBCode 预览渲染）
Future<Map<String, dynamic>> fetchSmilies(Dio dio) async {
  final resp = await http.getSmiliesJs(dio);
  return parseWithLog(
    resp,
    (b, s) => parse.parseResponse(b, baseUrl: SiteStore.instance.cdnUrl),
  );
}

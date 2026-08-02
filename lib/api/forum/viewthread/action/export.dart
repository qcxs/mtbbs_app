import 'package:dio/dio.dart';
import 'package:mtbbs/core/parser/xml_helper.dart';
import 'package:mtbbs/core/app/page_helper.dart';
import 'package:mtbbs/api/helpers.dart';
import 'http.dart' as http;
import 'parse.dart' as parse;

/// 获取评分弹窗表单数据
///
/// 如果返回的不是表单（已评分/不能评自己/无权限等提示），抛出 FormatException。
Future<parse.RateFormData> fetchRateDialog(Dio dio, String rateUrl) async {
  final resp = await http.getRateDialog(dio, rateUrl);
  final body = safeDecode(resp);

  // 非表单响应（提示信息窗）→ 取弹窗 body 文本作为错误消息
  final xml = parseInajaxXml(body);
  if (xml != null && xml.htmlDoc.querySelector('form') == null) {
    final msg = extractElementText(xml.htmlDoc.body)
        .replaceAll(RegExp(r'提示信息|关闭|确定|返回'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    throw FormatException(msg.isNotEmpty ? msg : '操作失败（无法获取评分表单）');
  }

  return parse.parseRateDialog(body);
}

/// 获取踢帖弹窗表单数据
Future<parse.KickFormData> fetchKickDialog(Dio dio, String kickUrl) async {
  final resp = await http.getKickDialog(dio, kickUrl);
  return parse.parseKickDialog(safeDecode(resp));
}

/// 获取收藏弹窗表单数据
///
/// 如果已收藏，抛出 FormatException。
Future<parse.FavoriteFormData> fetchFavoriteDialog(
  Dio dio,
  String favUrl,
) async {
  final resp = await http.getFavoriteDialog(dio, favUrl);
  final body = safeDecode(resp);

  // 已收藏检测
  final xml = parseInajaxXml(body);
  if (xml != null) {
    final tipText = extractElementText(xml.htmlDoc.body);
    if (tipText.contains('已收藏') || tipText.contains('请勿重复收藏')) {
      throw FormatException('您已收藏');
    }
  }

  return parse.parseFavoriteDialog(body);
}

/// 提交评分
Future<SubmitResult> doRate(
  Dio dio,
  String action,
  Map<String, dynamic> data,
) async {
  final resp = await http.submitRate(dio, action, data);
  return parseSubmitResponse(safeDecode(resp));
}

/// 提交踢帖
Future<SubmitResult> doKick(
  Dio dio,
  String action,
  Map<String, dynamic> data,
) async {
  final resp = await http.submitKick(dio, action, data);
  return parseSubmitResponse(safeDecode(resp));
}

/// 提交收藏
///
/// [action] 表单 action URL
/// [data] POST body 参数
/// [formId] 表单元素 id（如 favoriteform_3），用于在 URL 中添加 handlekey
Future<SubmitResult> doFavorite(
  Dio dio,
  String action,
  Map<String, dynamic> data, {
  String formId = '',
}) async {
  // 添加 formId 对应的 handlekey（Discuz 要求）
  final separator = action.contains('?') ? '&' : '?';
  final submitAction = formId.isNotEmpty
      ? '$action${separator}handlekey=$formId'
      : action;
  final resp = await http.submitFavorite(dio, submitAction, data);
  return parseSubmitResponse(safeDecode(resp));
}

/// 点赞
Future<SubmitResult> doRecommend(Dio dio, String recUrl) async {
  final resp = await http.submitRecommend(dio, recUrl);
  return parseSubmitResponse(safeDecode(resp));
}

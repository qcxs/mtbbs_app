import 'package:dio/dio.dart';
import 'package:mtbbs/core/parser/xml_helper.dart';
import 'package:mtbbs/core/app/page_helper.dart';
import 'package:mtbbs/api/helpers.dart';
import 'package:mtbbs/api/forum/viewthread/action/http.dart' as http;
import 'package:mtbbs/api/forum/viewthread/action/parse.dart' as parse;

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

/// 提交评分
Future<SubmitResult> doRate(
  Dio dio,
  String action,
  Map<String, dynamic> data,
) async {
  final resp = await http.submitRate(dio, action, data);
  return parseSubmitResponse(safeDecode(resp));
}

/// 点赞
Future<SubmitResult> doRecommend(Dio dio, String recUrl) async {
  final resp = await http.submitRecommend(dio, recUrl);
  return parseSubmitResponse(safeDecode(resp));
}

import 'package:dio/dio.dart';
import 'package:mtbbs/api/helpers.dart';
import 'package:mtbbs/api/forum/secqaa/http.dart' as http;
import 'package:mtbbs/api/forum/secqaa/parse.dart' as parse;
import 'package:mtbbs/core/utils/logger.dart';

/// 题面里自带的答案提示（部分站点把答案写在题目里）；取不到返回空串。
String secqaaAnswerFromQuestion(String question) =>
    parse.parseSecqaaAnswer(question);

/// 拉取验证问答题面。失败返回空串，由 UI 显示「题目加载失败」。
///
/// 首次加载与「换一个」都走这里：`action=update` 会同时把新题写入会话，
/// 题面只出现在响应里，页面 HTML 不带。
Future<String> fetchSecqaaQuestion(
  Dio dio, {
  required String idhash,
  String modId = '',
}) async {
  try {
    final resp = await http.updateSecqaa(
      dio,
      idhash: idhash,
      modId: modId,
    );
    final question = parse.parseSecqaaQuestion(safeDecode(resp));
    if (question.isEmpty) {
      AppLogger.w('PAGE', 'secqaa question empty: ${resp.statusCode}');
    }
    return question;
  } catch (e) {
    AppLogger.w('PAGE', 'secqaa update error: $e');
    return '';
  }
}

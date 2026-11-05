import 'package:mtbbs/core/parser/xml_helper.dart';

/// 解析「编辑提交」响应。
///
/// 编辑成功时 Discuz 返回 301/302 跳到 `viewthread`；失败则在 inajax 文本里
/// 给「抱歉 / 无权 / 限制…」。审核态单独标记。
SubmitResult parseEditResponse(
  String body,
  int statusCode,
  String location,
) {
  final loc = location.trim();
  if (statusCode == 301 || statusCode == 302) {
    if (loc.contains('viewthread')) {
      return const SubmitResult(success: true, message: '编辑成功');
    }
    return SubmitResult(success: false, message: '编辑后重定向异常: $loc');
  }

  final errorMatch = RegExp(
    r'(抱歉|错误|失败|小于|限制|禁止|不能|非法|无权|权限)',
  ).firstMatch(body);
  if (errorMatch != null) {
    final start = body.indexOf(errorMatch.group(0)!);
    final end = (start + 60).clamp(start, body.length);
    final snippet = body.substring(start, end);
    final message = snippet.replaceAll(RegExp(r'<[^>]+>'), '').trim();
    return SubmitResult(success: false, message: message);
  }

  if (body.contains('审核') || body.contains('审核中')) {
    return const SubmitResult(
      success: true,
      message: '编辑成功，等待审核',
      needsApproval: true,
    );
  }

  return const SubmitResult(success: true, message: '编辑成功');
}

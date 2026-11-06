/// 解析验证码相关响应（纯函数，无网络逻辑）。

/// 从「换一个」响应（JS 文本）中取出新的验证码图片地址。
///
/// 实测响应形如：
/// `... src="misc.php?mod=seccode&update=76386&idhash=cSi48v0C" ...`
/// 取不到时返回空串，由调用方决定兜底地址。
String parseUpdatedSeccodeImage(
  String body, {
  required String idhash,
}) {
  final match = RegExp(
    r'misc\.php\?mod=seccode(?:&amp;|&)update=(\d+)(?:&amp;|&)idhash=' +
        RegExp.escape(idhash),
  ).firstMatch(body);
  if (match == null) return '';
  return 'misc.php?mod=seccode&update=${match.group(1)}&idhash=$idhash';
}

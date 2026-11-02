/// 错误信息展示层格式化。
///
/// 把状态码 / Dio 异常 / 原始 HTML 这类对用户没有意义的串，换成可读文案；
/// 已经可读的服务端中文提示原样保留。**日志仍记录原始异常**，这里只影响 UI。
String friendlyErrorMessage(String raw) {
  var text = raw.trim();
  // 部分调用方会把异常直接 toString()，去掉前缀后可能还有可读内容
  while (text.startsWith('Exception: ')) {
    text = text.substring(11).trim();
  }
  if (text.isEmpty) return fallbackErrorMessage;

  final status = _statusCodeOf(text);
  if (status != null) {
    if (status == 401) {
      return '登录已过期（401）\n请重新登录后再试。';
    }
    if (status == 403) {
      return '访问受限（403）\n可能没有权限、登录已过期，或触发了站点防护。';
    }
    if (status == 404) {
      return '内容不存在（404）\n它可能已被删除、移动，或链接有误。';
    }
    if (status == 429) {
      return '请求过于频繁（429）\n请稍后再试。';
    }
    if (status == 408 || status == 504) {
      return '请求超时（$status）\n请检查网络后重试。';
    }
    if (status >= 500) {
      return '服务器暂时不可用（$status）\n请稍后重试。';
    }
    if (status >= 400) {
      return '请求失败（$status）\n请稍后重试。';
    }
  }

  final lower = text.toLowerCase();
  if (lower.contains('timeout') ||
      lower.contains('timed out') ||
      text.contains('超时')) {
    return '请求超时\n请检查网络后重试。';
  }
  if (_looksLikeNetworkError(lower)) {
    return '网络连接失败\n请检查网络后重试。';
  }
  if (_looksLikeRawHtml(lower) || text.length > 200) {
    return fallbackErrorMessage;
  }

  // 服务端 / 业务层已经给出的可读提示（如「帖子不存在或已被删除」）
  return text;
}

/// 兜底文案：原始信息没有任何展示价值时使用
const String fallbackErrorMessage = '加载失败，请稍后重试。';

/// 从 `HTTP 404` / `status code 404` / `statusCode: 404` /
/// `status code of 404`（Dio 默认异常文案）中提取状态码
int? _statusCodeOf(String text) {
  final match = RegExp(
    r'(?:http|status\s*(?:code)?\s*(?:of\s*)?)\s*[:=]?\s*(\d{3})',
    caseSensitive: false,
  ).firstMatch(text);
  return match == null ? null : int.tryParse(match.group(1)!);
}

bool _looksLikeNetworkError(String lower) {
  const needles = [
    'socketexception',
    'connection refused',
    'connection reset',
    'connection closed',
    'connection error',
    'failed host lookup',
    'network is unreachable',
    'network error',
    'networkexception',
    'clientexception',
    'xmlhttprequest error',
  ];
  if (needles.any(lower.contains)) return true;
  return lower.contains('网络') || lower.contains('连接失败');
}

bool _looksLikeRawHtml(String lower) =>
    lower.contains('<!doctype') ||
    lower.contains('<html') ||
    lower.contains('<body') ||
    lower.contains('<script');

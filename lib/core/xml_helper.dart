import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as htmlParser;

/// Discuz inajax 响应解析结果
class InajaxResult {
  final String cdataHtml;
  final dom.Document htmlDoc;

  InajaxResult(this.cdataHtml, this.htmlDoc);
}

/// 解析 Discuz inajax XML/CDATA 响应
/// 格式: <?xml...?><root><![CDATA[ HTML ]]></root>
InajaxResult? parseInajaxXml(String body) {
  try {
    final cdataMatch = RegExp(r'<!\[CDATA\[([\s\S]*?)\]\]>').firstMatch(body);
    if (cdataMatch == null) return null;
    final cdataContent = cdataMatch.group(1)!.trim();
    if (cdataContent.isEmpty) return null;
    final htmlDoc = htmlParser.parse(cdataContent);
    return InajaxResult(cdataContent, htmlDoc);
  } catch (_) {
    return null;
  }
}

// ============================================================
// 提交操作响应（统一解析）
// ============================================================

/// 统一提交操作结果
class SubmitResult {
  final bool success;
  final String message;

  /// 发帖/回复成功时从 redirect URL 中提取的 tid
  final String tid;

  /// 发帖/回复成功时从 redirect URL 中提取的 pid
  final String pid;

  /// 发帖/回复需要审核
  final bool needsApproval;

  const SubmitResult({
    required this.success,
    this.message = '',
    this.tid = '',
    this.pid = '',
    this.needsApproval = false,
  });
}

/// 从 DOM 元素中提取纯净文本（相当于 textContent，剔除 script/style 内容）
String _domText(dom.Element? el) {
  return extractTextContent(el);
}

/// 公开版本：从 DOM 元素提取纯净文本（剔除 script/style）
///
/// 可用于响应体中提取 Discuz 提示消息，无需自行拼接 textContent。
String extractTextContent(dom.Element? el) {
  if (el == null) return '';
  // 克隆后移除 script/style 标签，避免它们的文本污染结果
  final clone = el.clone(true);
  clone.querySelectorAll('script, style').forEach((e) => e.remove());
  return clone.text.trim().replaceAll(RegExp(r'\s+'), ' ');
}

/// 解析 inajax XML 提交响应，统一处理各种 Discuz 响应格式
///
/// 检测顺序（优先级从高到低）：
/// 1. Discuz Mobile System Error（`#message li` 中的系统错误）
/// 2. `succeedhandle_` 标准成功（包含 tid/pid/needsApproval）
/// 3. `errorhandle_` 标准失败（克米模板 `errorhandle_('ok')` 作为成功）
/// 4. `showDialog(...)` 消息提示
/// 5. `#messagetext p` 文本（用 DOM textContent 提取，干净无标签）
/// 6. 去标签后文本兜底
SubmitResult parseSubmitResponse(String body) {
  final xml = parseInajaxXml(body);
  final cdata = xml?.cdataHtml ?? body;
  final doc = xml?.htmlDoc;

  // 1. Discuz Mobile System Error
  // 格式: <table id="container"><tr><td class="bodytext" id="message"><ul><li>错误信息</li></ul></td></tr></table>
  if (doc != null) {
    final sysError = doc.querySelector('#message li, .bodytext#message li');
    if (sysError != null) {
      return SubmitResult(success: false, message: _domText(sysError));
    }
  }

  // 2. succeedhandle_ — Discuz 标准成功
  final successMatch = RegExp(
    r"succeedhandle_\('([^']+)',\s*'([^']*)'",
  ).firstMatch(cdata);
  if (successMatch != null) {
    final redirect = successMatch.group(1) ?? '';
    final message = successMatch.group(2) ?? '';
    final tid = RegExp(r'tid=(\d+)').firstMatch(redirect)?.group(1) ?? '';
    final pid = RegExp(r'pid=(\d+)').firstMatch(redirect)?.group(1) ?? '';
    final needsApproval = message.contains('审核');
    return SubmitResult(
      success: true,
      message: message.isNotEmpty ? message : '操作成功',
      tid: tid,
      pid: pid,
      needsApproval: needsApproval,
    );
  }

  // 3. errorhandle_ — Discuz 标准错误 / 克米模板特例
  final errorMatch = RegExp(r"errorhandle_\('([^']+)'").firstMatch(cdata);
  if (errorMatch != null) {
    final msg = errorMatch.group(1) ?? '';
    if (msg == 'ok' || msg == 'OK') {
      return const SubmitResult(success: true, message: '操作成功');
    }
    // "已评价"是点赞 toggle 的确认信息，视为成功
    if (msg.contains('已评价') || msg.contains('评价指数')) {
      return SubmitResult(success: true, message: msg);
    }
    return SubmitResult(success: false, message: msg);
  }

  // 4. showDialog 消息
  final dialogMatch = RegExp(r"showDialog\('([^']+)'\)").firstMatch(cdata);
  if (dialogMatch != null) {
    return SubmitResult(success: true, message: dialogMatch.group(1) ?? '操作成功');
  }

  // 5. #messagetext p — 用 DOM textContent 提取干净文本
  if (doc != null) {
    final msgText = doc.getElementById('messagetext');
    if (msgText != null) {
      final text = _domText(msgText);
      if (text.isNotEmpty) {
        if (text == 'ok' || text == 'OK') {
          return const SubmitResult(success: true, message: '操作成功');
        }
        if (text.contains('成功') ||
            text.contains('感谢') ||
            text.contains('已评价')) {
          return SubmitResult(success: true, message: text);
        }
        if (text.contains('抱歉') ||
            text.contains('无权') ||
            text.contains('没有权限')) {
          return SubmitResult(success: false, message: text);
        }
        return SubmitResult(success: false, message: text);
      }
    }

    // 也试一下 .comiis_tip dt 内的文本（克米模板的通用提示）
    final tipText = doc.querySelector('.comiis_tip dt');
    if (tipText != null) {
      final text = _domText(tipText);
      if (text.isNotEmpty && text != 'ok' && text != 'OK') {
        if (text.contains('成功') || text.contains('感谢')) {
          return SubmitResult(success: true, message: text);
        }
        return SubmitResult(success: false, message: text);
      }
    }
  }

  // 6. 去标签后文本兜底
  final clean = cdata.replaceAll(RegExp(r'<[^>]*>'), '').trim();
  if (clean.isNotEmpty) {
    if (clean == 'ok' || clean == 'OK') {
      return const SubmitResult(success: true, message: '操作成功');
    }
    if (clean.contains('成功') || clean.contains('感谢') || clean.contains('已评价')) {
      return SubmitResult(success: true, message: clean);
    }
    if (clean.contains('抱歉') ||
        clean.contains('无权') ||
        clean.contains('没有权限')) {
      return SubmitResult(success: false, message: clean);
    }
    return SubmitResult(success: false, message: clean);
  }

  return const SubmitResult(success: false, message: '未知响应');
}

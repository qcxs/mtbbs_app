import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as htmlParser;
import 'package:mtbbs/core/xml_helper.dart';

// ============================================================
// Data classes
// ============================================================

class RateItem {
  final String name;
  final String inputName;
  final List<String> options;
  final int min;
  final int max;
  final int todayRemaining;

  const RateItem({
    required this.name,
    required this.inputName,
    this.options = const [],
    this.min = 0,
    this.max = 0,
    this.todayRemaining = 0,
  });
}

class RateFormData {
  final String formhash;
  final String tid;
  final String pid;
  final String action;
  final List<RateItem> items;
  final List<String> reasonOptions;
  final bool hasNotifyAuthor;

  const RateFormData({
    required this.formhash,
    required this.tid,
    required this.pid,
    required this.action,
    this.items = const [],
    this.reasonOptions = const [],
    this.hasNotifyAuthor = false,
  });
}

class KickFormData {
  final String formhash;
  final String tid;
  final int currentKicks;
  final int maxKicks;
  final String action;

  const KickFormData({
    required this.formhash,
    required this.tid,
    required this.action,
    this.currentKicks = 0,
    this.maxKicks = 0,
  });
}

class FavoriteFormData {
  final String formhash;
  final String tid;
  final String action;

  /// 表单元素的 id，用于提交时构造 handlekey（如 favoriteform_3）
  final String formId;

  const FavoriteFormData({
    required this.formhash,
    required this.tid,
    required this.action,
    this.formId = '',
  });
}

// ============================================================
// Helpers
// ============================================================

String _extractInputValue(dom.Document doc, String name) {
  final byName = doc.querySelector('input[name="$name"]');
  if (byName != null) return byName.attributes['value'] ?? '';
  final byId = doc.querySelector('input#$name, input[id="$name"]');
  if (byId != null) return byId.attributes['value'] ?? '';
  return '';
}

String _extractFormAction(dom.Document doc) {
  final form = doc.querySelector('form');
  return form?.attributes['action'] ?? '';
}

// ============================================================
// Parse functions
// ============================================================

/// 解析评分弹窗表单
///
/// XML 格式：`<?xml version="1.0" encoding="utf-8"?><root><![CDATA[...]]></root>`
RateFormData parseRateDialog(String body) {
  final html = parseInajaxXml(body)?.cdataHtml ?? body;
  final doc = htmlParser.parse(html);

  final formhash = _extractInputValue(doc, 'formhash');
  final tid = _extractInputValue(doc, 'tid');
  final pid = _extractInputValue(doc, 'pid');
  final action = _extractFormAction(doc);

  // 解析评分项
  // 评分项在表格中，通常每个 tr 对应一个评分项
  final items = <RateItem>[];
  final rows = doc.querySelectorAll('tr');
  for (final row in rows) {
    // 检查是否有评分输入控件
    final select = row.querySelector('select[name^="score"]');
    final textInput = row.querySelector('input[type="text"][name^="score"]');
    final inputName =
        select?.attributes['name'] ?? textInput?.attributes['name'] ?? '';

    if (inputName.isEmpty) continue;

    // 获取评分项名称（通常是 td 或 th 中的文本）
    final nameTd = row.querySelector('th, td.label, td:first-child');
    final name = nameTd?.text.trim() ?? inputName;

    // 解析选项
    List<String> options = [];
    int min = 0, max = 0;

    if (select != null) {
      options = select
          .querySelectorAll('option')
          .map((o) => o.attributes['value'] ?? o.text.trim())
          .where((v) => v.isNotEmpty)
          .toList();
    }

    // 解析 min/max（从 select 的 option 值推断）
    if (options.isNotEmpty) {
      final values = options.map((v) => int.tryParse(v) ?? 0).toList();
      min = values.where((v) => v < 0).fold(0, (a, b) => a < b ? a : b);
      if (min == 0)
        min = values.where((v) => v > 0).fold(0, (a, b) => a < b ? a : b);
      max = values.fold(0, (a, b) => a > b ? a : b);
    }

    // 今日剩余
    int todayRemaining = 0;
    final remainMatch = RegExp(r'剩余\s*(\d+)').firstMatch(row.text);
    if (remainMatch != null) {
      todayRemaining = int.tryParse(remainMatch.group(1)!) ?? 0;
    }

    items.add(
      RateItem(
        name: name,
        inputName: inputName,
        options: options,
        min: min,
        max: max,
        todayRemaining: todayRemaining,
      ),
    );
  }

  // 解析可选理由
  final reasonOptions = <String>[];
  final reasonSelect = doc.querySelector('select[name="reason"]');
  if (reasonSelect != null) {
    for (final o in reasonSelect.querySelectorAll('option')) {
      final text = o.text.trim();
      if (text.isNotEmpty) reasonOptions.add(text);
    }
  }

  // 是否有通知作者 checkbox
  final notifyCheckbox = doc.querySelector('input[name="noticeauthor"]');
  final hasNotifyAuthor = notifyCheckbox != null;

  return RateFormData(
    formhash: formhash,
    tid: tid,
    pid: pid,
    action: action,
    items: items,
    reasonOptions: reasonOptions,
    hasNotifyAuthor: hasNotifyAuthor,
  );
}

/// 解析踢帖弹窗表单
KickFormData parseKickDialog(String body) {
  final html = parseInajaxXml(body)?.cdataHtml ?? body;
  final doc = htmlParser.parse(html);

  final formhash = _extractInputValue(doc, 'formhash');
  final tid = _extractInputValue(doc, 'tid');
  final action = _extractFormAction(doc);

  // 当前踢数和最大踢数
  int currentKicks = 0, maxKicks = 0;
  final text = doc.text;
  final kickMatch = RegExp(r'(\d+)\s*/\s*(\d+)').firstMatch(text ?? '');
  if (kickMatch != null) {
    currentKicks = int.tryParse(kickMatch.group(1)!) ?? 0;
    maxKicks = int.tryParse(kickMatch.group(2)!) ?? 0;
  }

  return KickFormData(
    formhash: formhash,
    tid: tid,
    action: action,
    currentKicks: currentKicks,
    maxKicks: maxKicks,
  );
}

/// 解析收藏弹窗表单
FavoriteFormData parseFavoriteDialog(String body) {
  final html = parseInajaxXml(body)?.cdataHtml ?? body;
  final doc = htmlParser.parse(html);

  final formhash = _extractInputValue(doc, 'formhash');
  final action = _extractFormAction(doc);
  // 收藏表单没有 <input name="tid">，tid 在 action URL 中
  final tid = RegExp(r'tid=(\d+)').firstMatch(action)?.group(1) ?? '';
  // 表单 ID（如 favoriteform_3），用于提交 URL 的 handlekey
  final form = doc.querySelector('form');
  final formId = form?.attributes['id'] ?? '';

  return FavoriteFormData(
    formhash: formhash,
    tid: tid,
    action: action,
    formId: formId,
  );
}

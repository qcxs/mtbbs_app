import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as htmlParser;
import 'package:mtbbs/core/parser/xml_helper.dart';

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
/// 兼容两种 Discuz 弹窗结构：
/// - 桌面 inajax XML：`<?xml...?><root><![CDATA[HTML]]></root>`（实际走 GET 完整页面，直接取 HTML）
/// - 评分项行结构（Chrome 实测，两个站点一致）：
/// ```html
/// <tr>
///   <td>金钱</td>
///   <td>
///     <input type="text" name="score2" id="score2" value="0">
///     <a class="dpbtn" onclick="showselect(this,'score2','scoreoption2')">^</a>
///     <ul id="scoreoption2"><li>+99</li>...</ul>   ← 可选值（DP 下拉）
///   </td>
///   <td>1 ~ 99</td>   ← 评分区间（min ~ max）
///   <td>999</td>      ← 今日剩余（可能为空）
/// </tr>
/// ```
/// 理由：`<ul id="reasonselect"><li>很给力!</li>...</ul>` + `<input name="reason">`
/// 通知作者：`<input type="checkbox" name="sendreasonpm">`
RateFormData parseRateDialog(String body) {
  final html = parseInajaxXml(body)?.cdataHtml ?? body;
  final doc = htmlParser.parse(html);

  final formhash = _extractInputValue(doc, 'formhash');
  final tid = _extractInputValue(doc, 'tid');
  final pid = _extractInputValue(doc, 'pid');
  final action = _extractFormAction(doc);

  // 解析评分项
  final items = <RateItem>[];
  for (final row in doc.querySelectorAll('tr')) {
    final textInput = row.querySelector('input[type="text"][name^="score"]');
    final select = row.querySelector('select[name^="score"]');
    final input = textInput ?? select;
    if (input == null) continue;

    final inputName = input.attributes['name'] ?? '';
    final inputId = input.attributes['id'] ?? '';

    // 评分项名称：第一个 td
    final nameTd = row.querySelector('td');
    final name = nameTd?.text.trim() ?? inputName;

    // 可选值：DP 下拉 ul（id=scoreoptionN 关联 input id=scoreN）或 select option
    List<String> options = [];
    if (select != null) {
      options = select
          .querySelectorAll('option')
          .map((o) => o.attributes['value'] ?? o.text.trim())
          .where((v) => v.isNotEmpty)
          .toList();
    } else {
      final optionUl = inputId.isNotEmpty
          ? doc.querySelector('ul#scoreoption${inputId.replaceFirst('score', '')}')
          : null;
      if (optionUl != null) {
        options = optionUl
            .querySelectorAll('li')
            .map((li) => li.text.trim())
            .where((v) => v.isNotEmpty)
            .toList();
      }
    }

    // 评分区间 / 今日剩余：列位置固定（0=名称, 1=输入, 2=区间, 3=剩余）
    int min = 0, max = 0, todayRemaining = 0;
    final tds = row.querySelectorAll('td');
    if (tds.length >= 3) {
      final rangeText = tds[2].text;
      final rangeMatch = RegExp(r'(-?\d+)\s*~\s*(-?\d+)').firstMatch(rangeText);
      if (rangeMatch != null) {
        min = int.tryParse(rangeMatch.group(1)!) ?? 0;
        max = int.tryParse(rangeMatch.group(2)!) ?? 0;
      }
    }
    if (tds.length >= 4) {
      todayRemaining = int.tryParse(tds[3].text.trim()) ?? 0;
    }
    // 兜底：无区间列文本时从可选值推断
    if (min == 0 && max == 0 && options.isNotEmpty) {
      final values = options.map((v) => int.tryParse(v) ?? 0).toList();
      min = values.where((v) => v < 0).fold(0, (a, b) => a < b ? a : b);
      if (min == 0)
        min = values.where((v) => v > 0).fold(0, (a, b) => a < b ? a : b);
      max = values.fold(0, (a, b) => a > b ? a : b);
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

  // 解析可选理由（ul#reasonselect li 或 select[name="reason"] option）
  final reasonOptions = <String>[];
  final reasonUl = doc.querySelector('ul#reasonselect');
  if (reasonUl != null) {
    for (final li in reasonUl.querySelectorAll('li')) {
      final text = li.text.trim();
      if (text.isNotEmpty) reasonOptions.add(text);
    }
  } else {
    final reasonSelect = doc.querySelector('select[name="reason"]');
    if (reasonSelect != null) {
      for (final o in reasonSelect.querySelectorAll('option')) {
        final text = o.text.trim();
        if (text.isNotEmpty) reasonOptions.add(text);
      }
    }
  }

  // 是否有通知作者 checkbox（sendreasonpm 是标准字段，noticeauthor 是旧模板兼容）
  final notifyCheckbox = doc.querySelector(
    'input[name="sendreasonpm"], input[name="noticeauthor"]',
  );
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

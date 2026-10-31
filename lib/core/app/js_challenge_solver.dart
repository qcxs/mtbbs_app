import 'dart:convert';

import 'package:mtbbs/core/app/acw_pure_dart.dart';
import 'package:mtbbs/core/utils/logger.dart';
import 'package:mtbbs/platform/optional/js_engine.dart';

/// 本地自解结果。
///
/// 站点 JS 挑战目前见过两种收尾方式：
/// - **写 cookie**：脚本把令牌写进 `document.cookie`（阿里云 ESA 的 `acw_sc__v2`）；
/// - **跳转**：脚本把算好的地址赋给 `window.location`（网宿 WZWS 的 `?wzwschallenge=`）。
///
/// 两者都无需用户参与，因此一次执行可以同时采集，交给调用方按顺序处理。
class JsChallengeSolution {
  const JsChallengeSolution({this.cookies = const {}, this.redirectUrl});

  /// 脚本写入的 cookie（只保留名值，忽略 domain/path/expires 等属性）。
  final Map<String, String> cookies;

  /// 脚本要求跳转的地址（可能为空）。
  final String? redirectUrl;

  bool get isEmpty => cookies.isEmpty && redirectUrl == null;
}

/// 站点 JS 挑战的**本地自解**（内嵌 JS 引擎执行挑战页脚本）。与厂商无关。
///
/// 已有样本：
/// - 阿里云 ESA：未过挑战返回 200 + 几 KB 挑战页，脚本用 `arg1` 算出
///   `acw_sc__v2` 写进 `document.cookie` 后 `location.reload()`；
/// - 网宿 WZWS：返回 200 + 30~40 KB 混淆脚本，既不写 cookie 也不发请求，
///   而是把 `?wzwschallenge=…&wzwsinfos=…` 拼到原路径后 `window.location = …`；
///   服务端认可后 302 回原地址并直接给真实页面（后续普通请求也会放行一段时间）。
///
/// **为什么执行脚本而不是照抄算法**：算法（置乱表 / 常量种子）随站点版本变化，
/// 执行真实脚本则自动跟随，无需改代码。探针侧仍保留纯 Dart 的 ACW 算法
/// （`tool/acw_challenge.dart`），它跑在 `flutter test` 里、不方便加载原生插件，
/// 同时充当"算法是否变了"的哨兵。
///
/// 解不出来（交互式验证、脚本结构变化、引擎异常）时返回 null，调用方回退到
/// WebView 人工验证（见 `VerificationGate`）。
class JsChallengeSolver {
  JsChallengeSolver._();

  static final JsChallengeSolver instance = JsChallengeSolver._();

  /// 是否跳过本地自解，直接把挑战交给 WebView（L2）。由 `main.dart` 绑定到设置项
  /// 「人机验证改用网页完成」，与 `VerificationGate.isEnabled` 同一套做法。
  ///
  /// 存在的理由：L1 上线后 L2（`VerifyBrowserPage`）平时**不会被触发**，也就无从验证
  /// 它是否可用；打开该开关即可强制复现那条链路。默认关闭。
  bool Function(String pageUrl) skipLocalSolve = (_) => false;

  static final RegExp _scriptRe = RegExp(r'<script[^>]*>([\s\S]*?)</script>');

  /// 从挑战页解出 cookie / 跳转地址；非挑战页 / 解不出返回 null。
  ///
  /// [pageUrl] 是**被挑战的那个请求地址**（浏览器里地址栏的值），脚本可能用它
  /// 做指纹（如 `window.location.hostname` / `protocol`）。
  ///
  /// 两段式：
  /// 1. **本地 JS 引擎**（QuickJS）——执行页面真实脚本，能自动跟随站点改算法；
  /// 2. **纯 Dart 算法兜底**——没有 JS 引擎实现（如鸿蒙）或脚本执行失败时，
  ///    仅覆盖阿里云 ESC 的 `arg1` 算法（与探针共用 `acw_pure_dart.dart`）。
  JsChallengeSolution? solve(String html, {String pageUrl = ''}) {
    if (skipLocalSolve(pageUrl)) {
      AppLogger.i('DIO', '已按设置跳过本地自解，改由 WebView 处理');
      return null;
    }
    final byJs = _solveWithJs(html, pageUrl);
    if (byJs != null && !byJs.isEmpty) return byJs;
    return _solveWithPureDart(html);
  }

  JsChallengeSolution? _solveWithJs(String html, String pageUrl) {
    final scripts = _scriptRe
        .allMatches(html)
        .map((m) => m.group(1)!.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (scripts.isEmpty) return null;

    final code = StringBuffer(_shim(pageUrl));
    for (final script in scripts) {
      // 单个脚本抛错不应连累后续脚本：挑战页可能混入统计/广告脚本
      code.write('\ntry {\n(function () {\n$script\n})();\n} catch (e) {}\n');
    }
    code.write('\nJSON.stringify({ c: __jar, r: __redir })');

    final result = JsEngine.run(code.toString());
    if (result == null || result.isError) {
      if (result != null) {
        AppLogger.w('DIO', 'JS 挑战自解：脚本执行报错 ${result.stringResult}');
      }
      return null;
    }

    try {
      final data = jsonDecode(result.stringResult);
      if (data is! Map) return null;
      final cookies = <String, String>{};
      final rawCookies = data['c'];
      if (rawCookies is Map) {
        rawCookies.forEach((k, v) {
          if (v is String) cookies[k.toString()] = v;
        });
      }
      final redirect = data['r'];
      return JsChallengeSolution(
        cookies: cookies,
        redirectUrl: (redirect is String && redirect.isNotEmpty)
            ? redirect
            : null,
      );
    } catch (e) {
      AppLogger.w('DIO', 'JS 挑战自解：结果解析失败 $e');
      return null;
    }
  }

  JsChallengeSolution? _solveWithPureDart(String html) {
    final arg1 = extractAcwArg1(html);
    if (arg1 == null) return null;
    final value = acwScV2(arg1);
    AppLogger.i('DIO', 'ACW 自解：使用纯 Dart 算法');
    return JsChallengeSolution(cookies: {'acw_sc__v2': value});
  }

  /// 最小 DOM 桩。
  ///
  /// 必备项（实测踩过的）：
  /// - `document.cookie` **可写且按名合并**（不能把整串覆盖掉，挑战脚本可能多次写）；
  /// - `document.location` / `window.location` 都要在：脚本读写位置不固定；
  ///   `window.location = url` 必须被捕获（WZWS 的通行证就是这次跳转）；
  /// - `setTimeout` / `setInterval` 必须存在但**不执行回调**：WZWS 用
  ///   `setInterval` 挂反调试死循环（`while(true)` 递归），执行会白耗配额；
  /// - 反调试分支会故意无限递归到栈溢出，靠 `catch` 吞异常，引擎栈上限见 `JsEngine`。
  ///
  /// **不要注入任何 Dart 能力、不要开 fetch/xhr**。
  static String _shim(String pageUrl) {
    final uri = Uri.tryParse(pageUrl);
    final protocol = (uri != null && uri.scheme.isNotEmpty)
        ? '${uri.scheme}:'
        : '';
    final hostname = uri?.host ?? '';
    final pathname = (uri != null && uri.path.isNotEmpty) ? uri.path : '/';
    final search = (uri != null && uri.hasQuery) ? '?${uri.query}' : '';

    return '''
var __jar = {};
var __redir = '';
function __putCookie(v) {
  var s = String(v || '');
  var p = s.split(';')[0];
  var i = p.indexOf('=');
  if (i > 0) { __jar[p.substring(0, i).trim()] = p.substring(i + 1).trim(); }
}
function __cookieString() {
  var out = [];
  for (var k in __jar) { out.push(k + '=' + __jar[k]); }
  return out.join('; ');
}
var __loc = {
  href: ${jsonEncode(pageUrl)},
  protocol: ${jsonEncode(protocol)},
  hostname: ${jsonEncode(hostname)},
  host: ${jsonEncode(hostname)},
  pathname: ${jsonEncode(pathname)},
  search: ${jsonEncode(search)},
  hash: '',
  reload: function () {},
  replace: function (u) { __redir = String(u); },
  assign: function (u) { __redir = String(u); }
};
var document = {
  write: function () {}, writeln: function () {},
  createElement: function () {
    return { style: {}, setAttribute: function () {}, appendChild: function () {},
             submit: function () {}, getContext: function () { return null; },
             canPlayType: function () { return ''; } };
  },
  getElementsByTagName: function () { return []; },
  getElementsByClassName: function () { return []; },
  getElementById: function () { return null; },
  querySelector: function () { return null; },
  querySelectorAll: function () { return []; },
  addEventListener: function () {}, removeEventListener: function () {},
  documentElement: { style: {} },
  body: { style: {}, appendChild: function () {} },
  head: { style: {} },
  readyState: 'complete', all: [], referrer: '', URL: ${jsonEncode(pageUrl)}
};
Object.defineProperty(document, 'cookie', {
  configurable: true,
  get: function () { return __cookieString(); },
  set: function (v) { __putCookie(v); }
});
Object.defineProperty(document, 'location', {
  configurable: true,
  get: function () { return __loc; },
  set: function (v) { __redir = String(v); }
});
var navigator = { userAgent: '', platform: '', languages: [], language: '',
                  cookieEnabled: true, webdriver: false, plugins: [], mimeTypes: [] };
var screen = { width: 0, height: 0, availWidth: 0, availHeight: 0,
               colorDepth: 24, pixelDepth: 24 };
var console = { log: function () {}, warn: function () {}, error: function () {},
                info: function () {}, debug: function () {} };
var alert = function () {};
var open = function () { return null; };
var setTimeout = function () { return 0; };
var setInterval = function () { return 0; };
var clearTimeout = function () {};
var clearInterval = function () {};
var self = this;
var window = this;
var top = this;
var parent = this;
Object.defineProperty(window, 'location', {
  configurable: true,
  get: function () { return __loc; },
  set: function (v) { __redir = String(v); }
});
''';
  }
}

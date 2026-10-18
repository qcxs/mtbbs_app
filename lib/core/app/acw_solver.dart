import 'package:mtbbs/core/app/acw_pure_dart.dart';
import 'package:mtbbs/core/utils/logger.dart';
import 'package:mtbbs/platform/optional/js_engine.dart';

/// 阿里云 ESA「acw_sc__v2」挑战的**本地自解**（内嵌 JS 引擎执行挑战页脚本）。
///
/// 站点前置 ESA 时，未过挑战会返回 200 + 几 KB 的挑战页：
/// `<html><script>var arg1='…'…</script></html>`，脚本用 `arg1` 算出
/// `acw_sc__v2` 写进 `document.cookie` 后 `location.reload()`。浏览器毫秒级静默
/// 完成，App 没有 JS 引擎时只能弹 WebView 让用户人工过一遍（可见、打断）。
/// 本类把这段脚本丢进内嵌 JS 引擎跑，直接拿到 `acw_sc__v2`——与浏览器同样无感。
///
/// **为什么执行脚本而不是照抄算法**：算法本身（置乱表 + 固定 key 逐字节异或）
/// 多年未变，但站点随时可能改；执行真实脚本则自动跟随，无需改代码。
/// 探针侧仍保留纯 Dart 版算法（`tool/acw_challenge.dart`）——它跑在
/// `flutter test` 里，不方便加载原生插件，且顺带充当"算法是否变了"的哨兵。
///
/// 解不出来（交互式验证、脚本结构变化、引擎异常）时返回 null，调用方回退到
/// WebView 人工验证（见 `VerificationGate`）。
class AcwSolver {
  AcwSolver._();

  static final AcwSolver instance = AcwSolver._();

  /// 是否跳过本地自解，直接把挑战交给 WebView（L2）。由 `main.dart` 绑定到设置项
  /// 「人机验证改用网页完成」，与 `VerificationGate.isEnabled` 同一套做法。
  ///
  /// 存在的理由：L1 上线后 L2（`VerifyBrowserPage`）平时**不会被触发**，也就无从验证
  /// 它是否可用；打开该开关即可强制复现那条链路。默认关闭。
  bool Function() skipLocalSolve = () => false;

  static final RegExp _scriptRe = RegExp(r'<script[^>]*>([\s\S]*?)</script>');
  static final RegExp _cookieRe = RegExp(r'acw_sc__v2=([0-9a-fA-F]+)');

  /// 最小 DOM 桩：脚本只用到 `document.cookie`（可写）与
  /// `document.location.reload()`，其余是反调试分支可能碰到的空实现。
  static const String _shim = r'''
var __c = '';
var location = { href:'', reload:function(){}, replace:function(){}, assign:function(){} };
var document = {
  get cookie(){ return __c; },
  set cookie(v){ __c = v; },
  location: location,
  write: function(){}, writeln: function(){},
  createElement: function(){ return { style:{}, setAttribute:function(){}, appendChild:function(){} }; },
  getElementsByTagName: function(){ return []; },
  getElementsByClassName: function(){ return []; },
  getElementById: function(){ return null; },
  querySelector: function(){ return null; },
  addEventListener: function(){},
  documentElement:{style:{}}, body:{style:{}}, head:{style:{}},
  readyState: 'complete', all: []
};
var navigator = { userAgent:'', platform:'', languages:[] };
var console = { log:function(){}, warn:function(){}, error:function(){}, info:function(){}, debug:function(){} };
var alert = function(){}; var open = function(){};
var self = this; var window = this;
''';

  /// 从挑战页正文解出 `acw_sc__v2`；非挑战页 / 解不出返回 null。
  ///
  /// 两段式：
  /// 1. **本地 JS 引擎**（QuickJS）——执行页面真实脚本，能自动跟随站点改算法；
  /// 2. **纯 Dart 算法兜底**——没有 JS 引擎实现（如鸿蒙）或脚本执行失败时使用。
  ///    算法与探针共用 `acw_pure_dart.dart`，两套实现对同一 `arg1` 等价。
  String? solve(String html) {
    if (skipLocalSolve()) {
      AppLogger.i('DIO', '已按设置跳过本地自解，改由 WebView 处理');
      return null;
    }
    return _solveWithJs(html) ?? _solveWithPureDart(html);
  }

  String? _solveWithJs(String html) {
    final m = _scriptRe.firstMatch(html);
    if (m == null) return null;
    final result = JsEngine.run(
      '$_shim\n(function(){\n${m.group(1)!}\n})();\ndocument.cookie',
    );
    if (result == null) return null;
    if (result.isError) {
      AppLogger.w('DIO', 'acw 自解：脚本执行报错 ${result.stringResult}');
      return null;
    }
    return _cookieRe.firstMatch(result.stringResult)?.group(1);
  }

  String? _solveWithPureDart(String html) {
    final arg1 = extractAcwArg1(html);
    if (arg1 == null) return null;
    final value = acwScV2(arg1);
    AppLogger.i('DIO', 'acw 自解：使用纯 Dart 算法');
    return value;
  }
}

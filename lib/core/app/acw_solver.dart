import 'dart:io';

import 'package:flutter_js/flutter_js.dart';
import 'package:mtbbs/core/utils/logger.dart';

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

  /// JS 栈上限。**必须显式调小**：挑战脚本里的反调试分支会故意无限递归直到栈
  /// 溢出，靠 `catch` 吞掉该错误来区分"原生/解释执行"。若用引擎默认的 1 MiB，
  /// 原生线程栈会先炸，整个进程以 `0xC00000FD`（STATUS_STACK_OVERFLOW）崩溃。
  /// 调到 256 KiB 后引擎会先抛可捕获错误，脚本正常跑完。
  static const int _stackSize = 256 * 1024;

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
  /// 每次都用**全新的运行时**：解算是低频事件（约每小时一次），换来的是不复用
  /// 上一次的全局状态、也不长期占用原生内存。
  String? solve(String html) {
    if (skipLocalSolve()) {
      AppLogger.i('DIO', '已按设置跳过本地自解，改由 WebView 处理');
      return null;
    }
    final m = _scriptRe.firstMatch(html);
    if (m == null) return null;
    JavascriptRuntime? js;
    try {
      js = _createRuntime();
      final r = js.evaluate(
        '$_shim\n(function(){\n${m.group(1)!}\n})();\ndocument.cookie',
      );
      if (r.isError) {
        AppLogger.w('DIO', 'acw 自解：脚本执行报错 ${r.stringResult}');
        return null;
      }
      return _cookieRe.firstMatch(r.stringResult)?.group(1);
    } catch (e) {
      AppLogger.w('DIO', 'acw 自解失败: $e');
      return null;
    } finally {
      js?.dispose();
    }
  }

  /// Windows / Linux / Android 走 QuickJS —— **必须自建**才能传入 [_stackSize]，
  /// 官方工厂 `getJavascriptRuntime` 只给 Android 透传该参数，Windows/Linux 会拿到
  /// 默认的 1 MiB 从而崩溃（见 [_stackSize]）。Apple 侧交给工厂（即系统 JSC）。
  JavascriptRuntime _createRuntime() {
    if (Platform.isAndroid || Platform.isWindows || Platform.isLinux) {
      return QuickJsRuntime2(stackSize: _stackSize);
    }
    return getJavascriptRuntime(xhr: false);
  }
}

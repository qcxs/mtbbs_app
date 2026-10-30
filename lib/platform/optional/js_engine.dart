import 'package:flutter_qjs_next/flutter_qjs.dart';
import 'package:mtbbs/core/app/app_capabilities.dart';
import 'package:mtbbs/core/utils/logger.dart';

/// 一次 JS 执行的结果（只暴露 ACW 自解需要的两个字段）。
class JsRunResult {
  const JsRunResult({required this.isError, required this.stringResult});

  final bool isError;
  final String stringResult;
}

/// 本地 JS 引擎适配器。
///
/// **唯一** import `flutter_qjs_next` 的地方。平台没有该插件实现时返回 null，
/// 由 `JsChallengeSolver` 切到纯 Dart 算法；调用异常时同时关闭
/// [AppCapability.localJsSolver]，避免后续请求反复尝试。
abstract final class JsEngine {
  JsEngine._();

  /// JS 栈上限。**必须显式调小**：挑战脚本里的反调试分支会故意无限递归直到栈
  /// 溢出，靠 `catch` 吞掉该错误来区分“原生/解释执行”。若用引擎默认的 1 MiB，
  /// 原生线程栈会先炸，整个进程以 `0xC00000FD`（STATUS_STACK_OVERFLOW）崩溃。
  static const int _stackSize = 256 * 1024;

  /// 单次自解的最长墙上时间（毫秒）。挑战脚本是瞬时计算，5 秒足够；超时即中断。
  static const int _timeout = 5000;

  /// 单次运行时的堆上限（字节）。挑战脚本极小，32 MiB 足够，兼作 OOM 护栏。
  static const int _memoryLimit = 32 * 1024 * 1024;

  /// 执行一段脚本并返回 `document.cookie` 的值；不可用或失败时返回 null。
  static JsRunResult? run(String script) {
    if (!AppCapabilities.isAvailable(AppCapability.localJsSolver)) return null;
    JavascriptRuntime? js;
    try {
      js = getJavascriptRuntime(
        stackSize: _stackSize,
        timeout: _timeout,
        memoryLimit: _memoryLimit,
      );
      final result = js.evaluate(script);
      return JsRunResult(
        isError: result.isError,
        stringResult: result.stringResult,
      );
    } on Error catch (e) {
      // 鸿蒙等平台没有原生实现时，插件会抛 MissingPluginException（Error 子类）
      // 或 UnimplementedError；两者都在这里收敛。
      AppLogger.w('DIO', '本地 JS 引擎不可用，改用纯 Dart 兜底: $e');
      AppCapabilities.disable(AppCapability.localJsSolver);
      return null;
    } catch (e) {
      AppLogger.w('DIO', '本地 JS 引擎执行异常: $e');
      return null;
    } finally {
      js?.dispose();
    }
  }
}

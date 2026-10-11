/// 探针场景类型定义与共享工具（无外部依赖）
library;

/// 探针场景定义
class ApiScenario {
  /// 场景描述（供 AI 理解用途）
  final String desc;

  /// 参数说明（key: 默认值 或 *必填）
  final Map<String, String> params;

  /// 是否必须登录（无 Cookie 时探针会拦截并提示）
  final bool needsLogin;

  /// 原始输出模式：为 true 时结果不做长字符串截断
  /// （调试场景用于展示完整原始响应，由场景自己控制输出长度）
  final bool raw;

  /// 是否支持**移动模板**（白名单，默认 false = 仅桌面模板 PC）。
  ///
  /// 前提与 MCP 的 `McpToolDefinition.mobileSupported` 一致：支持移动端的接口
  /// 必定同时支持 PC（有 PC 保底），且这类接口是少数。显式传 `ua=mobile` 时，
  /// 白名单外的场景会被拒绝并提示，避免把移动模板解析出的错数据当正常结果。
  final bool mobileSupported;

  /// 执行函数：args 为参数值（字符串）
  final Future<Map<String, dynamic>> Function(Map<String, String> args) run;

  const ApiScenario({
    required this.desc,
    required this.params,
    this.needsLogin = false,
    this.raw = false,
    this.mobileSupported = false,
    required this.run,
  });
}

/// 参数转 int（缺省/非法时用 fallback）
int intArg(Map<String, String> a, String key, int fallback) =>
    int.tryParse(a[key] ?? '') ?? fallback;

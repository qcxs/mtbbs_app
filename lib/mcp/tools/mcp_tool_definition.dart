import 'package:mcp_dart/mcp_dart.dart';
import 'package:mtbbs/mcp/mcp_types.dart';

/// 一个 MCP 工具的声明（名字 / 分组 / 描述 / 入参 schema / 实现）
///
/// 工具实现只负责"取数据 + 组装 Map"，出站脱敏与日志由
/// `McpToolRegistry` 统一处理。
class McpToolDefinition {
  const McpToolDefinition({
    required this.name,
    required this.group,
    required this.description,
    required this.properties,
    required this.run,
    this.requiredArgs = const [],
    this.network = true,
  });

  final String name;
  final McpToolGroup group;
  final String description;
  final Map<String, JsonSchema> properties;
  final List<String> requiredArgs;

  /// 是否真的会向论坛发起 HTTP 请求。
  ///
  /// AI 可能一口气并发调用多个工具，直连站点会被风控当成刷量；
  /// 为 true 时调用前先过 `enqueueStagger()` 错峰队列逐个放行。
  /// **默认 true**：新增工具时忘记声明的代价只是多等一个间隔，
  /// 反之（默认 false 却忘了标）会让请求不受限流，风险大得多。
  final bool network;

  /// 返回业务数据（Map），出站前统一过 `McpSanitizer`
  final Future<Map<String, dynamic>> Function(Map<String, dynamic> args) run;
}

/// 工具入参读取 —— 统一处理缺省、类型转换与范围裁剪。
///
/// MCP 客户端传参不受控（可能是字符串、数字或缺失），
/// 全部经这里归一化，避免每个工具重复写解析代码。
class McpArgs {
  McpArgs._();

  /// 读字符串，缺失/空白时返回 [fallback]
  static String str(
    Map<String, dynamic> args,
    String key, {
    String fallback = '',
  }) {
    final value = args[key];
    if (value == null) return fallback;
    final text = value.toString().trim();
    return text.isEmpty ? fallback : text;
  }

  /// 读必填字符串，缺失/空白时抛错（由调用包装转成可读的 MCP 错误）
  static String requireStr(
    Map<String, dynamic> args,
    String key, {
    String? label,
  }) {
    final value = str(args, key);
    if (value.isEmpty) throw ArgumentError('${label ?? key} 不能为空');
    return value;
  }

  /// 读整数并裁剪到 [min]~[max]，非法值返回 [fallback]
  static int integer(
    Map<String, dynamic> args,
    String key, {
    required int fallback,
    required int min,
    required int max,
  }) {
    final value = args[key];
    final parsed = value is num
        ? value.toInt()
        : int.tryParse(value?.toString() ?? '') ?? fallback;
    return parsed.clamp(min, max);
  }

  /// 读布尔，缺失/无法识别时返回 [fallback]
  ///
  /// 方法名不用 `bool`：会遮蔽同名的 Dart 内置类型。
  static bool boolean(
    Map<String, dynamic> args,
    String key, {
    bool fallback = false,
  }) {
    final value = args[key];
    if (value is bool) return value;
    if (value is num) return value != 0;
    final text = value?.toString().trim().toLowerCase();
    if (text == null || text.isEmpty) return fallback;
    return text == 'true' || text == '1' || text == 'yes';
  }
}

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:mtbbs/core/utils/logger.dart';

/// MCP 访问鉴权 —— 只接受**本机回环连接** + 正确的 **Bearer 令牌**。
///
/// 与 SDK 的 DNS rebinding 防护（Host / Origin 白名单）形成两层：
/// 那层挡"恶意网页借道访问"，这层挡"非本机来源"与"无令牌调用"。
class McpAuthenticator {
  McpAuthenticator._();

  static const String bearerPrefix = 'Bearer ';

  /// 生成 32 字节随机令牌（base64url，去掉 padding）
  static String generateToken() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(32, (_) => rnd.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  /// 是否接受该来源：**回环恒接受**；非回环仅在开启「允许非本机连接」时接受。
  ///
  /// 抽成纯函数便于单测（HttpRequest 不便构造）。
  static bool acceptsRemote({
    required bool isLoopback,
    required bool allowRemote,
  }) => isLoopback || allowRemote;

  /// 校验请求：来源必须是回环地址（或在开启「允许非本机连接」时允许非回环），
  /// 且携带 `Authorization: Bearer <token>`，且该令牌属于用户已创建的令牌列表。
  ///
  /// 令牌列表为空时一律拒绝（不允许"无令牌即放行"）。
  /// [allowRemote] 见 `McpServerController.allowRemote`（默认 false = 仅本机）。
  static bool authorize(
    dynamic request,
    Iterable<String> expectedTokens, {
    bool allowRemote = false,
  }) {
    try {
      final req = request as HttpRequest;
      final remote = req.connectionInfo?.remoteAddress;
      if (remote == null) return false;
      if (!acceptsRemote(
        isLoopback: remote.isLoopback,
        allowRemote: allowRemote,
      )) {
        AppLogger.w('MCP', '拒绝非本机连接: ${remote.address}（未开启「允许非本机连接」）');
        return false;
      }
      if (!remote.isLoopback) {
        AppLogger.i('MCP', '接受非本机连接: ${remote.address}');
      }
      final header = req.headers.value(HttpHeaders.authorizationHeader);
      if (header == null || !header.startsWith(bearerPrefix)) return false;
      final presented = header.substring(bearerPrefix.length).trim();

      // 逐个比较且不提前返回，避免"命中了第几个令牌"被时序推断
      var matched = false;
      for (final token in expectedTokens) {
        matched |= constantTimeEquals(presented, token);
      }
      return matched;
    } catch (e) {
      AppLogger.w('MCP', '鉴权异常: $e');
      return false;
    }
  }

  /// 常量时间比较，避免逐字符比较泄露令牌长度/内容
  static bool constantTimeEquals(String a, String b) {
    final x = utf8.encode(a);
    final y = utf8.encode(b);
    var diff = x.length ^ y.length;
    final len = x.length < y.length ? x.length : y.length;
    for (var i = 0; i < len; i++) {
      diff |= x[i] ^ y[i];
    }
    return diff == 0;
  }
}

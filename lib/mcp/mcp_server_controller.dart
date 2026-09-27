import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:mtbbs/core/utils/database_helper.dart';
import 'package:mtbbs/core/utils/logger.dart';
import 'package:mtbbs/mcp/mcp_authenticator.dart';
import 'package:mtbbs/mcp/mcp_self_test.dart';
import 'package:mtbbs/mcp/mcp_status_notice.dart';
import 'package:mtbbs/mcp/mcp_token.dart';
import 'package:mtbbs/mcp/mcp_types.dart';
import 'package:mtbbs/mcp/tools/mcp_tool_registry.dart';

/// MCP 服务运行状态
enum McpServerStatus { stopped, starting, running, error }

/// MCP 服务控制器 —— 唯一的状态源与生命周期管理者。
///
/// 隔离设计：
/// - 未启用时**不绑定任何端口**，不注册任何工具，对现有功能零影响；
/// - 只读工具复用 `lib/api/**/export.dart` 与 `ApiService().dio`，不新增解析层；
/// - 所有异常在工具边界被吞掉并转成 JSON-RPC error，不会向上冒泡到 UI。
///
/// 安全设计：
/// - 只绑 `127.0.0.1`，仅接受回环地址连接；
/// - 复用 SDK 的 DNS rebinding 防护（Host / Origin 白名单）；
/// - 必须携带本机生成的 Bearer token；
/// - 出站数据统一过 `McpSanitizer`；
/// - 单次调用 30s 硬超时（见 [McpToolRegistry.callTimeout]）。
class McpServerController extends ChangeNotifier {
  McpServerController._();
  static final McpServerController instance = McpServerController._();

  static const int defaultPort = 8765;
  static const int minPort = 1024;
  static const int maxPort = 65535;
  static const String endpointPath = '/mcp';

  /// 只绑回环，绝不监听 0.0.0.0
  static const String bindHost = '127.0.0.1';

  static const Set<String> _allowedHosts = {'127.0.0.1', 'localhost'};

  static const String _kEnabled = 'mcpEnabled';
  static const String _kPort = 'mcpPort';
  static const String _kTokens = 'mcpTokens';
  static const String _kDisabledGroups = 'mcpDisabledGroups';

  /// 旧版单令牌键（首次运行迁移为"默认令牌"，保住已配置的客户端）
  static const String _kLegacyToken = 'mcpToken';

  bool _loaded = false;
  bool _enabled = false;
  int _port = defaultPort;
  final List<McpToken> _tokens = [];

  /// 分组 → 工具数（静态：工具清单不随运行时变化）
  static final Map<McpToolGroup, int> _toolCounts =
      McpToolRegistry.toolCountByGroup();
  final Set<McpToolGroup> _disabledGroups = {
    for (final g in McpToolGroup.values)
      if (!g.defaultEnabled) g,
  };

  McpServerStatus _status = McpServerStatus.stopped;
  String? _lastError;
  int? _boundPort;
  StreamableMcpServer? _server;

  McpAccountInfoProvider _accountInfo = () => const McpAccountInfo.guest();

  // ==================== 只读状态 ====================

  DatabaseHelper get _db => DatabaseHelper.instance;

  bool get enabled => _enabled;
  int get port => _port;

  /// 用户创建的访问令牌（可多个，像 API Key 一样管理）
  List<McpToken> get tokens => List.unmodifiable(_tokens);

  /// 是否已有可用令牌：没有令牌时所有连接都会被拒绝
  bool get hasToken => _tokens.isNotEmpty;

  McpServerStatus get status => _status;
  String? get lastError => _lastError;
  bool get isRunning => _status == McpServerStatus.running;

  /// 实际监听端口（未运行时为配置端口）
  int get activePort => _boundPort ?? _port;

  String get endpointUrl => 'http://$bindHost:$activePort$endpointPath';

  bool isGroupEnabled(McpToolGroup group) => !_disabledGroups.contains(group);

  Set<McpToolGroup> get disabledGroups => Set.unmodifiable(_disabledGroups);

  /// 已开启分组的工具数 / 全部工具数（工具常驻注册，关闭的只是调用被拒）
  int get enabledToolCount => _toolCounts.entries
      .where((e) => isGroupEnabled(e.key))
      .fold(0, (sum, e) => sum + e.value);

  int get totalToolCount => _toolCounts.values.fold(0, (sum, v) => sum + v);

  // ==================== 启动 / 生命周期 ====================

  /// 绑定登录态快照（由 `main.dart` 注入，避免依赖 UI Provider 生命周期）
  void bindAccountInfo(McpAccountInfoProvider provider) {
    _accountInfo = provider;
  }

  /// 读取持久化配置；仅在启用时才启动服务。
  Future<void> bootstrap() async {
    await load();
    if (!_enabled || isRunning) return;
    await start();
    // 刚重启时上一个实例可能尚未释放端口，稍后重试一次
    if (!isRunning) {
      await Future.delayed(const Duration(milliseconds: 1200));
      await start();
    }
  }

  Future<void> load() async {
    if (_loaded) return;
    _enabled = (await _db.getSettingBool(_kEnabled)) ?? false;
    _port = ((await _db.getSettingInt(_kPort)) ?? defaultPort).clamp(
      minPort,
      maxPort,
    );

    await _loadTokens();

    final raw = await _db.getSetting(_kDisabledGroups);
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List<dynamic>;
        final parsed = <McpToolGroup>{};
        for (final id in list) {
          final group = McpToolGroup.fromId(id.toString());
          if (group != null) parsed.add(group);
        }
        _disabledGroups
          ..clear()
          ..addAll(parsed);
      } catch (_) {}
    }

    _loaded = true;
    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    if (_enabled == value) return;
    _enabled = value;
    await _db.setSettingBool(_kEnabled, value);
    notifyListeners();
    if (value) {
      await start();
    } else {
      await stop();
    }
  }

  Future<void> start() async {
    if (_server != null) return;

    _status = McpServerStatus.starting;
    _lastError = null;
    notifyListeners();

    try {
      final server = StreamableMcpServer(
        serverFactory: (sessionId) => McpToolRegistry.createServer(
          isGroupEnabled: isGroupEnabled,
          accountInfo: () => _accountInfo(),
        ),
        host: bindHost,
        port: _port,
        path: endpointPath,
        enableDnsRebindingProtection: true,
        allowedHosts: _allowedHosts,
        // 刻意**不传** allowedOrigins：显式传集合时 SDK 要求 Origin 字符串
        // 精确相等（含端口），于是 Trae 这类 Chromium 系客户端发来的
        // `http://127.0.0.1:8765` 会被 DNS rebinding 防护判为非法并返回 403，
        // 客户端只表现为一句 "list tools failed"，极难排查（见 docs/07 #63）。
        // 不传时 SDK 退化为「Origin 的 host 必须属于 allowedHosts」，
        // 即任意端口的回环 Origin 均放行，安全性等价：
        // 非回环 Origin 照样被拒，且 Host 校验与 Bearer 令牌两层防护仍在。
        enableJsonResponse: true,
        authenticator: (request) =>
            McpAuthenticator.authorize(request, _tokens.map((t) => t.value)),
      );
      await server.start();
      _server = server;
      _boundPort = server.boundPort;
      _status = McpServerStatus.running;
      AppLogger.i('MCP', '服务已启动 $endpointUrl');
      // Android：通知栏常驻状态，让用户明确 MCP 正在运行
      unawaited(McpStatusNotice.show(endpointUrl));
    } catch (e) {
      _server = null;
      _boundPort = null;
      _status = McpServerStatus.error;
      _lastError = _describeStartError(e);
      AppLogger.e('MCP', '服务启动失败: $e');
    }
    notifyListeners();
  }

  /// 把启动失败翻译成可操作提示（最常见的是端口被占用）
  String _describeStartError(Object e) {
    if (e is SocketException) {
      return '端口 $_port 无法监听：可能有另一个实例仍在占用，'
          '请关闭其他实例或改用其它端口'
          '（${e.osError?.message ?? e.message}）';
    }
    return e.toString();
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    _boundPort = null;
    _status = McpServerStatus.stopped;
    _lastError = null;
    notifyListeners();
    unawaited(McpStatusNotice.hide());
    if (server == null) return;
    try {
      await server.stop();
      AppLogger.i('MCP', '服务已停止');
    } catch (e) {
      AppLogger.w('MCP', '停止服务失败: $e');
    }
  }

  // ==================== 配置写入 ====================

  /// 端口变更：运行中则重启服务
  Future<void> setPort(int value) async {
    final next = value.clamp(minPort, maxPort);
    if (next == _port) return;
    _port = next;
    await _db.setSettingInt(_kPort, next);
    notifyListeners();
    if (_server != null) {
      await stop();
      await start();
    }
  }

  // ==================== 访问令牌管理 ====================

  Future<void> _loadTokens() async {
    final raw = await _db.getSetting(_kTokens);
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List<dynamic>;
        _tokens
          ..clear()
          ..addAll(
            list.map((e) => McpToken.fromJson(e as Map<String, dynamic>)),
          );
      } catch (_) {}
    }
    if (_tokens.isNotEmpty) return;

    // 旧版单令牌迁移：保住用户已经配置好的客户端
    final legacy = await _db.getSetting(_kLegacyToken);
    if (legacy == null || legacy.isEmpty) return;
    _tokens.add(
      McpToken(
        id: _newTokenId(),
        value: legacy,
        note: '默认令牌',
        createdAt: DateTime.now(),
      ),
    );
    await _persistTokens();
    await _db.deleteSetting(_kLegacyToken);
    AppLogger.i('MCP', '旧版令牌已迁移为「默认令牌」');
  }

  /// 新建令牌（值由 App 生成，用户只填备注）
  Future<McpToken> createToken({String note = ''}) async {
    final token = McpToken(
      id: _newTokenId(),
      value: McpAuthenticator.generateToken(),
      note: note.trim().isEmpty ? McpToken.fallbackNote : note.trim(),
      createdAt: DateTime.now(),
    );
    _tokens.add(token);
    await _persistTokens();
    AppLogger.i('MCP', '已创建访问令牌「${token.note}」');
    return token;
  }

  /// 刷新令牌值（id 与备注保持不变），返回刷新后的令牌
  Future<McpToken> refreshToken(String id) async {
    final index = _tokens.indexWhere((t) => t.id == id);
    if (index < 0) throw ArgumentError('令牌不存在');
    final next = _tokens[index].copyWith(
      value: McpAuthenticator.generateToken(),
    );
    _tokens[index] = next;
    await _persistTokens();
    AppLogger.i('MCP', '已刷新访问令牌「${next.note}」');
    return next;
  }

  Future<void> renameToken(String id, String note) async {
    final index = _tokens.indexWhere((t) => t.id == id);
    if (index < 0) return;
    final text = note.trim();
    _tokens[index] = _tokens[index].copyWith(
      note: text.isEmpty ? McpToken.fallbackNote : text,
    );
    await _persistTokens();
  }

  Future<void> deleteToken(String id) async {
    final before = _tokens.length;
    _tokens.removeWhere((t) => t.id == id);
    if (_tokens.length == before) return;
    await _persistTokens();
    AppLogger.i('MCP', '已删除访问令牌');
  }

  Future<void> _persistTokens() async {
    await _db.setSetting(
      _kTokens,
      jsonEncode(_tokens.map((t) => t.toJson()).toList()),
    );
    notifyListeners();
  }

  static String _newTokenId() =>
      'tk_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';

  /// 开关某个能力分组。
  ///
  /// `serverFactory` 按请求创建 Server 实例，因此下一个请求即生效，
  /// 不需要重启服务（也不会断开已连接的客户端）。
  Future<void> setGroupEnabled(McpToolGroup group, bool enabled) async {
    final changed = enabled
        ? _disabledGroups.remove(group)
        : _disabledGroups.add(group);
    if (!changed) return;
    await _db.setSetting(
      _kDisabledGroups,
      jsonEncode(_disabledGroups.map((g) => g.id).toList()),
    );
    notifyListeners();
  }

  // ==================== 鉴权 ====================
  // 实现见 McpAuthenticator：回环来源校验 + Bearer 令牌 + 常量时间比较

  // ==================== 连通性自检 ====================

  bool _testing = false;
  McpSelfTestResult? _lastSelfTest;

  /// 是否正在自检（设置页用它显示进度）
  bool get testing => _testing;

  /// 最近一次自检结果（设置页用它显示结论）
  McpSelfTestResult? get lastSelfTest => _lastSelfTest;

  /// 真实走一遍 MCP 协议（listTools + 调一个工具），验证
  /// 端口 / Host-Origin 校验 / 令牌鉴权 / 工具执行四条链路。
  Future<McpSelfTestResult> selfTest() async {
    if (!isRunning) {
      return const McpSelfTestResult(ok: false, message: '服务未运行，请先开启 MCP 服务');
    }
    if (!hasToken) {
      return const McpSelfTestResult(
        ok: false,
        message: '尚未创建访问令牌：先在「访问令牌」里新建一个再测试',
      );
    }
    if (_testing) {
      return _lastSelfTest ??
          const McpSelfTestResult(ok: false, message: '正在测试中，请稍候…');
    }

    _testing = true;
    _lastSelfTest = null;
    notifyListeners();

    final result = await McpSelfTest.run(
      endpointUrl: endpointUrl,
      token: _tokens.first.value,
    );
    _testing = false;
    _lastSelfTest = result;
    notifyListeners();
    return result;
  }
}

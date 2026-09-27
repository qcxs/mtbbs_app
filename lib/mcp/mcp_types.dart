/// MCP 能力分组 —— 决定哪些工具会被注册暴露给 AI 客户端。
///
/// 用户可在「设置 → 存储与工具 → MCP 服务」里逐组开关，不写死。
/// [defaultEnabled] 是首次启用 MCP 时的默认值：与"账号相关数据"
/// （收藏/关注）和本地浏览记录默认关闭，其余默认开启。
enum McpToolGroup {
  appInfo(
    id: 'app_info',
    label: 'App 信息',
    description: '版本、当前站点、登录状态（不含任何凭据）',
    defaultEnabled: true,
  ),
  publicData(
    id: 'public_data',
    label: '论坛公开数据',
    description: '版块、帖子、用户公开资料、排行榜、在线会员、RSS',
    defaultEnabled: true,
  ),
  editorRead(
    id: 'editor_read',
    label: '只读编辑器草稿',
    description: '读取编辑器里正在写的内容与历史快照',
    defaultEnabled: true,
  ),
  accountData(
    id: 'account_data',
    label: '账号相关数据',
    description: '我的收藏（需登录；收藏不公开，仅自己可见）',
    defaultEnabled: false,
  ),
  localData(
    id: 'local_data',
    label: '本地浏览记录',
    description: 'App 内保存的浏览历史',
    defaultEnabled: false,
  );

  const McpToolGroup({
    required this.id,
    required this.label,
    required this.description,
    required this.defaultEnabled,
  });

  /// 持久化用的稳定标识（改文案不会影响已保存的开关）
  final String id;

  /// 设置页显示名
  final String label;

  /// 设置页副标题
  final String description;

  final bool defaultEnabled;

  static McpToolGroup? fromId(String id) {
    for (final g in values) {
      if (g.id == id) return g;
    }
    return null;
  }
}

/// 登录态快照 —— 由 `main.dart` 注入，避免 MCP 层直接依赖 UI 层 Provider。
class McpAccountInfo {
  const McpAccountInfo({
    required this.isLoggedIn,
    required this.username,
    required this.uid,
    required this.userGroup,
  });

  const McpAccountInfo.guest()
    : isLoggedIn = false,
      username = '',
      uid = '',
      userGroup = '游客';

  final bool isLoggedIn;
  final String username;
  final String uid;
  final String userGroup;

  Map<String, dynamic> toJson() => {
    'isLoggedIn': isLoggedIn,
    if (isLoggedIn) 'username': username,
    if (isLoggedIn) 'uid': uid,
    'userGroup': userGroup,
  };
}

/// 登录态提供者（`main.dart` 绑定，未绑定时视为游客）
typedef McpAccountInfoProvider = McpAccountInfo Function();

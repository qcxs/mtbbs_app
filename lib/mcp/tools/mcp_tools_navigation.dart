import 'package:mcp_dart/mcp_dart.dart';
import 'package:mtbbs/mcp/mcp_scope.dart';
import 'package:mtbbs/mcp/mcp_types.dart';
import 'package:mtbbs/mcp/tools/mcp_tool_definition.dart';

/// 打开 App 页面的回调：成功返回 null，失败返回给 AI 看的原因。
///
/// 由 `main.dart` 在路由创建后注入（MCP 层不直接依赖 UI 层）。
typedef McpPageOpener = String? Function(String path);

/// App 导航组（`McpToolGroup.navigation`）
///
/// 只允许跳转到**内容页白名单**：帖子 / 用户 / 版块 / 搜索 / 导读 / 首页。
/// 刻意不开放设置、编辑器、内置浏览器（任意 URL）与私信页，避免 AI 把用户
/// 带进写操作或私密页面。
List<McpToolDefinition> navigationTools(McpPageOpener? openPage) => [
  McpToolDefinition(
    name: 'open_app_page',
    group: McpToolGroup.navigation,
    description:
        '在 App 内打开指定内容页面（帖子 / 用户 / 版块 / 搜索 / 导读 / 首页）。'
        '仅在用户明确要求「打开 / 跳转 / 带我去看」时调用；App 需在前台，'
        '后台调用不会把界面带到前台。不开放设置、编辑器、内置浏览器与私信页。'
        '若用户开启了跨站点访问，可额外传 site 打开其它站点的帖子 / 用户 / 搜索页。',
    properties: {
      'target': JsonSchema.string(
        description: '目标页面类型',
        enumValues: const ['thread', 'user', 'forum', 'search', 'guide', 'home'],
      ),
      'id': JsonSchema.string(
        description: '目标 ID：thread=帖子 tid，user=用户 uid，forum=版块 fid',
      ),
      'page': JsonSchema.integer(
        minimum: 1,
        maximum: 200,
        description: '仅 thread 生效：打开第几页，默认 1',
      ),
      'keyword': JsonSchema.string(
        description: '仅 search 生效：搜索关键词',
      ),
    },
    requiredArgs: const ['target'],
    network: false, // 本地导航，不发请求
    readOnlyHint: false, // 会改变 App 当前页面，不能声明为只读
    run: (args) async {
      final opener = openPage;
      if (opener == null) {
        throw StateError('App 页面导航尚未就绪（路由未创建或 App 正在启动），请稍后重试');
      }
      final target = McpArgs.requireStr(args, 'target').toLowerCase();
      final path = _resolvePath(target, args);
      final error = opener(path);
      if (error != null) throw StateError(error);
      return {'opened': true, 'target': target, 'path': path};
    },
  ),
];

String _resolvePath(String target, Map<String, dynamic> args) {
  final scope = McpScope.current;
  // 跨站点只支持路由器已实现的「直开内容页」（见 docs/27）：
  // 版块 / 导读 / 首页在其它站点会被路由器改送内置浏览器，这里提前拒绝。
  final crossSite = scope != null && scope.crossSite;
  final siteParam = {
    if (crossSite) 'site': scope.host,
  };
  if (crossSite && !const {'thread', 'user', 'search'}.contains(target)) {
    throw ArgumentError(
      '跨站点只能打开帖子 / 用户 / 搜索页（target=thread / user / search）；'
      '版块、导读、首页请回到当前站点或用 open_app_page 的 site 省略后再打开',
    );
  }
  switch (target) {
    case 'thread':
      final tid = _requireNumericId(args, 'tid');
      final page = McpArgs.integer(args, 'page', fallback: 1, min: 1, max: 200);
      return Uri(
        path: '/thread/$tid',
        queryParameters: {if (page > 1) 'page': '$page', ...siteParam},
      ).toString();
    case 'user':
      return Uri(
        path: '/user/${_requireNumericId(args, 'uid')}',
        queryParameters: siteParam.isEmpty ? null : siteParam,
      ).toString();
    case 'forum':
      return '/forum?fid=${_requireNumericId(args, 'fid')}';
    case 'search':
      final keyword = McpArgs.requireStr(args, 'keyword', label: 'keyword');
      return Uri(
        path: '/search/result',
        queryParameters: {'kw': keyword, ...siteParam},
      ).toString();
    case 'guide':
      return '/guide';
    case 'home':
      return '/';
    default:
      throw ArgumentError(
        '不支持的 target=$target，可用：thread / user / forum / search / guide / home',
      );
  }
}

String _requireNumericId(Map<String, dynamic> args, String label) {
  final value = McpArgs.requireStr(args, 'id', label: 'id（$label）');
  if (!RegExp(r'^\d+$').hasMatch(value)) {
    throw ArgumentError('id 必须是数字（$label），收到：$value');
  }
  return value;
}

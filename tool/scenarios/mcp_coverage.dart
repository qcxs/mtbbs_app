/// 探针场景 ↔ MCP 工具覆盖矩阵
///
/// 目的是让「新增了 MCP 工具」「新增了探针场景」这两件事能被一条命令发现：
/// 跑 `--dart-define=cmd=coverage`，看哪些工具没有任何探针能验证、
/// 哪些场景还没有对应的 MCP 工具。
library;

import 'package:mtbbs/mcp/mcp_types.dart';
import 'package:mtbbs/mcp/tools/mcp_tool_registry.dart';

/// 场景 → 对应的 MCP 工具（一个场景可以覆盖多个工具）。
///
/// 写操作场景、纯页面渲染类场景没有 MCP 工具，属正常现象，不必强行映射。
const Map<String, List<String>> _scenarioToMcpTools = {
  'session.list': ['get_app_info', 'list_sites'],
  'session.status': ['get_app_info', 'get_user_profile'],
  'guide.list': ['list_guide_threads'],
  'forum.list': ['list_forum_threads'],
  'ranklist.thread': ['get_ranklist'],
  'ranklist.member': ['get_ranklist'],
  'ranklist.forum': ['get_ranklist'],
  'online.list': ['get_online_users'],
  'rss.list': ['get_rss_feed'],
  'forum.nav': ['list_forums'],
  'group.index': ['list_groups'],
  'group.category': ['list_group_forums'],
  'search.list': ['search_forum_threads'],
  'thread.detail': ['get_thread_detail'],
  'user.info': ['get_user_profile', 'list_user_threads'],
  'wall.list': ['list_wall_messages'],
  'friend.list': ['list_user_friends'],
  'follow.list': ['list_user_follows'],
  'favorite.list': ['list_my_favorites'],
  'credit.log': ['list_credit_log'],
  'message.system': ['list_notifications'],
  'message.manage': ['list_notifications'],
  'message.interactive': ['list_notifications'],
  'notice.counts': ['list_notifications'],
  'my.threads': ['list_user_threads'],
  'cache.list': ['get_thread_detail'],
  'cache.thread': ['get_thread_detail'],
};

/// 生成覆盖矩阵（不联网、不需要登录）
Map<String, dynamic> buildMcpCoverage(Iterable<String> scenarioKeys) {
  final keys = scenarioKeys.toList()..sort();
  final tools = McpToolRegistry.buildTools(
    () => const McpAccountInfo.guest(),
  ).map((t) => t.name).toSet();
  final mapped = <String, List<String>>{};
  final coveredTools = <String>{};
  for (final key in keys) {
    final targets = (_scenarioToMcpTools[key] ?? const <String>[])
        .where(tools.contains)
        .toList();
    if (targets.isEmpty) continue;
    mapped[key] = targets;
    coveredTools.addAll(targets);
  }
  final mappingUnknown = <String>{
    for (final targets in _scenarioToMcpTools.values) ...targets,
  }.difference(tools).toList()..sort();
  return {
    'scenarioTotal': keys.length,
    'mcpToolTotal': tools.length,
    'mappedScenarioCount': mapped.length,
    'mappedScenarios': mapped,
    'scenariosWithoutMcpTool': [
      for (final key in keys)
        if (!mapped.containsKey(key)) key,
    ],
    'mcpToolsWithoutScenario': tools.difference(coveredTools).toList()..sort(),
    if (mappingUnknown.isNotEmpty) 'mappingUnknownTools': mappingUnknown,
    'note':
        '写操作场景、页面渲染类场景没有 MCP 工具属正常；'
        'mcpToolsWithoutScenario 是需要补充探针（或本地计算/导航类本来就不发请求）的工具。',
  };
}

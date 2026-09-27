import 'package:mcp_dart/mcp_dart.dart';
import 'package:mtbbs/api/home/favorite/export.dart' as favorite;
import 'package:mtbbs/core/utils/database_helper.dart';
import 'package:mtbbs/mcp/mcp_types.dart';
import 'package:mtbbs/mcp/tools/mcp_tool_definition.dart';
import 'package:mtbbs/services/api_service.dart';

/// 与"个人数据"相关的工具，两组都**默认关闭**：
/// - `McpToolGroup.accountData`：需要登录的账号**私有**数据（目前只有收藏）
/// - `McpToolGroup.localData`：App 本地保存的浏览记录
///
/// 好友 / 关注 / 粉丝属于公开信息，已移到 `mcp_tools_user.dart`（默认开启）。
List<McpToolDefinition> savedTools() => [
  // ---------- 账号相关 ----------
  McpToolDefinition(
    name: 'list_my_favorites',
    group: McpToolGroup.accountData,
    description: '读取当前登录账号的收藏列表。需登录，且该能力默认关闭，可由用户在 App 中开启。',
    properties: {
      'page': JsonSchema.integer(
        minimum: 1,
        maximum: 200,
        description: '页码，默认 1',
      ),
    },
    run: (args) async {
      final page = McpArgs.integer(args, 'page', fallback: 1, min: 1, max: 200);
      return favorite.fetchFavorites(ApiService().dio, page: page);
    },
  ),

  // ---------- 本地浏览记录 ----------
  McpToolDefinition(
    name: 'get_browse_history',
    group: McpToolGroup.localData,
    description: '读取 App 本地保存的浏览记录（最近访问的帖子/用户）。该能力默认关闭，可由用户在 App 中开启。',
    properties: {
      'type': JsonSchema.string(
        description: '记录类型过滤：thread / user / mythread / reply，留空返回全部',
      ),
      'limit': JsonSchema.integer(
        minimum: 1,
        maximum: 200,
        description: '返回条数上限，默认 30',
      ),
    },
    network: false, // 读本地数据库浏览记录
    run: (args) async {
      final type = McpArgs.str(args, 'type');
      final limit = McpArgs.integer(
        args,
        'limit',
        fallback: 30,
        min: 1,
        max: 200,
      );
      final db = DatabaseHelper.instance;
      final all = type.isEmpty
          ? await db.getAllBrowseRecords()
          : await db.getBrowseRecordsByType(type);
      final records = all.take(limit).map((r) => r.toJson()).toList();
      return {'count': records.length, 'total': all.length, 'records': records};
    },
  ),
];

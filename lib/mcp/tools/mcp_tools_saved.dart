import 'package:mcp_dart/mcp_dart.dart';
import 'package:mtbbs/api/home/credit/export.dart' as credit;
import 'package:mtbbs/api/home/favorite/export.dart' as favorite;
import 'package:mtbbs/api/home/mypost/export.dart' as mypost;
import 'package:mtbbs/api/home/notice/export.dart' as notice;
import 'package:mtbbs/core/utils/database_helper.dart';
import 'package:mtbbs/mcp/mcp_types.dart';
import 'package:mtbbs/mcp/tools/mcp_payloads.dart';
import 'package:mtbbs/mcp/tools/mcp_tool_definition.dart';
import 'package:mtbbs/services/api_service.dart';

/// 与"个人数据"相关的工具，两组都**默认关闭**：
/// - `McpToolGroup.accountData`：需要登录的账号**私有**数据（收藏 / 积分记录 / 提醒）
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
  McpToolDefinition(
    name: 'list_credit_log',
    group: McpToolGroup.accountData,
    description: '读取当前登录账号的积分变更记录（分页）。该能力默认关闭，可由用户在 App 中开启。',
    properties: {
      'page': JsonSchema.integer(
        minimum: 1,
        maximum: 200,
        description: '页码，默认 1',
      ),
      'exttype': JsonSchema.string(
        description: '积分类型：1=好评 / 2=金币 / 3=信誉，留空=不限',
      ),
      'optype': JsonSchema.string(
        description: '操作类型代码（如 PRC=帖子被评分），留空=不限',
      ),
    },
    run: (args) async {
      final page = McpArgs.integer(args, 'page', fallback: 1, min: 1, max: 200);
      final exttype = McpArgs.str(args, 'exttype');
      final optype = McpArgs.str(args, 'optype');
      final result = await credit.fetchCreditLog(
        ApiService().dio,
        page: page,
        exttype: exttype.isEmpty ? '0' : exttype,
        optype: optype,
      );
      return McpPayloads.creditLog(result);
    },
  ),
  McpToolDefinition(
    name: 'list_notifications',
    group: McpToolGroup.accountData,
    description:
        '读取当前登录账号的提醒（分页）。view：system 系统提醒 / manage 管理提醒 / '
        'interactive 坛友互动 / mypost 帖子提醒。该能力默认关闭，可由用户在 App 中开启。',
    properties: {
      'view': JsonSchema.string(
        description: '视图，默认 system',
        enumValues: const ['system', 'manage', 'interactive', 'mypost'],
      ),
      'page': JsonSchema.integer(
        minimum: 1,
        maximum: 200,
        description: '页码，默认 1',
      ),
    },
    run: (args) async {
      final view = McpArgs.str(args, 'view', fallback: 'system');
      final page = McpArgs.integer(args, 'page', fallback: 1, min: 1, max: 200);
      final result = view == 'mypost'
          ? await mypost.getMypostList(ApiService().dio, page: page, type: 'post')
          : await notice.getNoticeList(ApiService().dio, page: page, view: view);
      return McpPayloads.notifications(result, view: view);
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

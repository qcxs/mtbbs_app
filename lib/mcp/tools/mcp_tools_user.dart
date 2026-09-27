import 'package:mcp_dart/mcp_dart.dart';
import 'package:mtbbs/api/home/follow/export.dart' as follow;
import 'package:mtbbs/api/home/friend/export.dart' as friend;
import 'package:mtbbs/api/home/mythread/export.dart' as mythread;
import 'package:mtbbs/mcp/mcp_types.dart';
import 'package:mtbbs/mcp/tools/mcp_payloads.dart';
import 'package:mtbbs/mcp/tools/mcp_tool_definition.dart';
import 'package:mtbbs/services/api_service.dart';

/// 用户维度工具（`McpToolGroup.publicData`）—— "看某个人"的三个面：
/// 他发过什么（主题/回复）、他的好友、他的关注与粉丝。
///
/// 三者都**支持 uid**：省略 `uid` = 当前登录账号，填了就看该用户。
/// 配合 `get_user_profile` 即可支撑「总结某个账号是什么样的人」这类任务。
///
/// 注意：能否看到**他人**的列表取决于站点隐私设置。被限制时 payload 会带
/// `privacyBlocked: true` 或 `loginRequired: true`，而不是返回空列表——
/// 这样 AI 才能区分"没有数据"和"没权限"。
List<McpToolDefinition> userTools() => [
  McpToolDefinition(
    name: 'list_user_threads',
    group: McpToolGroup.publicData,
    description:
        '列出某个用户的主题或回复（uid 省略 = 当前登录账号）。'
        'type: thread 他发的主题 / reply 他的回复。'
        '配合 get_user_profile 可判断"这人平时都在聊什么/关心什么"。'
        '注意：该接口每页只返回最近一批、**不提供总页数**，'
        '需要更多时把 page 递增继续取，直到返回 count=0。',
    properties: {
      'uid': JsonSchema.string(description: '用户 UID；省略则为当前登录账号'),
      'type': JsonSchema.string(
        description: 'thread 主题 / reply 回复，默认 thread',
        enumValues: const ['thread', 'reply'],
      ),
      'page': JsonSchema.integer(
        minimum: 1,
        maximum: 200,
        description: '页码，默认 1',
      ),
    },
    run: (args) async {
      final uid = McpArgs.str(args, 'uid');
      final type = McpArgs.str(args, 'type', fallback: 'thread');
      final page = McpArgs.integer(args, 'page', fallback: 1, min: 1, max: 200);
      final result = await mythread.getMyThreads(
        ApiService().dio,
        uid: uid.isEmpty ? null : uid,
        type: type,
        page: page,
      );
      return McpPayloads.threadList(
        result,
        extra: {'uid': uid.isEmpty ? 'self' : uid, 'type': type},
      );
    },
  ),
  McpToolDefinition(
    name: 'list_user_friends',
    group: McpToolGroup.publicData,
    description: '列出某个用户的好友（uid 省略 = 当前登录账号）。',
    properties: {
      'uid': JsonSchema.string(description: '用户 UID；省略则为当前登录账号'),
      'page': JsonSchema.integer(
        minimum: 1,
        maximum: 200,
        description: '页码，默认 1',
      ),
    },
    run: (args) async {
      final uid = McpArgs.str(args, 'uid');
      final page = McpArgs.integer(args, 'page', fallback: 1, min: 1, max: 200);
      final result = await friend.getFriendList(
        ApiService().dio,
        uid: uid,
        page: page,
      );
      return McpPayloads.userList(
        result,
        extra: {'uid': uid.isEmpty ? 'self' : uid},
      );
    },
  ),
  McpToolDefinition(
    name: 'list_user_follows',
    group: McpToolGroup.publicData,
    description:
        '列出某个用户的关注或粉丝（uid 省略 = 当前登录账号）。'
        'type: following 他关注的人 / follower 他的粉丝。',
    properties: {
      'uid': JsonSchema.string(description: '用户 UID；省略则为当前登录账号'),
      'type': JsonSchema.string(
        description: 'following 关注 / follower 粉丝，默认 following',
        enumValues: const ['following', 'follower'],
      ),
      'page': JsonSchema.integer(
        minimum: 1,
        maximum: 200,
        description: '页码，默认 1',
      ),
    },
    run: (args) async {
      final uid = McpArgs.str(args, 'uid');
      final type = McpArgs.str(args, 'type', fallback: 'following');
      final page = McpArgs.integer(args, 'page', fallback: 1, min: 1, max: 200);
      final result = await follow.getFollowList(
        ApiService().dio,
        type: type,
        uid: uid,
        page: page,
      );
      return McpPayloads.userList(
        result,
        extra: {'uid': uid.isEmpty ? 'self' : uid, 'type': type},
      );
    },
  ),
];

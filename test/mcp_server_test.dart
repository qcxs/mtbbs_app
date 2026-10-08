import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:mtbbs/core/app/site_store.dart';
import 'package:mtbbs/mcp/mcp_authenticator.dart';
import 'package:mtbbs/mcp/mcp_sanitizer.dart';
import 'package:mtbbs/mcp/mcp_types.dart';
import 'package:mtbbs/mcp/tools/mcp_payloads.dart';
import 'package:mtbbs/mcp/tools/mcp_tool_registry.dart';

/// MCP 服务端链路验证：真实起一个本机 Streamable HTTP 服务，用 SDK 客户端连上去。
///
/// 覆盖：鉴权（生产实现 McpAuthenticator，含多令牌与空列表）、
/// tools/list、能力开关语义、工具调用、脱敏规则。
/// 不覆盖需要联网的论坛工具（那些由 App 内「连通性测试」按钮覆盖）。
void main() {
  const tokenA = 'unit-test-token-a';
  const tokenB = 'unit-test-token-b';
  const tokenList = [tokenA, tokenB];

  StreamableMcpServer buildServer({
    bool Function(McpToolGroup)? isGroupEnabled,
    List<String> tokens = tokenList,
  }) => StreamableMcpServer(
    serverFactory: (_) => McpToolRegistry.createServer(
      isGroupEnabled: isGroupEnabled ?? (_) => true,
      accountInfo: () => const McpAccountInfo.guest(),
    ),
    host: '127.0.0.1',
    port: 0,
    path: '/mcp',
    enableDnsRebindingProtection: true,
    allowedHosts: const {'127.0.0.1', 'localhost'},
    allowedOrigins: const {'http://127.0.0.1', 'http://localhost'},
    enableJsonResponse: true,
    // 直接用生产鉴权实现，测试即覆盖真实路径
    authenticator: (request) => McpAuthenticator.authorize(request, tokens),
  );

  McpClient buildClient() =>
      McpClient(Implementation(name: 'mtbbs-test-client', version: '1.0.0'));

  StreamableHttpClientTransport transportFor(int port, {String? bearer}) =>
      StreamableHttpClientTransport(
        Uri.parse('http://127.0.0.1:$port/mcp'),
        opts: StreamableHttpClientTransportOptions(
          requestInit: {
            if (bearer != null) 'headers': {'Authorization': 'Bearer $bearer'},
          },
        ),
      );

  setUpAll(() {
    SiteStore.instance.init();
    SiteStore.instance.replaceForums({'2': '测试版块', '39': '逆向工程'});
  });

  group('鉴权', () {
    late StreamableMcpServer server;
    late int port;

    setUp(() async {
      server = buildServer();
      await server.start();
      port = server.boundPort;
    });

    tearDown(() async {
      await server.stop();
    });

    Future<void> expectRejected({String? bearer, List<String>? tokens}) async {
      // tokens 非空时换一个只认这些令牌的服务
      var activePort = port;
      StreamableMcpServer? extra;
      if (tokens != null) {
        extra = buildServer(tokens: tokens);
        await extra.start();
        activePort = extra.boundPort;
      }
      final client = buildClient();
      try {
        await expectLater(() async {
          await client.connect(transportFor(activePort, bearer: bearer));
          await client.listTools();
        }, throwsA(anything));
      } finally {
        await client.close();
        await extra?.stop();
      }
    }

    test('无令牌必须失败', () => expectRejected());

    test('错误令牌必须失败', () => expectRejected(bearer: 'wrong-token'));

    test('令牌列表为空时一律拒绝', () => expectRejected(tokens: []));

    test('令牌列表中的任意一个都能通过', () async {
      for (final bearer in tokenList) {
        final client = buildClient();
        await client.connect(transportFor(port, bearer: bearer));
        final tools = await client.listTools();
        expect(tools.tools, isNotEmpty);
        await client.close();
      }
    });
  });

  group('工具表与只读约束', () {
    late StreamableMcpServer server;
    late int port;

    setUp(() async {
      server = buildServer();
      await server.start();
      port = server.boundPort;
    });

    tearDown(() async {
      await server.stop();
    });

    test('可列出全部只读工具，且不含写操作', () async {
      final client = buildClient();
      await client.connect(transportFor(port, bearer: tokenA));
      final tools = await client.listTools();
      final names = tools.tools.map((t) => t.name).toSet();

      expect(names, contains('get_app_info'));
      expect(names, contains('list_forums'));
      expect(names, contains('get_thread_detail'));
      expect(names, contains('search_forum_threads'));
      expect(names, contains('get_editor_draft'));
      expect(names, contains('list_my_favorites'));
      // 用户维度（都支持 uid）与首次使用引导
      expect(names, contains('help'));
      expect(names, contains('list_user_threads'));
      expect(names, contains('list_user_friends'));
      expect(names, contains('list_user_follows'));

      // 只读断言 ①：每个工具的注解都必须声明 readOnlyHint
      for (final tool in tools.tools) {
        expect(
          tool.annotations?.readOnlyHint,
          isTrue,
          reason: '工具未声明只读: ${tool.name}',
        );
      }

      // 只读断言 ②：不得出现任何写操作工具名
      const forbidden = {
        'post_thread',
        'reply_thread',
        'edit_post',
        'add_favorite',
        'delete_favorite',
        'rate_thread',
        'recommend_thread',
        'send_private_message',
      };
      expect(names.intersection(forbidden), isEmpty);
      await client.close();
    });

    test('调用 list_forums 返回站点版块', () async {
      final client = buildClient();
      await client.connect(transportFor(port, bearer: tokenA));
      final result = await client.callTool(
        CallToolRequest(name: 'list_forums', arguments: const {}),
      );

      expect(result.isError, isFalse);
      final text = (result.content.first as TextContent).text;
      expect(text, contains('测试版块'));
      expect(text, contains(SiteStore.instance.host));
      await client.close();
    });

    test('调用 get_app_info 返回游客态且不含凭据键', () async {
      final client = buildClient();
      await client.connect(transportFor(port, bearer: tokenA));
      final result = await client.callTool(
        CallToolRequest(name: 'get_app_info', arguments: const {}),
      );

      expect(result.isError, isFalse);
      final text = (result.content.first as TextContent).text;
      expect(text, contains('"isLoggedIn":false'));
      expect(text, isNot(contains('cookie')));
      expect(text, isNot(contains('formhash')));
      expect(text, isNot(contains('token')));
      await client.close();
    });

    test('调用 help 返回使用指南与场景组合', () async {
      final client = buildClient();
      await client.connect(transportFor(port, bearer: tokenA));
      final result = await client.callTool(
        CallToolRequest(name: 'help', arguments: const {}),
      );

      expect(result.isError, isFalse);
      final text = (result.content.first as TextContent).text;
      // 覆盖典型任务，并指向用户维度工具与隐私受限的语义
      expect(text, contains('scenarios'));
      expect(text, contains('list_user_threads'));
      expect(text, contains('privacyBlocked'));
      await client.close();
    });
  });

  group('能力开关', () {
    late StreamableMcpServer server;
    late int port;

    setUp(() async {
      // 关掉「账号相关数据」和「本地浏览记录」
      server = buildServer(
        isGroupEnabled: (g) =>
            g != McpToolGroup.accountData && g != McpToolGroup.localData,
      );
      await server.start();
      port = server.boundPort;
    });

    tearDown(() async {
      await server.stop();
    });

    test('关闭的分组仍在工具列表里（客户端缓存不失效）', () async {
      final client = buildClient();
      await client.connect(transportFor(port, bearer: tokenA));
      final names = (await client.listTools()).tools.map((t) => t.name).toSet();

      expect(names, contains('list_my_favorites'));
      expect(names, contains('list_user_follows'));
      expect(names, contains('get_browse_history'));
      await client.close();
    });

    test('调用关闭分组的能力会被拒绝并提示如何开启', () async {
      final client = buildClient();
      await client.connect(transportFor(port, bearer: tokenA));
      final result = await client.callTool(
        CallToolRequest(name: 'list_my_favorites', arguments: const {}),
      );

      expect(result.isError, isTrue);
      final text = (result.content.first as TextContent).text;
      expect(text, contains('已在 App 中关闭'));
      expect(text, contains(McpToolGroup.accountData.label));
      await client.close();
    });

    test('未受影响的分组仍可用', () async {
      final client = buildClient();
      await client.connect(transportFor(port, bearer: tokenA));
      final result = await client.callTool(
        CallToolRequest(name: 'list_forums', arguments: const {}),
      );
      expect(result.isError, isFalse);
      await client.close();
    });
  });

  group('McpSanitizer', () {
    test('剥离凭据 / IP / 写操作入口，保留公开字段', () {
      final input = {
        'formhash': 'abc123',
        'cookie': 'sid=1',
        'registerIp': '1.2.3.4',
        'lastvisitip': '5.6.7.8',
        'realName': '张三',
        'qq': '123456',
        'followUrl': '/home.php?mod=spacecp&formhash=abc123',
        'ipLocation': '来自 江苏',
        'username': 'someone',
        'nested': {
          'pageData': {'formhash': 'x'},
          'content': '看这个链接 /forum.php?mod=post&formhash=deadbeef&action=new',
        },
      };

      final out = McpSanitizer.sanitize(input) as Map<String, dynamic>;

      expect(out.containsKey('formhash'), isFalse);
      expect(out.containsKey('cookie'), isFalse);
      expect(out.containsKey('registerIp'), isFalse);
      expect(out.containsKey('lastvisitip'), isFalse);
      expect(out.containsKey('realName'), isFalse);
      expect(out.containsKey('qq'), isFalse);
      expect(out.containsKey('followUrl'), isFalse);
      // 公开字段保留
      expect(out['ipLocation'], '来自 江苏');
      expect(out['username'], 'someone');

      final nested = out['nested'] as Map<String, dynamic>;
      expect(nested.containsKey('pageData'), isFalse);
      // 文本里残留的 formhash 参数被擦除
      expect(nested['content'], isNot(contains('deadbeef')));
      expect(nested['content'], contains('[已隐去]'));
    });

    test('clampText 超长截断', () {
      final long = 'x' * 100;
      expect(McpSanitizer.clampText(long, 10).startsWith('x' * 10), isTrue);
      expect(McpSanitizer.clampText(long, 10), contains('已截断'));
      expect(McpSanitizer.clampText('short', 10), 'short');
    });
  });

  group('正文精简（省 AI 上下文）', () {
    test('默认剔除样式标签，但保留删除线与内容标签', () {
      final raw = {
        'bbcode': '[b]标题[/b][color=red]红字[/color][s]作废[/s][quote]引用[/quote]',
      };
      final out = McpPayloads.post(raw);
      expect(out['bbcode'], '标题红字[s]作废[/s][quote]引用[/quote]');
    });

    test('full_bbcode=true 返回完整原文', () {
      const source = '[b]标题[/b][color=red]红字[/color][s]作废[/s]';
      final out = McpPayloads.post({'bbcode': source}, fullBbcode: true);
      expect(out['bbcode'], source);
    });
  });

  group('超长正文分片（可续读）', () {
    test('超出 maxChars：返回片段 + 总长 + bbcodeNextOffset', () {
      final source = 'a' * 100;
      final out = McpPayloads.post({'bbcode': source}, maxChars: 30);
      expect(out['bbcodeTotalChars'], 100);
      expect(out['bbcodeNextOffset'], 30);
      expect(out['bbcode'], startsWith('a' * 30));
      expect(out['bbcode'], contains('bbcode_offset=30'));
    });

    test('带 offset 续读拿到后续片段，末片无 bbcodeNextOffset', () {
      const source = 'abcdefghij';
      final mid = McpPayloads.post({'bbcode': source}, offset: 4, maxChars: 3);
      expect(mid['bbcode'], startsWith('efg'));
      expect(mid['bbcodeNextOffset'], 7);
      final last = McpPayloads.post({'bbcode': source}, offset: 7, maxChars: 3);
      expect(last['bbcode'], 'hij');
      expect(last.containsKey('bbcodeNextOffset'), isFalse);
    });

    test('offset 超出总长：返回空片段且不报错', () {
      final out = McpPayloads.post({'bbcode': 'abc'}, offset: 99, maxChars: 10);
      expect(out['bbcode'], '');
      expect(out.containsKey('bbcodeNextOffset'), isFalse);
    });

    test('偏移量作用于精简后的文本（与 full_bbcode 口径一致）', () {
      const source = '[b]ab[/b]cd'; // 精简后为 abcd
      final out = McpPayloads.post({'bbcode': source}, offset: 2, maxChars: 10);
      expect(out['bbcode'], 'cd');
      expect(out['bbcodeTotalChars'], 4);
    });
  });

  group('帖子详情：分片续读指引', () {
    test('楼层正文被分片时，note 给出 bbcode_offset 续读方法', () {
      final result = {
        'tid': '1',
        'posts': [
          {'pid': 'p1', 'bbcode': 'x' * 50},
        ],
      };
      final out = McpPayloads.threadDetail(
        result,
        tid: '1',
        maxPosts: 10,
        maxChars: 20,
      );
      expect(out['bbcodeMode'], 'slim');
      expect(out['note'], contains('bbcode_offset'));
    });

    test('楼层数被截断时，note 仍指引 max_posts / 翻页', () {
      final result = {
        'tid': '1',
        'posts': [
          {'pid': 'p1', 'bbcode': 'short'},
          {'pid': 'p2', 'bbcode': 'short'},
        ],
      };
      final out = McpPayloads.threadDetail(result, tid: '1', maxPosts: 1);
      expect(out['truncated'], isTrue);
      expect(out['note'], contains('max_posts'));
    });
  });
}

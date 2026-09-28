import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtbbs/api/forum/viewthread/detail/parse.dart' as detail;
import 'package:mtbbs/services/api_service.dart';
import 'api_bootstrap.dart';

/// 抓取真实帖子详情页 → 生成解析契约测试样本。
///
/// **产物是站点数据，不进版本库**：写在 `build/fixtures/`（已被 `.gitignore`
/// 的 `/build/` 覆盖）。仓库里只保留"从哪个 URL 抓"这一份信息，需要时重新抓。
///
/// 用法：
/// ```powershell
/// flutter test tool/capture_fixture_test.dart --dart-define=tid=170313
/// # 需登录的版块追加：--dart-define=account=<账号名>
/// ```
///
/// 为什么不用探针 `debug.http`：长正文会被截断（maxStr 100K），抓不到完整页面。
///
/// 抓完请人工过一眼，再跑 `flutter test test/parser_contract_test.dart` 确认契约。
/// 页面结构有意变更时才重抓；**不要为了让测试通过而改样本内容**。
void main() {
  test('capture thread detail fixture', () async {
    const tid = String.fromEnvironment('tid', defaultValue: '170313');
    const account = String.fromEnvironment('account', defaultValue: '');
    const outPath = 'build/fixtures/mt_thread_detail.html';

    await bootstrap(account: account, site: '', baseUrl: '', siteName: '');

    final resp = await ApiService().dio.get<String>(
      '/forum.php?mod=viewthread&tid=$tid&page=1',
    );
    final body = resp.data ?? '';

    // 落盘前先自检，避免抓到登录页/错误页把好样本覆盖掉
    final looksLikeThreadPage =
        resp.statusCode == 200 &&
        body.contains('id="postlist"') &&
        RegExp(r'<table[^>]+id="pid').hasMatch(body) &&
        body.length > 50000;
    if (!looksLikeThreadPage) {
      print(
        'CAPTURE ABORTED status=${resp.statusCode} chars=${body.length} '
        '—— 不像帖子详情页，未覆盖样本',
      );
      return;
    }

    // 抓完顺手跑一遍解析，确认这份样本是"能过契约"的
    final r = detail.parseResponse(body, resp.statusCode!, page: 1);
    final main = r['mainPost'] as Map<String, dynamic>?;
    final posts = (r['posts'] as List?) ?? const [];

    final header =
        '<!--\n'
        '  站点样本（MT 论坛 PC 模板帖子详情页）— 供 test/parser_contract_test.dart 做契约测试。\n'
        '\n'
        '  来源：${_sourceUrl(tid)}（游客态抓取，未裁剪）\n'
        '\n'
        '  注意：这是**站点数据**，不是代码/测试资产，不要提交到版本库。\n'
        '    它落在 build/fixtures/（.gitignore 已覆盖），需要时用上面的命令重抓。\n'
        '\n'
        '  维护约定：本文件是**冻结样本**，不要为了让测试通过而改内容；\n'
        '  只有线上页面结构确实变化时才重抓，并 Review diff。\n'
        '-->';

    Directory('build/fixtures').createSync(recursive: true);
    File(outPath).writeAsStringSync('$header\n$body');
    print('CAPTURED → $outPath (${body.length} chars)');
    print(
      'PARSE success=${r['success']} tid=${r['tid']} title=${r['title']} '
      'mainPid=${main?['pid']} mainUser=${main?['username']} '
      'posts=${posts.length} health=${r['_health']}',
    );
  });
}

/// 样本来源 URL —— 仓库里唯一保留的"站点数据"（只是一个地址，无内容）
String _sourceUrl(String tid) =>
    '${ApiService().dio.options.baseUrl}/forum.php?mod=viewthread&tid=$tid&page=1';

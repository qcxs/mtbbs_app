/// 写操作场景：发帖（fid）/ 评论与回复评论（tid+reppid）/ 修改帖子与评论（tid+pid）/ 删除收藏（favid）
library;

import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:mtbbs/api/forum/post/export.dart' as post_api;
import 'package:mtbbs/api/forum/post/http.dart' as post_http;
import 'package:mtbbs/api/forum/viewthread/action/export.dart' as rate_api;
import 'package:mtbbs/api/home/favorite/export.dart' as favorite_api;
import 'package:mtbbs/core/app/site_store.dart';
import 'package:mtbbs/services/api_service.dart';
import 'scenario_types.dart';

/// 写操作场景注册表（命令名 → 场景）
///
/// 通用流程：GET 页面提取 formhash（CSRF）/posttime → POST + form-urlencoded。
/// 详见 docs/12-写操作API文档.md。
final Map<String, ApiScenario> writeScenarios = {
  'post.reply': ApiScenario(
    desc: '评论/回复帖子（写操作！需登录；自动拉取回复页提取 formhash/posttime 后提交）',
    params: {
      'tid': '*主题 ID',
      'message': '*内容',
      'reppid': '回复的评论 ID（可空；评论帖子=空，回复某条评论=其 pid）',
      'fid': '版块 ID（可空；Discuz 由 tid 推导，一般无需传入）',
    },
    needsLogin: true,
    run: (a) async {
      final dio = ApiService().dio;
      final tid = a['tid'] ?? '';
      final message = a['message'] ?? '';
      final reppid = a['reppid'] ?? '';
      if (tid.isEmpty) throw Exception('缺少必填参数 tid');
      if (message.isEmpty) throw Exception('缺少必填参数 message');

      // 1. 拉取回复页（回复某评论时带 repquote），提取 formhash/posttime
      final resp = await post_http.getReplyPage(
        dio,
        tid: tid,
        repquote: reppid.isEmpty ? null : reppid,
      );
      final doc = html_parser.parse(resp.data ?? '');
      String val(String name) =>
          doc.querySelector('input[name="$name"]')?.attributes['value'] ?? '';
      final formhash = val('formhash');
      final posttime = val('posttime');
      // fid 可选：Discuz 回复由 tid 推导 fid，空 fid（fid=）与无 fid 效果相同
      final fid = a['fid'] ?? '';
      if (formhash.isEmpty) {
        return {'success': false, 'message': '回复页未提取到 formhash（可能未登录或该版块禁止回复）'};
      }

      // 2. 提交（reppid 非空 = 回复该条评论）
      final r = await post_api.submitReply(
        dio,
        fid: fid,
        tid: tid,
        formhash: formhash,
        posttime: posttime,
        message: message,
        reppid: reppid.isEmpty ? null : reppid,
      );
      return {
        'success': r.success,
        'message': r.message,
        'tid': r.tid,
        'pid': r.pid,
        'needsApproval': r.needsApproval,
      };
    },
  ),
  'post.new': ApiScenario(
    desc: '发布新帖（写操作！需登录；自动拉取发帖页提取 formhash/posttime 后提交）',
    params: {'fid': '*版块 ID', 'subject': '*标题', 'message': '*内容'},
    needsLogin: true,
    run: (a) async {
      final dio = ApiService().dio;
      final fid = a['fid'] ?? '';
      final subject = a['subject'] ?? '';
      final message = a['message'] ?? '';
      if (fid.isEmpty) throw Exception('缺少必填参数 fid');
      if (subject.isEmpty) throw Exception('缺少必填参数 subject');
      if (message.isEmpty) throw Exception('缺少必填参数 message');

      // 1. 拉取发帖页，提取 formhash/posttime
      final resp = await post_http.getNewThreadPage(dio, fid: fid);
      final doc = html_parser.parse(resp.data ?? '');
      String val(String name) =>
          doc.querySelector('input[name="$name"]')?.attributes['value'] ?? '';
      final formhash = val('formhash');
      final posttime = val('posttime');
      if (formhash.isEmpty) {
        return {'success': false, 'message': '发帖页未提取到 formhash（可能未登录或该版块禁止发帖）'};
      }

      // 2. 提交
      final r = await post_api.submitNewPost(
        dio,
        fid: fid,
        formhash: formhash,
        posttime: posttime,
        subject: subject,
        message: message,
      );
      return {
        'success': r.success,
        'message': r.message,
        'tid': r.tid,
        'pid': r.pid,
        'needsApproval': r.needsApproval,
      };
    },
  ),
  'post.edit': ApiScenario(
    desc:
        '修改帖子/评论（写操作！需登录；tid+pid 定位，pid=楼主的 pid 即改帖子；'
        '自动拉取编辑页提取 formhash/posttime 后提交）',
    params: {
      'tid': '*主题 ID',
      'pid': '*帖子/评论 ID（楼主的 pid 即改帖子本体）',
      'message': '*新内容',
      'subject': '标题（改楼主帖时生效，评论可空）',
      'fid': '版块 ID（可空；Discuz 由 tid 推导）',
    },
    needsLogin: true,
    run: (a) async {
      final dio = ApiService().dio;
      final tid = a['tid'] ?? '';
      final pid = a['pid'] ?? '';
      final message = a['message'] ?? '';
      final subject = a['subject'] ?? '';
      final fid = a['fid'] ?? '';
      if (tid.isEmpty) throw Exception('缺少必填参数 tid');
      if (pid.isEmpty) throw Exception('缺少必填参数 pid');
      if (message.isEmpty) throw Exception('缺少必填参数 message');

      // 1. 拉取编辑页，提取 formhash/posttime/fid
      final pageUri = Uri.parse(
        SiteStore.instance.baseUrl,
      ).resolve('/forum.php?mod=post&action=edit&fid=$fid&tid=$tid&pid=$pid');
      final resp = await dio.get<String>(pageUri.toString());
      final doc = html_parser.parse(resp.data ?? '');
      String val(String name) =>
          doc.querySelector('input[name="$name"]')?.attributes['value'] ?? '';
      final formhash = val('formhash');
      final posttime = val('posttime');
      final realFid = fid.isNotEmpty ? fid : val('fid');
      if (formhash.isEmpty) {
        return {'success': false, 'message': '编辑页未提取到 formhash（可能未登录或无权限编辑）'};
      }

      // 2. 提交编辑（Discuz 编辑返回 301/302 跳转 viewthread 表示成功）
      final editResp = await dio.post<String>(
        '/forum.php?mod=post&action=edit&fid=$realFid&tid=$tid&pid=$pid'
        '&editsubmit=yes&inajax=1&formhash=$formhash',
        options: Options(
          headers: {'Content-Type': Headers.formUrlEncodedContentType},
          followRedirects: false,
        ),
        data: {
          'formhash': formhash,
          'posttime': posttime,
          'subject': subject,
          'message': message,
          'fid': realFid,
          'tid': tid,
          'pid': pid,
          'page': '1',
          'editsubmit': 'yes',
        },
      );
      final code = editResp.statusCode;
      final location = (editResp.headers.value('location') ?? '').trim();
      final body = editResp.data is String ? (editResp.data as String) : '';
      if (code == 301 || code == 302) {
        final ok = location.contains('viewthread');
        return {
          'success': ok,
          'message': ok ? '编辑成功' : '编辑后重定向异常: $location',
          'redirect': location,
        };
      }
      final errorMatch = RegExp(
        r'(抱歉|错误|失败|小于|限制|禁止|不能|非法|无权|权限)',
      ).firstMatch(body);
      if (errorMatch != null) {
        final start = body.indexOf(errorMatch.group(0)!);
        final snippet = body.substring(start, start + 60);
        final cleanMsg = snippet.replaceAll(RegExp(r'<[^>]+>'), '').trim();
        return {'success': false, 'message': cleanMsg};
      }
      final needsApproval = body.contains('审核') || body.contains('审核中');
      return {
        'success': !needsApproval,
        'message': needsApproval ? '编辑成功，等待审核' : '编辑成功',
        'needsApproval': needsApproval,
      };
    },
  ),
  'favorite.add': ApiScenario(
    desc: '收藏帖子（写操作！需登录；支持备注；自动从帖子页联动提取 formhash 后提交）',
    params: {'tid': '*主题 ID', 'note': '备注（可空；来自手机端收藏表单的 description 字段）'},
    needsLogin: true,
    run: (a) {
      final tid = a['tid'] ?? '';
      if (tid.isEmpty) throw Exception('缺少必填参数 tid');
      final note = a['note'] ?? '';
      return favorite_api.addFavorite(ApiService().dio, tid: tid, note: note);
    },
  ),
  'score.form': ApiScenario(
    desc: '解析评分弹窗（写操作前奏！需登录；GET 评分表单并解析字段/区间/剩余/理由/通知）',
    params: {'tid': '*主题 ID', 'pid': '*帖子/评论 ID（楼主 pid 即评帖子，评论 pid 评评论）'},
    needsLogin: true,
    run: (a) async {
      final dio = ApiService().dio;
      final tid = a['tid'] ?? '';
      final pid = a['pid'] ?? '';
      if (tid.isEmpty) throw Exception('缺少必填参数 tid');
      if (pid.isEmpty) throw Exception('缺少必填参数 pid');

      final rateUrl = '/forum.php?mod=misc&action=rate&tid=$tid&pid=$pid';
      final form = await rate_api.fetchRateDialog(dio, rateUrl);
      return {
        'tid': form.tid,
        'pid': form.pid,
        'action': form.action,
        'items': form.items
            .map(
              (i) => {
                'name': i.name,
                'inputName': i.inputName,
                'min': i.min,
                'max': i.max,
                'todayRemaining': i.todayRemaining,
                'options': i.options,
              },
            )
            .toList(),
        'reasonOptions': form.reasonOptions,
        'hasNotifyAuthor': form.hasNotifyAuthor,
        // 极端情况：所有字段无可评正值（区间 max<=0 且可选值无正数）→ 今日评分额度用完
        'exhausted':
            form.items.isNotEmpty &&
            form.items.every(
              (i) =>
                  i.max <= 0 &&
                  !i.options.any(
                    (o) => (int.tryParse(o.replaceAll('+', '')) ?? 0) > 0,
                  ),
            ),
      };
    },
  ),
  'score.submit': ApiScenario(
    desc: '提交评分（写操作！需登录；自动从评分弹窗联动提取 formhash 后提交）',
    params: {
      'tid': '*主题 ID',
      'pid': '*帖子/评论 ID（楼主 pid 即评帖子，评论 pid 评评论）',
      'scores': '评分值，k=v 逗号分隔，如 score2=5,score1=1',
      'reason': '评分理由（可空；不传则用弹窗第一个可选理由）',
      'notify': '通知作者，1 或 0（默认 1）',
    },
    needsLogin: true,
    run: (a) async {
      final dio = ApiService().dio;
      final tid = a['tid'] ?? '';
      final pid = a['pid'] ?? '';
      if (tid.isEmpty) throw Exception('缺少必填参数 tid');
      if (pid.isEmpty) throw Exception('缺少必填参数 pid');

      // 1. GET 评分弹窗，联动提取 formhash/tid/pid/action
      final rateUrl = '/forum.php?mod=misc&action=rate&tid=$tid&pid=$pid';
      final form = await rate_api.fetchRateDialog(dio, rateUrl);
      if (form.items.isNotEmpty &&
          form.items.every(
            (i) =>
                i.max <= 0 &&
                !i.options.any(
                  (o) => (int.tryParse(o.replaceAll('+', '')) ?? 0) > 0,
                ),
          )) {
        return {'success': false, 'message': '今日评分额度已用完'};
      }

      // 2. 构造提交数据
      final data = <String, dynamic>{
        'formhash': form.formhash,
        'tid': form.tid,
        'pid': form.pid,
        'handlekey': 'rate',
      };
      final scores = <String, String>{};
      for (final pair in (a['scores'] ?? '').split(',')) {
        final idx = pair.indexOf('=');
        if (idx > 0) {
          scores[pair.substring(0, idx).trim()] = pair
              .substring(idx + 1)
              .trim();
        }
      }
      for (final item in form.items) {
        data[item.inputName] = scores[item.inputName] ?? '0';
      }
      final reason = a['reason'] ?? '';
      if (reason.isNotEmpty) {
        data['reason'] = reason;
      } else if (form.reasonOptions.isNotEmpty) {
        data['reason'] = form.reasonOptions.first;
      }
      if (form.hasNotifyAuthor) {
        data['sendreasonpm'] = a['notify'] == '0' ? '0' : 'on';
      }

      // 3. 提交
      final result = await rate_api.doRate(dio, form.action, data);
      return {'success': result.success, 'message': result.message};
    },
  ),
  'favorite.delete': ApiScenario(
    desc: '删除收藏（写操作！需登录；自动从收藏列表页联动提取 formhash 后提交）',
    params: {'favid': '*收藏 ID（favorite.list 返回的 favid）'},
    needsLogin: true,
    run: (a) {
      final favid = a['favid'] ?? '';
      if (favid.isEmpty) throw Exception('缺少必填参数 favid');
      return favorite_api.deleteFavorite(ApiService().dio, favid: favid);
    },
  ),
};

import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'package:mtbbs/core/page_fetcher.dart';
import 'package:mtbbs/core/xml_helper.dart';
import 'package:mtbbs/core/logger.dart';
import 'package:mtbbs/services/api_service.dart';
import 'package:mtbbs/api/forum/post/export.dart' as post_api;
import 'package:mtbbs/api/forum/viewthread/viewpid/export.dart' as viewpid_api;
import 'package:mtbbs/models/editor_snapshot.dart';
import 'package:mtbbs/widgets/bbcode_controller.dart';

/// 编辑器页面加载和提交逻辑
///
/// 封装 fetchPage, fetchQuotedPost, submit, submitEdit, parseAttachNew。
/// 注意：pageData 在每次调用 submit/submitEdit 时传入，不保存在构造函数中。
class EditorSubmitHelper {
  final BuildContext context;
  final EditorType editorType;
  final String widgetFid;
  final String widgetTid;
  final String widgetPid;
  final TextEditingController titleCtl;
  final BBCodeController contentCtl;
  final bool isEdit;
  final bool isPost;
  final bool isReply;

  EditorSubmitHelper({
    required this.context,
    required this.editorType,
    required this.widgetFid,
    required this.widgetTid,
    required this.widgetPid,
    required this.titleCtl,
    required this.contentCtl,
    required this.isEdit,
    required this.isPost,
    required this.isReply,
  });

  /// 构造编辑器页面 URL
  String _buildUrl() {
    final type = switch (editorType) {
      EditorType.post => 'post',
      EditorType.comment => 'comment',
      EditorType.reply => 'reply',
      EditorType.editPost => 'editPost',
      EditorType.editReply => 'editReply',
    };
    return PageFetcher.buildUrl(
      type: type,
      fid: widgetFid,
      tid: widgetTid,
      pid: widgetPid,
      repquote: isReply ? widgetPid : null,
    );
  }

  /// 拉取绑定的 Discuz 页面数据
  Future<PageFormData> fetchPage({bool preserveContent = false}) async {
    final url = _buildUrl();
    if (url.isEmpty) return const PageFormData(success: false, error: 'URL 为空');

    try {
      final resp = await ApiService().dio.get(url);
      final html = resp.data is String ? (resp.data as String) : '';
      final result = PageFetcher.parsePage(html, url: url);
      if (result.success) {
        AppLogger.i(
          'PAGE',
          'EditorPage loaded: type=${editorType.name}, formhash=${result.formhash}',
        );
      } else {
        AppLogger.w('PAGE', 'EditorPage error: ${result.error}');
      }
      return result;
    } catch (e) {
      final msg = e.toString();
      final cleanMsg = msg.startsWith('Exception: ') ? msg.substring(11) : msg;
      AppLogger.e('PAGE', 'EditorPage fetch failed: $cleanMsg');
      return PageFormData(
        success: false,
        error: cleanMsg.isEmpty ? '加载失败' : cleanMsg,
      );
    }
  }

  /// 获取被引用的帖子
  Future<Map<String, dynamic>?> fetchQuotedPost() async {
    try {
      final result = await viewpid_api.getPostByPid(
        ApiService().dio,
        tid: widgetTid,
        viewpid: widgetPid,
      );
      if (result['success'] == true && result['post'] != null) {
        return result['post'] as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      AppLogger.e('PAGE', 'fetchQuotedPost failed: $e');
      return null;
    }
  }

  /// 从内容中提取 [attachimg]{aid}[/attachimg] + [attach]{aid}[/attach] + 面板活跃 AID
  Map<String, String> parseAttachNew(String content) {
    final aids = RegExp(
      r'\[attachimg\](\d+)\[/attachimg\]',
    ).allMatches(content).map((m) => m.group(1)!).toSet();
    // 也提取 [attach]{aid}[/attach]
    aids.addAll(
      RegExp(
        r'\[attach\](\d+)\[/attach\]',
      ).allMatches(content).map((m) => m.group(1)!),
    );
    aids.addAll(contentCtl.pendingAids);
    if (aids.isEmpty) return const {};
    return {for (final aid in aids) 'attachnew[$aid][description]': ''};
  }

  /// 提交编辑
  Future<SubmitResult> submitEdit(
    PageFormData pageData,
    String title,
    String content, {
    Map<String, String> attachNew = const {},
  }) async {
    AppLogger.i(
      'EDITOR',
      jsonEncode({
        'action': 'submitEdit',
        'titleLen': title.length,
        'contentLen': content.length,
        'attachNew': attachNew.length,
        'fid': pageData.fid.isNotEmpty ? pageData.fid : widgetFid,
        'tid': pageData.tid.isNotEmpty ? pageData.tid : widgetTid,
        'pid': pageData.pid.isNotEmpty ? pageData.pid : widgetPid,
      }),
    );
    try {
      final editResp = await ApiService().dio.post(
        '/forum.php?mod=post&action=edit&fid=${pageData.fid.isNotEmpty ? pageData.fid : widgetFid}&tid=${pageData.tid.isNotEmpty ? pageData.tid : widgetTid}&pid=${pageData.pid.isNotEmpty ? pageData.pid : widgetPid}&editsubmit=yes&inajax=1&formhash=${pageData.formhash}',
        data: {
          'formhash': pageData.formhash,
          'posttime': pageData.posttime,
          'subject': title,
          'message': content,
          'fid': pageData.fid.isNotEmpty ? pageData.fid : widgetFid,
          'tid': pageData.tid.isNotEmpty ? pageData.tid : widgetTid,
          'pid': pageData.pid.isNotEmpty ? pageData.pid : widgetPid,
          'page': '1',
          'editsubmit': 'yes',
          ...attachNew,
        },
        options: Options(
          followRedirects: false,
          sendTimeout: const Duration(seconds: 60),
          receiveTimeout: const Duration(seconds: 60),
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            'X-Requested-With': 'XMLHttpRequest',
          },
        ),
      );

      final code = editResp.statusCode;
      final location = (editResp.headers.value('location') ?? '').trim();
      final body = editResp.data is String ? (editResp.data as String) : '';

      if (code == 301 || code == 302) {
        final ok = location.contains('viewthread');
        AppLogger.i(
          'EDITOR',
          jsonEncode({
            'action': 'submitEdit_redirect',
            'success': ok,
            'code': code,
            'location': location,
          }),
        );
        if (ok) {
          return const SubmitResult(success: true, message: '编辑成功');
        }
        return SubmitResult(success: false, message: '编辑后重定向异常: $location');
      }

      final errorMatch = RegExp(
        r'(抱歉|错误|失败|小于|限制|禁止|不能|非法|无权|权限)',
      ).firstMatch(body);
      if (errorMatch != null) {
        final start = body.indexOf(errorMatch.group(0)!);
        final snippet = body.substring(start, start + 60);
        final cleanMsg = snippet.replaceAll(RegExp(r'<[^>]+>'), '').trim();
        AppLogger.w(
          'EDITOR',
          jsonEncode({'action': 'submitEdit_error', 'error': cleanMsg}),
        );
        return SubmitResult(success: false, message: cleanMsg);
      }

      if (body.contains('审核') || body.contains('审核中')) {
        AppLogger.i(
          'EDITOR',
          jsonEncode({'action': 'submitEdit_approval', 'needsApproval': true}),
        );
        return const SubmitResult(
          success: true,
          message: '编辑成功，等待审核',
          needsApproval: true,
        );
      }
      AppLogger.i(
        'EDITOR',
        jsonEncode({'action': 'submitEdit_done', 'success': true}),
      );
      return const SubmitResult(success: true, message: '编辑成功');
    } catch (e) {
      AppLogger.e(
        'EDITOR',
        jsonEncode({'action': 'submitEdit_exception', 'error': e.toString()}),
      );
      return SubmitResult(success: false, message: '网络错误: $e');
    }
  }

  /// 统一提交入口
  Future<SubmitResult> submit(
    PageFormData pageData,
    String title,
    String content,
  ) async {
    final attachNew = parseAttachNew(content);

    AppLogger.i(
      'EDITOR',
      jsonEncode({
        'action': 'submit',
        'type': editorType.name,
        'titleLen': title.length,
        'contentLen': content.length,
        'attachNew': attachNew.length,
        'formhash': pageData.formhash.isNotEmpty,
      }),
    );

    switch (editorType) {
      case EditorType.post:
        return post_api.submitNewPost(
          ApiService().dio,
          fid: pageData.fid.isNotEmpty ? pageData.fid : widgetFid,
          formhash: pageData.formhash,
          posttime: pageData.posttime,
          subject: title,
          message: content,
          attachNew: attachNew,
        );
      case EditorType.editPost:
      case EditorType.editReply:
        return submitEdit(pageData, title, content, attachNew: attachNew);
      case EditorType.comment:
      case EditorType.reply:
        return post_api.submitReply(
          ApiService().dio,
          fid: pageData.fid.isNotEmpty ? pageData.fid : '2',
          tid: pageData.tid.isNotEmpty ? pageData.tid : widgetTid,
          formhash: pageData.formhash,
          posttime: pageData.posttime,
          message: content,
          attachNew: attachNew,
          noticeauthor: pageData.noticeauthor,
          noticetrimstr: pageData.noticetrimstr,
          noticeauthormsg: pageData.noticeauthormsg,
          reppid: editorType == EditorType.reply ? pageData.reppid : null,
        );
    }
  }
}

import 'dart:convert';
import 'package:flutter/material.dart';

import 'package:mtbbs/core/parser/page_fetcher.dart';
import 'package:mtbbs/core/parser/xml_helper.dart';
import 'package:mtbbs/core/utils/logger.dart';
import 'package:mtbbs/services/api_service.dart';
import 'package:mtbbs/api/forum/post/export.dart' as post_api;
import 'package:mtbbs/api/forum/viewthread/viewpid/export.dart' as viewpid_api;
import 'package:mtbbs/models/editor_snapshot.dart';
import 'package:mtbbs/core/app/emoji_loader.dart';
import 'package:mtbbs/widgets/bbcode/bbcode_controller.dart';

/// 编辑器页面加载和提交逻辑
///
/// 封装 fetchPage, fetchQuotedPost, submit, submitEdit, parseAttachNew。
/// 注意：pageData 在每次调用 submit/submitEdit 时传入，不保存在构造函数中。
class EditorSubmitHelper {
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

  /// 编辑器类型 → PageFetcher 的 URL 类型标识
  String get _typeKey => switch (editorType) {
    EditorType.post => 'post',
    EditorType.comment => 'comment',
    EditorType.reply => 'reply',
    EditorType.editPost => 'editPost',
    EditorType.editReply => 'editReply',
  };

  /// 拉取绑定的 Discuz 页面数据
  Future<PageFormData> fetchPage({bool preserveContent = false}) async {
    try {
      final result = await post_api.fetchEditorPage(
        ApiService().dio,
        type: _typeKey,
        fid: widgetFid,
        tid: widgetTid,
        pid: widgetPid,
        repquote: isReply ? widgetPid : null,
      );
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
      // 确保表情已加载，引用帖内容里的表情才能还原为 [呵呵] 文本
      await EmojiService().load();
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

  /// 从内容中提取 [attachimg]{aid}[/attachimg] + [attach]{aid}[/attach] + 面板活跃 AID，
  /// 以及调用方额外补充的 aid（[extraAids]，用于"已上传但未插入正文"的项）。
  ///
  /// 这些 aid 会以 `attachnew[aid][description]` 提交，Discuz 据此把附件绑定到帖子，
  /// **未在正文中引用到的会被展示在正文末尾**。
  Map<String, String> parseAttachNew(
    String content, {
    Set<String> extraAids = const {},
  }) {
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
    aids.addAll(extraAids);
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
    final fid = pageData.fid.isNotEmpty ? pageData.fid : widgetFid;
    final tid = pageData.tid.isNotEmpty ? pageData.tid : widgetTid;
    final pid = pageData.pid.isNotEmpty ? pageData.pid : widgetPid;
    AppLogger.i(
      'EDITOR',
      jsonEncode({
        'action': 'submitEdit',
        'titleLen': title.length,
        'contentLen': content.length,
        'attachNew': attachNew.length,
        'fid': fid,
        'tid': tid,
        'pid': pid,
      }),
    );
    try {
      final result = await post_api.submitEditPost(
        ApiService().dio,
        fid: fid,
        tid: tid,
        pid: pid,
        formhash: pageData.formhash,
        posttime: pageData.posttime,
        subject: title,
        message: content,
        attachNew: attachNew,
      );
      AppLogger.i(
        'EDITOR',
        jsonEncode({
          'action': 'submitEdit_done',
          'success': result.success,
          'message': result.message,
          'needsApproval': result.needsApproval,
        }),
      );
      return result;
    } catch (e) {
      AppLogger.e(
        'EDITOR',
        jsonEncode({'action': 'submitEdit_exception', 'error': e.toString()}),
      );
      return SubmitResult(success: false, message: '网络错误: $e');
    }
  }

  /// 统一提交入口
  ///
  /// [appendAids]：已上传但未插入正文的图片/附件 aid，一并按 `attachnew` 提交
  /// （Discuz 会把这些未引用的附件展示在正文末尾）。
  Future<SubmitResult> submit(
    PageFormData pageData,
    String title,
    String content, {
    Set<String> appendAids = const {},
  }) async {
    final attachNew = parseAttachNew(content, extraAids: appendAids);

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

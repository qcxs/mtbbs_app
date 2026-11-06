import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:mtbbs/api/forum/seccode/export.dart' as seccode_api;
import 'package:mtbbs/api/forum/secqaa/export.dart' as secqaa_api;
import 'package:mtbbs/core/app/site_store.dart';
import 'package:mtbbs/core/parser/page_fetcher.dart';
import 'package:mtbbs/core/parser/xml_helper.dart';
import 'package:mtbbs/core/utils/logger.dart';
import 'package:mtbbs/models/editor_snapshot.dart';
import 'package:mtbbs/pages/editor/editor_submit.dart';
import 'package:mtbbs/providers/editor_history_provider.dart';
import 'package:mtbbs/services/api_service.dart';
import 'package:mtbbs/widgets/bbcode/bbcode_controller.dart';

/// 编辑器共享内核 — 内容 / 页面数据 / 提交协议。
///
/// 完整版编辑器（[EditorPage]）与迷你版编辑器（帖子页 / 私信页内嵌）**共用**
/// 本对象，保证"能力一致 + 单一实现"（见 docs/06）。内核刻意**不依赖
/// `BuildContext`**：弹窗、Toast、主题等 UI 行为留在各自的 Surface。
///
/// 职责边界：
/// - 持有：正文/标题控制器、页面数据（formhash 等）、引用帖、表情映射
/// - 协议：`fetchPage` / `fetchQuotedPost` / `submit` / `buildSnapshot`
/// - 目标：`switchTarget`（帖子页"评论 ↔ 回复某评论"切换）
///
/// 图片/附件"列表管理"属完整版的界面能力，暂留在 `EditorPage`。
class EditorSession extends ChangeNotifier {
  EditorSession({
    required this.editorType,
    this.fid = '',
    this.tid = '',
    this.pid = '',
  });

  /// 当前编辑目标类型（可被 [switchTarget] 改变）
  EditorType editorType;

  /// 版块 / 帖子 / 楼层 id（可被 [switchTarget] 改变）
  String fid;
  String tid;
  String pid;

  final TextEditingController titleCtl = TextEditingController();
  final BBCodeController contentCtl = BBCodeController();

  /// 验证码输入框（页面要求验证码时才有意义）
  final TextEditingController seccodeCtl = TextEditingController();

  /// 验证问答答案输入框（页面要求验证问答时才有意义）
  final TextEditingController secqaaCtl = TextEditingController();

  /// 验证码图片字节；null 表示未加载成功
  Uint8List? seccodeImage;
  bool seccodeLoading = false;
  bool seccodeFailed = false;

  /// 验证问答题干；空串表示未加载/加载失败
  String secqaaQuestion = '';
  bool secqaaLoading = false;
  bool secqaaFailed = false;

  /// 防止快速点「换一个」时旧请求覆盖新图片
  int _seccodeEpoch = 0;
  int _secqaaEpoch = 0;

  /// 当前页面是否要求填写图片验证码
  bool get seccodeRequired => pageData.seccodeRequired;

  /// 当前页面是否要求回答验证问答
  bool get secqaaRequired => pageData.secqaaRequired;

  /// 当前页面是否要求任何形式的人机验证
  bool get captchaRequired => pageData.captchaRequired;

  /// 验证问答题面里自带的答案提示；空串表示没有（UI 隐藏「填充答案」）
  String get secqaaAnswerHint =>
      secqaa_api.secqaaAnswerFromQuestion(secqaaQuestion);

  /// 从绑定的 Discuz 页面提取的会话数据（formhash / posttime / uploadHash…）
  PageFormData pageData = const PageFormData();

  /// 被引用的帖子（回复某评论时用于展示引用卡）
  Map<String, dynamic>? quotedPost;

  /// 表情文本映射（快照持久化用）
  Map<String, String> emojiMap = {};

  bool get isPost =>
      editorType == EditorType.post || editorType == EditorType.editPost;
  bool get isReply => editorType == EditorType.reply;
  bool get isEdit =>
      editorType == EditorType.editPost || editorType == EditorType.editReply;

  /// 快照会话 key（由当前目标类型 + id 派生）
  String get sessionKey =>
      EditorHistoryProvider.generateKey(editorType, tid: tid, pid: pid);

  String get pageTitle {
    switch (editorType) {
      case EditorType.post:
        final name = SiteStore.instance.forums[fid] ?? '版块 $fid';
        return '发帖 - $name';
      case EditorType.editPost:
        return '编辑帖子';
      case EditorType.comment:
        return '评论';
      case EditorType.editReply:
        return '编辑评论';
      case EditorType.reply:
        return '回复评论';
    }
  }

  /// 提交辅助器按当前目标按需构建（[switchTarget] 后自动取到新值）
  EditorSubmitHelper get submitHelper => EditorSubmitHelper(
    editorType: editorType,
    widgetFid: fid,
    widgetTid: tid,
    widgetPid: pid,
    titleCtl: titleCtl,
    contentCtl: contentCtl,
    isEdit: isEdit,
    isPost: isPost,
    isReply: isReply,
  );

  // ==================== 协议 ====================

  Future<PageFormData> fetchPage({bool preserveContent = false}) =>
      submitHelper.fetchPage(preserveContent: preserveContent);

  Future<Map<String, dynamic>?> fetchQuotedPost() =>
      submitHelper.fetchQuotedPost();

  /// 提交当前内容（评论 / 回复 / 发帖 / 编辑）
  Future<SubmitResult> submit(
    String title,
    String content, {
    Set<String> appendAids = const {},
  }) => submitHelper.submit(
    pageData,
    title,
    content,
    appendAids: appendAids,
    seccodeVerify: seccodeCtl.text.trim(),
    secanswer: secqaaCtl.text.trim(),
  );

  // ==================== 人机验证（图片验证码 / 验证问答） ====================

  /// 按页面要求加载对应的人机验证：图片验证码或验证问答。
  ///
  /// 首次加载与「换一个」都走这里；两者互斥（拦截页只开一种）。
  Future<void> loadCaptcha() async {
    if (seccodeRequired) {
      await loadSeccodeImage();
    } else if (secqaaRequired) {
      await loadSecqaaQuestion();
    } else {
      clearCaptcha();
      notifyListeners();
    }
  }

  /// 加载验证码图片（首次加载与「换一个」都走这里）。
  ///
  /// 必须先请求 `action=update`：桌面模板页面只有占位 span，服务端不会在
  /// 页面里下发图片令牌；同时 update 会把验证码按 [PageFormData.seccodeModId]
  /// 写入会话，保证提交时的模块标识一致。图片与站点会话绑定，必须走
  /// [ApiService] 的 Dio，且不能被图片缓存复用。
  Future<void> loadSeccodeImage() async {
    if (!seccodeRequired) {
      clearCaptcha();
      notifyListeners();
      return;
    }
    final epoch = ++_seccodeEpoch;
    seccodeLoading = true;
    seccodeFailed = false;
    notifyListeners();

    Uint8List? bytes;
    try {
      final dio = ApiService().dio;
      bytes = await seccode_api.refreshSeccodeImage(
        dio,
        idhash: pageData.seccodeHash,
        modId: pageData.seccodeModId,
        fallbackImageUrl: pageData.seccodeImageUrl,
      );
    } catch (e) {
      AppLogger.w('EDITOR', 'seccode load error: $e');
    }

    if (epoch != _seccodeEpoch) return;
    seccodeImage = bytes;
    seccodeFailed = bytes == null;
    seccodeLoading = false;
    notifyListeners();
  }

  /// 加载验证问答题干（首次加载与「换一个」都走这里）。
  ///
  /// 题面只出现在 `misc.php?mod=secqaa&action=update` 的 JS 响应里，
  /// 页面 HTML 只有占位 span。该请求同时把新题写入会话，保证提交时
  /// `secqaahash` 与服务端一致。
  Future<void> loadSecqaaQuestion() async {
    if (!secqaaRequired) {
      clearCaptcha();
      notifyListeners();
      return;
    }
    final epoch = ++_secqaaEpoch;
    secqaaLoading = true;
    secqaaFailed = false;
    notifyListeners();

    String question = '';
    try {
      question = await secqaa_api.fetchSecqaaQuestion(
        ApiService().dio,
        idhash: pageData.secqaaHash,
        modId: pageData.secqaaModId,
      );
    } catch (e) {
      AppLogger.w('EDITOR', 'secqaa load error: $e');
    }

    if (epoch != _secqaaEpoch) return;
    secqaaQuestion = question;
    secqaaFailed = question.isEmpty;
    secqaaLoading = false;
    notifyListeners();
  }

  /// 提交失败（验证码 / 验证问答错误）后清空输入并换一张新题。
  void resetCaptcha() {
    seccodeCtl.clear();
    secqaaCtl.clear();
    loadCaptcha();
  }

  /// 清空人机验证状态（切目标 / 重新抓页面时调用）。
  void clearCaptcha() {
    _seccodeEpoch++;
    _secqaaEpoch++;
    seccodeCtl.clear();
    secqaaCtl.clear();
    seccodeImage = null;
    seccodeLoading = false;
    seccodeFailed = false;
    secqaaQuestion = '';
    secqaaLoading = false;
    secqaaFailed = false;
  }

  /// 切换编辑目标（帖子页：评论 ↔ 回复某评论）。
  ///
  /// 保留正文与图片，清掉旧的页面数据/引用帖——新目标需要重新抓取
  /// （reply 需要 `repquote` 页面数据里的 noticeauthor/reppid 等）。
  void switchTarget(EditorType type, {String? tid, String pid = ''}) {
    editorType = type;
    if (tid != null && tid.isNotEmpty) this.tid = tid;
    this.pid = pid;
    pageData = const PageFormData();
    quotedPost = null;
    clearCaptcha();
    notifyListeners();
  }

  // ==================== 快照 ====================

  EditorSnapshot buildSnapshot({required bool isManual}) {
    return EditorSnapshot(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      sessionKey: sessionKey,
      editorType: editorType.name,
      label: pageTitle,
      title: titleCtl.text,
      content: contentCtl.text,
      pendingAids: contentCtl.pendingAids.toList(),
      quotedPost: quotedPost?.map((k, v) => MapEntry(k, v.toString())),
      createdAt: DateTime.now(),
      isManual: isManual,
      tid: tid,
      pid: pid,
      fid: fid,
      pageData: PageFormDataSnapshot.fromPageFormData(pageData),
      emojiMap: Map.from(emojiMap),
    );
  }

  @override
  void dispose() {
    titleCtl.dispose();
    contentCtl.dispose();
    seccodeCtl.dispose();
    secqaaCtl.dispose();
    super.dispose();
  }
}

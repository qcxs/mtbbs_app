import 'package:flutter/material.dart';

import 'package:mtbbs/core/app/site_store.dart';
import 'package:mtbbs/core/parser/page_fetcher.dart';
import 'package:mtbbs/core/parser/xml_helper.dart';
import 'package:mtbbs/models/editor_snapshot.dart';
import 'package:mtbbs/pages/editor/editor_submit.dart';
import 'package:mtbbs/providers/editor_history_provider.dart';
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
  }) => submitHelper.submit(pageData, title, content, appendAids: appendAids);

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
    super.dispose();
  }
}

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import 'package:mtbbs/api/forum/post/upload.dart' as upload_api;
import 'package:mtbbs/core/parser/page_fetcher.dart';
import 'package:mtbbs/core/utils/cache_utils.dart';
import 'package:mtbbs/core/utils/logger.dart';
import 'package:mtbbs/services/api_service.dart';
import 'package:mtbbs/widgets/bbcode/bbcode_controller.dart';
import 'package:mtbbs/widgets/common/toast_utils.dart';

/// 图片管理 —— **状态与动作的唯一实现**，完整编辑器与迷你编辑器（帖子页）共用。
///
/// 只负责数据与动作（刷新 / 上传 / 删除 / 忽略 / AID 同步 / 预览用的 aid→src），
/// 渲染交给纯 UI 组件 `ImagePickerSheet`（`widgets/dialog/image_picker_sheet.dart`）。
///
/// 依赖通过回调注入（当前页面数据 / 当前登录 uid / fid/tid/pid 回退），不持有
/// `BuildContext`，因此可单测。变更通过 [ChangeNotifier] 通知宿主重建。
///
/// - 完整编辑器：页面级持有，列表在编辑器生命周期内**持久**（预览 `aidToSrc`、
///   工具栏角标、提交前预检、剪贴板上传都读它）。
/// - 迷你编辑器：图片抽屉打开时临时持有，关闭即释放（每次打开重新拉取）。
class ForumImageController extends ChangeNotifier {
  ForumImageController({
    required this.contentCtl,
    required this.pageData,
    required this.uid,
    this.fallbackFid = '',
    this.fallbackTid = '',
    this.fallbackPid = '',
  });

  /// 正文控制器（插入 `[attachimg]`、同步 `pendingAids`）
  final BBCodeController contentCtl;

  /// 当前页面数据（异步加载，故用回调而非快照）
  final PageFormData Function() pageData;

  /// 当前登录 uid（未登录返回 ''）
  final String Function() uid;

  /// 页面数据未就绪时的 fid/tid/pid 回退（来自页面 widget）
  final String fallbackFid;
  final String fallbackTid;
  final String fallbackPid;

  final List<Map<String, dynamic>> _list = [];
  final Set<String> _ignored = <String>{};
  bool _loading = false;

  /// AID → 图片 URL 映射（预览时把 `[attachimg]aid[/attachimg]` 换成真实图）
  final Map<String, String> aidToSrc = {};

  /// 图片列表（被忽略的已从中移除，与历史实现一致）
  List<Map<String, dynamic>> get list => List.unmodifiable(_list);

  /// 被忽略的 AID（透传给面板）
  Set<String> get ignoredAids => Set.unmodifiable(_ignored);

  bool get loading => _loading;

  /// 活跃 AID（未忽略）——提交前预检 / `pendingAids` 用
  Set<String> get activeAids => _list
      .map((i) => i['aid']?.toString() ?? '')
      .where((a) => a.isNotEmpty && !_ignored.contains(a))
      .toSet();

  String get _fid {
    final d = pageData();
    return d.fid.isNotEmpty ? d.fid : fallbackFid;
  }

  String get _tid {
    final d = pageData();
    return d.tid.isNotEmpty ? d.tid : fallbackTid;
  }

  String get _pid {
    final d = pageData();
    return d.pid.isNotEmpty ? d.pid : fallbackPid;
  }

  /// 登记一张已知图片（页面抓取 / 上传成功 / 剪贴板上传）
  void addImage({
    required String aid,
    required String src,
    String title = '',
    String type = 'uploaded',
  }) {
    if (aid.isEmpty || src.isEmpty) return;
    if (!_list.any((i) => i['aid'] == aid)) {
      _list.add({'aid': aid, 'src': src, 'title': title, 'type': type});
    }
    aidToSrc[aid] = src;
    notifyListeners();
  }

  /// 仅补充 aid→src 映射（快照恢复用；不动列表）
  void addAidSrc(String aid, String src) {
    if (aid.isEmpty || src.isEmpty) return;
    aidToSrc[aid] = src;
  }

  /// 页面抓取/刷新后填充列表与映射。
  ///
  /// [preserve] = true 时保留已有 `aidToSrc`（合并新值）；列表始终按 [images] 重建
  /// （复刻历史行为）。
  void setFromPageImages(
    List<Map<String, dynamic>> images, {
    bool preserve = false,
  }) {
    if (!preserve) aidToSrc.clear();
    for (final img in images) {
      final aid = img['aid']?.toString() ?? '';
      final src = img['src']?.toString() ?? '';
      if (aid.isNotEmpty && src.isNotEmpty) aidToSrc[aid] = src;
    }
    _list
      ..clear()
      ..addAll(
        images.map(
          (img) => <String, dynamic>{
            'aid': img['aid'] ?? '',
            'src': img['src'] ?? '',
            'title': img['title'] ?? '',
            'type': 'existing',
          },
        ),
      );
    notifyListeners();
  }

  /// 刷新"已上传未使用"的图片（合并去重）
  Future<void> refresh() async {
    _loading = true;
    notifyListeners();
    try {
      final fetched = await upload_api.fetchUnusedImages(
        ApiService().dio,
        fid: _fid,
        tid: _tid.isNotEmpty ? _tid : null,
      );
      for (final img in fetched) {
        final aid = img['aid']?.toString() ?? '';
        final src = img['src']?.toString() ?? '';
        if (aid.isEmpty || src.isEmpty) continue;
        if (!_list.any((i) => i['aid'] == aid)) {
          _list.add({
            'aid': aid,
            'src': src,
            'title': img['title']?.toString() ?? '',
            'type': 'uploaded',
          });
        }
        aidToSrc.putIfAbsent(aid, () => src);
      }
    } catch (e) {
      AppLogger.w('EDITOR', 'image refresh failed: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// 选择文件（可多选）→ 上传 → 加入列表（不自动插入，交给用户"插入"）
  Future<void> upload() async {
    if (uid().isEmpty) {
      showToast('请先登录');
      return;
    }
    final data = pageData();
    if (data.uploadHash.isEmpty) return;

    final exts = data.imageExtensions;
    final result = await FilePicker.platform.pickFiles(
      type: exts.isNotEmpty ? FileType.custom : FileType.image,
      allowedExtensions: exts.isNotEmpty ? exts : null,
      allowMultiple: true,
      withReadStream: true,
      // 关闭插件默认压缩：否则 GIF 丢动画、PNG 被转 JPG（docs/07 #14）
      allowCompression: false,
    );
    if (result == null || result.files.isEmpty) return;

    int success = 0;
    int fail = 0;
    for (final f in result.files) {
      final path = f.path;
      if (path == null) {
        fail++;
        continue;
      }
      try {
        final up = await uploadFile(File(path));
        if (up != null) {
          success++;
        } else {
          fail++;
        }
        // 上传后清理 file_picker 复制的临时缓存文件（Android，见 docs/07 #28）
        await deleteFilePickerTempIfAny(path);
      } catch (e) {
        fail++;
        AppLogger.w('EDITOR', 'image upload failed: $e');
      }
    }
    if (success > 0 && fail == 0) {
      showToast('上传成功 $success 张图片');
    } else if (success > 0) {
      showToast('上传完成：成功 $success 张，失败 $fail 张');
    } else {
      showToast('上传失败');
    }
  }

  /// 上传单个文件并登记；返回 `{aid, src, title}`，失败返回 null
  Future<Map<String, dynamic>?> uploadFile(File file) async {
    final u = uid();
    final data = pageData();
    if (u.isEmpty || data.uploadHash.isEmpty) return null;
    try {
      final up = await upload_api.uploadImage(
        ApiService().dio,
        file: file,
        uid: u,
        uploadHash: data.uploadHash,
      );
      if (up['success'] != true) return null;
      final aid = up['aid']?.toString() ?? '';
      final src = up['src']?.toString() ?? '';
      if (aid.isEmpty || src.isEmpty) return null;
      final title = up['title']?.toString() ?? '';
      addImage(aid: aid, src: src, title: title);
      return {'aid': aid, 'src': src, 'title': title};
    } catch (e) {
      AppLogger.w('EDITOR', 'image upload failed: $e');
      return null;
    }
  }

  /// 删除图片（服务端 + 本地列表）
  Future<void> delete(String aid) async {
    final ok = await upload_api.deleteUnusedImage(
      ApiService().dio,
      formhash: pageData().formhash,
      tid: _tid,
      pid: _pid,
      aid: aid,
    );
    if (!ok) {
      showToast('删除失败');
      return;
    }
    _list.removeWhere((i) => i['aid'] == aid);
    aidToSrc.remove(aid);
    notifyListeners();
    showToast('已删除');
  }

  /// 忽略图片（从列表隐藏，不删服务端）
  void ignore(String aid) {
    _ignored.add(aid);
    _list.removeWhere((i) => i['aid'] == aid);
    aidToSrc.remove(aid);
    notifyListeners();
  }

  /// 把活跃 AID 同步到 [BBCodeController.pendingAids]：
  /// "上传但未插入正文"的图片据此在提交时经 `attachnew` 绑定（见 docs/07 #42）。
  void syncPendingAids() {
    contentCtl.pendingAids
      ..clear()
      ..addAll(activeAids);
  }
}

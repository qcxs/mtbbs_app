import 'dart:convert';
import 'dart:math';

import 'package:mtbbs/core/page_fetcher.dart';

/// 生成唯一 ID（基于时间戳 + 随机数，不依赖 uuid 包）
String _generateId() {
  final ts = DateTime.now().millisecondsSinceEpoch;
  final r = Random().nextInt(99999);
  return '${ts}_$r';
}

// ==================== PageFormDataSnapshot ====================

/// PageFormData 的序列化版本
///
/// 保存编辑器绑定的 Discuz 页面数据的快照。
/// 恢复时 formhash 可能已过期，需要重新 fetch。
class PageFormDataSnapshot {
  final String formhash;
  final String posttime;
  final String fid;
  final String tid;
  final String pid;
  final String noticeauthor;
  final String reppid;
  final String noticetrimstr;
  final String noticeauthormsg;
  final String title;
  final String content;
  final String uploadHash;
  final String fetchedUrl;
  final List<Map<String, String>> images;

  const PageFormDataSnapshot({
    this.formhash = '',
    this.posttime = '',
    this.fid = '',
    this.tid = '',
    this.pid = '',
    this.noticeauthor = '',
    this.reppid = '',
    this.noticetrimstr = '',
    this.noticeauthormsg = '',
    this.title = '',
    this.content = '',
    this.uploadHash = '',
    this.fetchedUrl = '',
    this.images = const [],
  });

  factory PageFormDataSnapshot.fromPageFormData(PageFormData data) {
    return PageFormDataSnapshot(
      formhash: data.formhash,
      posttime: data.posttime,
      fid: data.fid,
      tid: data.tid,
      pid: data.pid,
      noticeauthor: data.noticeauthor,
      reppid: data.reppid,
      noticetrimstr: data.noticetrimstr,
      noticeauthormsg: data.noticeauthormsg,
      title: data.title,
      content: data.content,
      uploadHash: data.uploadHash,
      fetchedUrl: data.fetchedUrl,
      images: List<Map<String, String>>.from(data.images),
    );
  }

  PageFormData toPageFormData() {
    return PageFormData(
      formhash: formhash,
      posttime: posttime,
      fid: fid,
      tid: tid,
      pid: pid,
      noticeauthor: noticeauthor,
      reppid: reppid,
      noticetrimstr: noticetrimstr,
      noticeauthormsg: noticeauthormsg,
      title: title,
      content: content,
      images: images,
      uploadHash: uploadHash,
      fetchedUrl: fetchedUrl,
      success: formhash.isNotEmpty,
    );
  }

  Map<String, dynamic> toJson() => {
        'formhash': formhash,
        'posttime': posttime,
        'fid': fid,
        'tid': tid,
        'pid': pid,
        'noticeauthor': noticeauthor,
        'reppid': reppid,
        'noticetrimstr': noticetrimstr,
        'noticeauthormsg': noticeauthormsg,
        'title': title,
        'content': content,
        'uploadHash': uploadHash,
        'fetchedUrl': fetchedUrl,
        'images': images,
      };

  factory PageFormDataSnapshot.fromJson(Map<String, dynamic> json) {
    final rawImages = json['images'];
    List<Map<String, String>> images;
    if (rawImages is List) {
      images = rawImages.map((e) {
        if (e is Map<String, String>) return e;
        if (e is Map) {
          return e.map((k, v) => MapEntry(k.toString(), v.toString()));
        }
        return <String, String>{};
      }).toList();
    } else {
      images = const [];
    }

    return PageFormDataSnapshot(
      formhash: json['formhash']?.toString() ?? '',
      posttime: json['posttime']?.toString() ?? '',
      fid: json['fid']?.toString() ?? '',
      tid: json['tid']?.toString() ?? '',
      pid: json['pid']?.toString() ?? '',
      noticeauthor: json['noticeauthor']?.toString() ?? '',
      reppid: json['reppid']?.toString() ?? '',
      noticetrimstr: json['noticetrimstr']?.toString() ?? '',
      noticeauthormsg: json['noticeauthormsg']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      content: json['content']?.toString() ?? '',
      uploadHash: json['uploadHash']?.toString() ?? '',
      fetchedUrl: json['fetchedUrl']?.toString() ?? '',
      images: images,
    );
  }
}

// ==================== EditorSnapshot ====================

/// 编辑器快照 — 完整序列化编辑器状态
///
/// 序列化的是整个编辑器状态（controller + pageData + pendingAids 等），
/// 而不是手动拼接字段。后续新增编辑器功能时，只需在此类中追加字段即可自动适配。
class EditorSnapshot {
  /// 唯一标识
  final String id;

  /// 分组 key（用于关联同一次编辑会话）
  final String sessionKey;

  /// 编辑器类型字符串
  final String editorType;

  /// 显示标签（如"发帖 - 技术区"）
  final String label;

  /// 标题输入框内容
  final String title;

  /// BBCode 内容
  final String content;

  /// 未绑定到内容的图片 AID
  final List<String> pendingAids;

  /// 引用帖子数据
  final Map<String, String>? quotedPost;

  /// 快照创建时间
  final DateTime createdAt;

  /// true=手动保存，false=自动快照
  final bool isManual;

  /// 编辑器参数
  final String tid;
  final String pid;
  final String fid;

  /// PageFormData 序列化
  final PageFormDataSnapshot pageData;

  /// emoji 映射（预览恢复用）
  final Map<String, String> emojiMap;

  const EditorSnapshot({
    required this.id,
    required this.sessionKey,
    required this.editorType,
    required this.label,
    this.title = '',
    this.content = '',
    this.pendingAids = const [],
    this.quotedPost,
    required this.createdAt,
    this.isManual = false,
    this.tid = '',
    this.pid = '',
    this.fid = '',
    required this.pageData,
    this.emojiMap = const {},
  });

  /// 去除 BBCode 标签后的纯文本预览
  String get preview {
    final text = content.replaceAll(_bbcodePattern, '');
    return text.trim();
  }

  /// 纯文本字数
  int get wordCount {
    final text = preview;
    // 中文字算 1 字，英文单词按空格分隔
    return text.replaceAll(RegExp(r'\s+'), '').length;
  }

  static final RegExp _bbcodePattern = RegExp(r'\[/?[a-z0-9=,#]+\]');

  Map<String, dynamic> toJson() => {
        'id': id,
        'sessionKey': sessionKey,
        'editorType': editorType,
        'label': label,
        'title': title,
        'content': content,
        'pendingAids': pendingAids,
        'quotedPost': quotedPost,
        'createdAt': createdAt.toIso8601String(),
        'isManual': isManual,
        'tid': tid,
        'pid': pid,
        'fid': fid,
        'pageData': pageData.toJson(),
        'emojiMap': emojiMap,
      };

  factory EditorSnapshot.fromJson(Map<String, dynamic> json) {
    final rawQuoted = json['quotedPost'];
    Map<String, String>? quotedPost;
    if (rawQuoted is Map) {
      quotedPost = rawQuoted.map((k, v) => MapEntry(k.toString(), v.toString()));
    }

    final rawEmoji = json['emojiMap'];
    Map<String, String> emojiMap;
    if (rawEmoji is Map) {
      emojiMap = rawEmoji.map((k, v) => MapEntry(k.toString(), v.toString()));
    } else {
      emojiMap = const {};
    }

    final rawAids = json['pendingAids'];
    List<String> pendingAids;
    if (rawAids is List) {
      pendingAids = rawAids.map((e) => e.toString()).toList();
    } else {
      pendingAids = const [];
    }

    return EditorSnapshot(
      id: json['id']?.toString() ?? _generateId(),
      sessionKey: json['sessionKey']?.toString() ?? '',
      editorType: json['editorType']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      content: json['content']?.toString() ?? '',
      pendingAids: pendingAids,
      quotedPost: quotedPost,
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      isManual: json['isManual'] == true,
      tid: json['tid']?.toString() ?? '',
      pid: json['pid']?.toString() ?? '',
      fid: json['fid']?.toString() ?? '',
      pageData:
          PageFormDataSnapshot.fromJson(json['pageData'] as Map<String, dynamic>? ?? {}),
      emojiMap: emojiMap,
    );
  }
}

// ==================== 序列化辅助 ====================

extension EditorSnapshotCodec on EditorSnapshot {
  static String encodeList(List<EditorSnapshot> snapshots) =>
      jsonEncode(snapshots.map((e) => e.toJson()).toList());

  static List<EditorSnapshot> decodeList(String jsonStr) {
    final list = jsonDecode(jsonStr) as List<dynamic>;
    return list
        .map((e) => EditorSnapshot.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mtbbs/core/utils/thread_cache_policy.dart';
import 'package:mtbbs/models/thread_detail.dart';
import 'package:mtbbs/models/thread_snapshot.dart';
import 'package:mtbbs/services/thread_cache_transfer.dart';

PostItem _post({
  String pid = '100',
  int floor = 0,
  bool isOp = false,
  String bbcode = '楼主正文',
  String postTime = '3 小时前',
  String username = 'alice',
}) => PostItem(
  pid: pid,
  floor: floor,
  isOp: isOp,
  uid: 'u$pid',
  username: username,
  postTime: postTime,
  bbcode: bbcode,
);

ThreadSnapshot _snapshot({
  ThreadCacheKind kind = ThreadCacheKind.auto,
  String host = 'bbs.example.com',
  String? viewer = 'uid:1',
  String tid = '42',
  String title = '测试标题',
  String hash = '0011223344556677',
  Map<int, List<PostItem>> commentPages = const {},
}) {
  final now = DateTime(2026, 10, 27, 10, 0, 0);
  final pages = commentPages.isEmpty
      ? {
          1: [_post(pid: '101', floor: 1, bbcode: '评论一')],
        }
      : commentPages;
  return ThreadSnapshot(
    kind: kind,
    host: host,
    viewer: viewer,
    savedBy: kind == ThreadCacheKind.offline ? 'uid:1' : null,
    tid: tid,
    title: title,
    contentHash: hash,
    postTimeText: '3 小时前',
    isNewAtCapture: true,
    mainPost: _post(isOp: true, bbcode: '[b]楼主[/b]正文'),
    commentPages: pages,
    cachedPages: pages.keys.toList()..sort(),
    totalPages: 3,
    createdAt: now,
    lastVisitedAt: kind == ThreadCacheKind.auto ? now : null,
    expiresAt: kind == ThreadCacheKind.auto
        ? now.add(const Duration(days: 1))
        : null,
    savedAt: kind == ThreadCacheKind.offline ? now : null,
  ).recomputeBytes();
}

void main() {
  group('ThreadSnapshot 序列化', () {
    test('toMap/fromMap 往返保留核心字段与评论页', () {
      final original = _snapshot(
        commentPages: {
          1: [_post(pid: '101', floor: 1, bbcode: '第一页')],
          2: [
            _post(pid: '102', floor: 2, bbcode: '第二页 A'),
            _post(pid: '103', floor: 3, bbcode: '第二页 B'),
          ],
        },
      );

      final restored = ThreadSnapshot.fromMap(
        Map<String, dynamic>.from(jsonDecode(jsonEncode(original.toMap()))),
      );

      expect(restored.schemaVersion, kThreadSnapshotSchemaVersion);
      expect(restored.kind, ThreadCacheKind.auto);
      expect(restored.host, original.host);
      expect(restored.viewer, 'uid:1');
      expect(restored.tid, original.tid);
      expect(restored.title, original.title);
      expect(restored.contentHash, original.contentHash);
      expect(restored.mainPost.bbcode, original.mainPost.bbcode);
      expect(restored.cachedPages, [1, 2]);
      expect(restored.commentPages[2]!.map((p) => p.pid), ['102', '103']);
      expect(restored.totalPages, 3);
      expect(restored.createdAt, original.createdAt);
      expect(restored.expiresAt, original.expiresAt);
    });

    test('缺少核心字段或不支持的版本抛 FormatException', () {
      final base = _snapshot().toMap();

      expect(
        () => ThreadSnapshot.fromMap({...base, 'schemaVersion': 2}),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => ThreadSnapshot.fromMap({...base, 'kind': 'unknown'}),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => ThreadSnapshot.fromMap({...base, 'host': ''}),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => ThreadSnapshot.fromMap({...base, 'tid': ''}),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => ThreadSnapshot.fromMap({...base, 'mainPost': null}),
        throwsA(isA<FormatException>()),
      );
    });

    test('cachedPages 只保留实际存在的评论页', () {
      final map = _snapshot().toMap();
      map['cachedPages'] = [1, 2, 3];
      final restored = ThreadSnapshot.fromMap(map);
      expect(restored.cachedPages, [1]);
    });

    test('approxBytes 缺失时按内容重算', () {
      final map = _snapshot().toMap(includeApproxBytes: false);
      expect(map.containsKey('approxBytes'), isFalse);
      final restored = ThreadSnapshot.fromMap(map);
      expect(restored.approxBytes, greaterThan(0));
    });
  });

  group('存储键', () {
    test('自动缓存键包含 host/viewer/tid/hash，空 viewer 记为 guest', () {
      expect(
        ThreadSnapshot.autoKey(
          host: 'a.com',
          viewer: '',
          tid: '1',
          contentHash: 'abc',
        ),
        'auto|a.com|guest|1|abc',
      );
      expect(
        ThreadSnapshot.autoKey(
          host: 'a.com',
          viewer: 'uid:9',
          tid: '1',
          contentHash: 'abc',
        ),
        'auto|a.com|uid:9|1|abc',
      );
    });

    test('离线副本键只含 host + tid，storageKey 按类型切换', () {
      expect(
        ThreadSnapshot.offlineKey(host: 'a.com', tid: '1'),
        'offline|a.com|1',
      );
      expect(_snapshot(kind: ThreadCacheKind.offline).storageKey,
          'offline|bbs.example.com|42');
      expect(_snapshot().storageKey,
          'auto|bbs.example.com|uid:1|42|0011223344556677');
    });
  });

  group('展示与分页', () {
    test('mainSummary 去掉 BBCode 标记并截断到 80 字', () {
      final longText = '[b]${'甲' * 100}[/b]';
      final snapshot = ThreadSnapshot(
        kind: ThreadCacheKind.auto,
        host: 'a.com',
        tid: '1',
        title: 't',
        contentHash: 'h',
        mainPost: _post(isOp: true, bbcode: longText),
        createdAt: DateTime(2026),
      );
      final summary = snapshot.mainSummary;
      expect(summary.contains('['), isFalse);
      expect(summary.endsWith('…'), isTrue);
      expect(summary.length, 81);
    });

    test('mainSummary 清理 appdata 占位元素后的空白', () {
      final snapshot = ThreadSnapshot(
        kind: ThreadCacheKind.auto,
        host: 'a.com',
        tid: '1',
        title: 't',
        contentHash: 'h',
        mainPost: _post(
          isOp: true,
          bbcode: '[appdata]{"type":"image"}[/appdata]正文 https://x.com/a.png',
        ),
        createdAt: DateTime(2026),
      );
      expect(snapshot.mainSummary, '正文');
    });

    test('toViewData 只返回指定评论页', () {
      final snapshot = _snapshot(
        commentPages: {
          1: [_post(pid: '101', floor: 1)],
          2: [_post(pid: '102', floor: 2)],
        },
      );
      final page2 = snapshot.toViewData(page: 2);
      expect(page2.tid, snapshot.tid);
      expect(page2.currentPage, 2);
      expect(page2.allPostsPids, ['102']);
      expect(snapshot.toViewData(page: 9).posts, isEmpty);
    });

    test('withCommentPage 合并页码并重算大小', () {
      final snapshot = _snapshot();
      final updated = snapshot.withCommentPage(2, [
        _post(pid: '102', floor: 2, bbcode: '新增评论'),
      ]);
      expect(updated.cachedPages, [1, 2]);
      expect(updated.commentPages[2]!.single.pid, '102');
      expect(updated.approxBytes, greaterThan(0));
      // 原对象不被修改
      expect(snapshot.cachedPages, [1]);
    });
  });

  group('ThreadSnapshotMeta 索引', () {
    test('tryFromMap 对损坏记录返回 null', () {
      expect(ThreadSnapshotMeta.tryFromMap(null), isNull);
      expect(ThreadSnapshotMeta.tryFromMap('x'), isNull);
      expect(ThreadSnapshotMeta.tryFromMap({'kind': 'auto'}), isNull);
      expect(
        ThreadSnapshotMeta.tryFromMap({
          'key': 'k',
          'kind': 'auto',
          'host': '',
          'tid': '1',
        }),
        isNull,
      );
    });

    test('tryFromMap 解析并计算分组与排序时间', () {
      final meta = ThreadSnapshotMeta.tryFromMap(
        _snapshot(kind: ThreadCacheKind.offline).toMeta().toMap(),
      );
      expect(meta, isNotNull);
      expect(meta!.isOffline, isTrue);
      expect(meta.offlineGroupKey, 'bbs.example.com|42');
      expect(meta.sortTime, meta.savedAt);
    });

    test('isExpiredAt 只对自动缓存生效', () {
      final now = DateTime(2026, 10, 27, 12);
      final auto = _snapshot().toMeta();
      expect(auto.isExpiredAt(now.add(const Duration(days: 1))), isTrue);
      expect(auto.isExpiredAt(now.subtract(const Duration(days: 2))), isFalse);

      final offline = _snapshot(kind: ThreadCacheKind.offline).toMeta();
      expect(offline.isExpiredAt(now.add(const Duration(days: 999))), isFalse);
      expect(offline.threadGroupKey, 'bbs.example.com|uid:1|42');
    });
  });

  group('threadContentHash', () {
    test('相同输入稳定，与字段内容相关', () {
      final a = threadContentHash('标题', '正文');
      expect(a, hasLength(16));
      expect(a, threadContentHash('标题', '正文'));
      expect(a, isNot(threadContentHash('标题', '正文2')));
      expect(a, isNot(threadContentHash('标题2', '正文')));
    });

    test('换行标准化：CRLF 与 LF 等价', () {
      expect(
        threadContentHash('t', 'a\r\nb\rc'),
        threadContentHash('t', 'a\nb\nc'),
      );
    });

    test('标题/正文首尾空白不影响结果', () {
      expect(threadContentHash(' t ', ' 正文 '), threadContentHash('t', '正文'));
    });
  });

  group('isNewThreadTime', () {
    test('相对时间视为新帖', () {
      for (final text in ['刚刚', '昨天', '前天', '25分钟前', '2 天前', '3 小时前']) {
        expect(isNewThreadTime(text), isTrue, reason: text);
      }
    });

    test('模板带前缀或中文数字/「半」同样视为新帖', () {
      // bbs.binmt.cc 的移动模板会下发「发表在 半小时前」，前缀不能影响判定
      for (final text in [
        '发表在 半小时前',
        '发表于 10 分钟前',
        '半小时前',
        '十分钟前',
        '一小时前',
        '两天前',
        '两个半小时前',
        '刚才',
        '昨天 12:34',
      ]) {
        expect(isNewThreadTime(text), isTrue, reason: text);
      }
    });

    test('无法确认的文本默认按新帖处理（排除法）', () {
      for (final text in ['半年前', '1 个月前', '2026-10']) {
        expect(isNewThreadTime(text), isTrue, reason: text);
      }
    });

    test('完整日期、时分与空串视为非新帖', () {
      for (final text in [
        '2026-10-11',
        '2026/10/11 08:00',
        '2026年10月11日',
        '10-11 08:00',
        '',
      ]) {
        expect(isNewThreadTime(text), isFalse, reason: text);
      }
    });
  });

  group('viewerTag', () {
    test('空/游客/0 归一为 guest，且幂等', () {
      expect(viewerTag(''), 'guest');
      expect(viewerTag('0'), 'guest');
      expect(viewerTag('guest'), 'guest');
      expect(viewerTag('123'), 'uid:123');
      expect(viewerTag('uid:123'), 'uid:123');
    });
  });

  group('导出文件', () {
    test('buildExportJson 顶层带格式与版本，items 可回读', () {
      final transfer = ThreadCacheTransfer.instance;
      final json = transfer.buildExportJson([_snapshot()]);
      final map = Map<String, dynamic>.from(jsonDecode(json));

      expect(map['format'], kThreadCacheExportFormat);
      expect(map['schemaVersion'], kThreadSnapshotSchemaVersion);
      expect(map['exportedAt'], isA<String>());
      expect(map['items'], hasLength(1));

      final restored = ThreadSnapshot.fromMap(
        Map<String, dynamic>.from((map['items'] as List).single as Map),
      );
      expect(restored.tid, '42');
    });

    test('预览拒绝非法 JSON / 错误格式 / 过高版本 / 缺少 items', () async {
      final transfer = ThreadCacheTransfer.instance;

      var preview = await transfer.preview('not json', viewer: '1');
      expect(preview.valid, isFalse);
      expect(preview.error, '文件不是合法 JSON');

      preview = await transfer.preview(
        jsonEncode({'format': 'other', 'schemaVersion': 1, 'items': []}),
        viewer: '1',
      );
      expect(preview.valid, isFalse);
      expect(preview.error, '不是 mtbbs 帖子缓存文件');

      preview = await transfer.preview(
        jsonEncode({
          'format': kThreadCacheExportFormat,
          'schemaVersion': kThreadSnapshotSchemaVersion + 1,
          'items': [],
        }),
        viewer: '1',
      );
      expect(preview.valid, isFalse);
      expect(preview.error, '文件版本过高，请升级 App');

      preview = await transfer.preview(
        jsonEncode({
          'format': kThreadCacheExportFormat,
          'schemaVersion': kThreadSnapshotSchemaVersion,
        }),
        viewer: '1',
      );
      expect(preview.valid, isFalse);
      expect(preview.error, '缺少 items 列表');
    });

    test('时间戳文件名格式为 yyyyMMdd_HHmmss', () {
      expect(
        ThreadCacheTransfer.timestampForFileName(),
        matches(RegExp(r'^\d{8}_\d{6}$')),
      );
    });
  });
}

extension on ThreadViewData {
  List<String> get allPostsPids => [for (final p in posts) p.pid];
}

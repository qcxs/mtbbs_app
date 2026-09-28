import 'package:flutter_test/flutter_test.dart';
import 'package:mtbbs/controllers/thread_list_controller.dart';

/// 通用帖子列表控制器 — 失败语义与项级隔离
///
/// 覆盖两类"静默失败"：
/// - API 返回 `success:false` 被当成"空列表"（用户看到"暂无帖子"而不是"需要先登录"）
/// - 单条坏数据让整个列表抛异常
void main() {
  ThreadListController controllerOf(Map<String, dynamic> result) =>
      ThreadListController(fetchFn: ({required page}) async => result);

  group('列表加载：失败不再被静默吞掉', () {
    test('success:false → 错误态，而不是空列表', () async {
      final c = controllerOf({'success': false, 'message': '需要先登录'});
      await c.loadInitial();
      expect(c.state, LoadState.error);
      expect(c.items, isEmpty);
      expect(c.errorMessage, contains('需要先登录'));
    });

    test('success:true + 空列表 → 正常空态', () async {
      final c = controllerOf({'success': true, 'threads': <dynamic>[]});
      await c.loadInitial();
      expect(c.state, LoadState.loaded);
      expect(c.items, isEmpty);
      expect(c.errorMessage, isNull);
    });

    test('单项坏数据不影响其余条目', () async {
      final c = controllerOf({
        'success': true,
        'threads': [
          {'threadId': 1, 'title': 'A'},
          'not-a-map', // 结构异常的一条
          {'threadId': 2, 'title': 'B'},
        ],
      });
      await c.loadInitial();
      expect(c.state, LoadState.loaded);
      expect(c.items.map((e) => e.threadId), [1, 2]);
    });

    test('翻页遇到 success:false → 回退页码并进入错误态', () async {
      var calls = 0;
      final c = ThreadListController(
        fetchFn: ({required page}) async {
          calls++;
          if (page == 1) {
            return {
              'success': true,
              'threads': [
                {'threadId': 1, 'title': 'A'},
              ],
            };
          }
          return {'success': false, 'message': '登录已过期'};
        },
      );
      await c.loadInitial();
      expect(c.page, 1);
      await c.nextPage();
      expect(calls, 2);
      expect(c.state, LoadState.error);
      expect(c.page, 1); // 回退，不是停在请求失败的页
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:mtbbs/core/utils/error_message.dart';

void main() {
  group('HTTP 状态码', () {
    test('404 → 内容不存在', () {
      final text = friendlyErrorMessage('HTTP 404');
      expect(text, contains('内容不存在'));
      expect(text, contains('404'));
    });

    test('403 → 访问受限', () {
      final text = friendlyErrorMessage('HTTP 403');
      expect(text, contains('访问受限'));
      expect(text, contains('403'));
    });

    test('401 / 429 / 5xx 各有独立文案', () {
      expect(friendlyErrorMessage('HTTP 401'), contains('登录已过期'));
      expect(friendlyErrorMessage('HTTP 429'), contains('请求过于频繁'));
      expect(friendlyErrorMessage('HTTP 502'), contains('服务器暂时不可用'));
    });

    test('兼容 statusCode / status code 写法', () {
      expect(friendlyErrorMessage('statusCode: 404'), contains('内容不存在'));
      expect(friendlyErrorMessage('status code 403'), contains('访问受限'));
    });

    test('兼容 Dio 默认的 status code of 写法', () {
      const raw =
          'DioException [bad response]: This exception was thrown because the '
          'response has a status code of 404 and RequestOptions.validateStatus '
          'was configured to throw for this status code.';
      expect(friendlyErrorMessage(raw), contains('内容不存在'));
    });
  });

  group('网络异常', () {
    test('超时', () {
      expect(
        friendlyErrorMessage('DioException [connection timeout]: ...'),
        contains('请求超时'),
      );
    });

    test('连接失败', () {
      expect(
        friendlyErrorMessage('SocketException: Failed host lookup'),
        contains('网络连接失败'),
      );
    });
  });

  group('保留可读信息 / 隐藏噪声', () {
    test('服务端中文提示原样保留', () {
      const message = '抱歉，指定的主题不存在或已被删除或正在被审核';
      expect(friendlyErrorMessage(message), message);
    });

    test('去掉 Exception 前缀', () {
      expect(friendlyErrorMessage('Exception: 帖子不存在'), '帖子不存在');
    });

    test('空字符串与原始 HTML 使用兜底文案', () {
      expect(friendlyErrorMessage(''), fallbackErrorMessage);
      expect(
        friendlyErrorMessage('<!DOCTYPE html><html><body>403</body></html>'),
        fallbackErrorMessage,
      );
    });

    test('超长且不可读的信息使用兜底文案', () {
      expect(friendlyErrorMessage('x' * 300), fallbackErrorMessage);
    });
  });
}

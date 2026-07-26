/// 通用用户名校验工具
///
/// 校验规则：
///   - 最短 3 个字符
///   - 最大 15 个字符（中文算 2 个字符）
///   - 可用字符：汉字、字母、数字、下划线
///   - 禁止字符：空格 % , * " < > & ( ) '
///   - 禁止值：Guest、游客（不区分大小写）
///   - 禁止包含文件路径特征（c:\con\con 等）
library;

/// 用户名校验结果
class UsernameValidationResult {
  final bool isValid;
  final String? errorMessage;

  const UsernameValidationResult({required this.isValid, this.errorMessage});
}

/// 用户名校验器
class UsernameValidator {
  UsernameValidator._();

  /// 最短长度
  static const int minLength = 3;

  /// 最大字符数（中文算 2 个字符时的上限）
  static const int maxLength = 15;

  /// 禁止字符集合
  static const _bannedChars = {
    ' ',
    '%',
    ',',
    '*',
    '"',
    '<',
    '>',
    '&',
    '(',
    ')',
    "'",
  };

  /// 可用字符正则：汉字、字母、数字、下划线
  static final _allowedPattern = RegExp(r'^[\u4e00-\u9fff\w]+$');

  /// 禁止值（不区分大小写）
  static const _bannedValues = ['guest', '游客'];

  /// 禁止的文件路径特征（不区分大小写）
  static final _bannedPathPattern = RegExp(
    r'^[a-z]:\\(?:con|prn|aux|nul|com\d|lpt\d)(?:\\|$)',
    caseSensitive: false,
  );

  /// 校验用户名，返回校验结果
  static UsernameValidationResult validate(String username) {
    if (username.isEmpty) {
      return const UsernameValidationResult(
        isValid: false,
        errorMessage: '用户名不能为空',
      );
    }

    // 检查禁止字符
    for (final ch in username.split('')) {
      if (_bannedChars.contains(ch)) {
        return UsernameValidationResult(
          isValid: false,
          errorMessage: '用户名包含非法字符「$ch」',
        );
      }
    }

    // 检查可用字符
    if (!_allowedPattern.hasMatch(username)) {
      return const UsernameValidationResult(
        isValid: false,
        errorMessage: '用户名只能包含汉字、字母、数字和下划线',
      );
    }

    // 计算长度：中文算 2，其他算 1
    final length = _calcLength(username);
    if (length < minLength) {
      return UsernameValidationResult(
        isValid: false,
        errorMessage: '用户名最少 $minLength 个字符（中文算 2 个）',
      );
    }
    if (length > maxLength) {
      return UsernameValidationResult(
        isValid: false,
        errorMessage: '用户名最多 $maxLength 个字符（中文算 2 个）',
      );
    }

    // 检查禁止值
    final lower = username.toLowerCase();
    for (final banned in _bannedValues) {
      if (lower == banned) {
        return UsernameValidationResult(
          isValid: false,
          errorMessage: '不允许使用此用户名',
        );
      }
    }

    // 检查文件路径特征
    if (_bannedPathPattern.hasMatch(lower)) {
      return const UsernameValidationResult(
        isValid: false,
        errorMessage: '用户名包含非法字符',
      );
    }

    return const UsernameValidationResult(isValid: true);
  }

  /// 计算用户名长度：中文（CJK 统一表意文字）算 2，其他算 1
  static int _calcLength(String username) {
    int len = 0;
    for (final rune in username.runes) {
      if (rune >= 0x4E00 && rune <= 0x9FFF) {
        len += 2; // 中文
      } else if (rune >= 0x3400 && rune <= 0x4DBF) {
        len += 2; // 中文扩展A
      } else {
        len += 1;
      }
    }
    return len;
  }

  /// 判断字符串是否为纯数字（用于区分 uid 和用户名）
  static bool isNumeric(String s) =>
      s.isNotEmpty && s.runes.every((r) => r >= 0x30 && r <= 0x39);
}

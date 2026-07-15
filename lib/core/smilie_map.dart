/// 全局 smilieId → insertText 映射
///
/// 纯 Dart，无 Flutter 依赖，可被 lib/api/ 下的 parse 文件引入。
/// 由 EmojiService 在加载表情数据后更新，Html2BBCode 自动读取。
class SmilieMap {
  static Map<String, String> _idMap = {};

  /// smilieId → insertText（如 "1240" → "[呵呵]"）
  static Map<String, String> get idMap => _idMap;

  /// 由 EmojiService 在加载时调用
  static void update(Map<String, String> map) {
    _idMap = map;
  }
}

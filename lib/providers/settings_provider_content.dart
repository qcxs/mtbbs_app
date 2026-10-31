part of 'settings_provider.dart';

/// [SettingsProvider] 的内容 / 展示类设置写操作
/// （BBCode 禁用标签、主题、头像与图片宽度等）
extension SettingsContent on SettingsProvider {
  Future<void> setDisabledBbcodeTags(Set<String> tags) async {
    _disabledBbcodeTags = Set.from(tags);
    await _persistApp();
    _notify();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    await _persistApp();
    _notify();
  }

  Future<void> setSeedColor(Color color) async {
    _seedColor = color;
    await _persistApp();
    _notify();
  }

  Future<void> setPureBlackTheme(bool value) async {
    _isPureBlackTheme = value;
    await _persistApp();
    _notify();
  }

  Future<void> setShowAvatars(bool value) async {
    _showAvatars = value;
    await _persistApp();
    _notify();
  }

  Future<void> setAvatarSizeMode(AvatarSizeMode mode) async {
    _avatarSizeMode = mode;
    await _persistApp();
    _notify();
  }

  Future<void> setMaxImageWidth(int px) async {
    _maxImageWidth = px.clamp(100, 2000);
    await _persistApp();
    _notify();
  }

  /// 分享图正文最大高度（逻辑像素）
  Future<void> setShareImageMaxHeight(int px) async {
    _shareImageMaxHeight = px.clamp(1000, 100000);
    await _persistApp();
    _notify();
  }

  /// 代码块折叠态最大行数（0 = 不限制）
  Future<void> setCodeBlockMaxLines(int lines) async {
    _codeBlockMaxLines = lines.clamp(0, 200);
    await _persistApp();
    _notify();
  }

  /// 楼层内评分区最多显示条数（0 = 不限制）
  Future<void> setRatingMaxRows(int rows) async {
    _ratingMaxRows = rows.clamp(0, 100);
    await _persistApp();
    _notify();
  }

  /// 开关「只生成内容图」
  Future<void> setShareImageContentOnly(bool value) async {
    _shareImageContentOnly = value;
    await _persistApp();
    _notify();
  }
}

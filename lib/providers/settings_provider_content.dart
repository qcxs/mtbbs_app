part of 'settings_provider.dart';

/// [SettingsProvider] 的内容 / 展示类设置写操作
/// （BBCode 禁用标签、主题、头像与图片宽度等）
extension SettingsContent on SettingsProvider {
  Future<void> setDisabledBbcodeTags(Set<String> tags) async {
    _disabledBbcodeTags = Set.from(tags);
    await _db.setDisabledBbcodeRaw(jsonEncode(tags.toList()));
    _notify();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    await _db.setSetting('themeMode', mode.name);
    _notify();
  }

  Future<void> setSeedColor(Color color) async {
    _seedColor = color;
    await _db.setSettingInt('seedColor', color.toARGB32());
    _notify();
  }

  Future<void> setPureBlackTheme(bool value) async {
    _isPureBlackTheme = value;
    await _db.setSettingBool('pureBlackTheme', value);
    _notify();
  }

  Future<void> setShowAvatars(bool value) async {
    _showAvatars = value;
    await _db.setSettingBool('showAvatars', value);
    _notify();
  }

  Future<void> setAvatarSizeMode(AvatarSizeMode mode) async {
    _avatarSizeMode = mode;
    await _db.setSetting('avatarSizeMode', mode.value);
    _notify();
  }

  Future<void> setMaxImageWidth(int px) async {
    _maxImageWidth = px.clamp(100, 2000);
    await _db.setSettingInt('maxImageWidth', _maxImageWidth);
    _notify();
  }
}

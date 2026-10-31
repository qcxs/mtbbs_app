import 'package:flutter/material.dart';
import 'package:mtbbs/config/notice_config.dart';
import 'package:mtbbs/config/toolbar_config.dart';
import 'package:mtbbs/core/app/avatar_url.dart';
import 'package:mtbbs/core/app/default_config.dart';
import 'package:mtbbs/core/utils/shortcut_helper.dart';
import 'package:mtbbs/models/managed_item.dart';
import 'package:mtbbs/models/settings/settings_defaults.dart';

/// 应用设置（与站点、账号无关）
///
/// 持久化为一份 JSON 文档，见 `SettingsRepository`。
class AppSettings {
  final int schemaVersion;
  final String currentSiteHost;

  final AppearanceSettings appearance;
  final StartupSettings startup;
  final ReadingSettings reading;
  final EditorSettings editor;
  final StorageSettings storage;
  final NoticeSettings notice;
  final ShareSettings share;
  final HistorySettings history;
  final AdvancedSettings advanced;

  const AppSettings({
    this.schemaVersion = 1,
    this.currentSiteHost = '',
    required this.appearance,
    required this.startup,
    required this.reading,
    required this.editor,
    required this.storage,
    required this.notice,
    required this.share,
    required this.history,
    required this.advanced,
  });

  static AppSettings defaults() => AppSettings(
    appearance: AppearanceSettings.defaults(),
    startup: StartupSettings.defaults(),
    reading: ReadingSettings.defaults(),
    editor: EditorSettings.defaults(),
    storage: StorageSettings.defaults(),
    notice: NoticeSettings.defaults(),
    share: ShareSettings.defaults(),
    history: HistorySettings.defaults(),
    advanced: AdvancedSettings.defaults(),
  );

  Map<String, dynamic> toMap() => {
    'schemaVersion': schemaVersion,
    'currentSiteHost': currentSiteHost,
    'appearance': appearance.toMap(),
    'startup': startup.toMap(),
    'reading': reading.toMap(),
    'editor': editor.toMap(),
    'storage': storage.toMap(),
    'notice': notice.toMap(),
    'share': share.toMap(),
    'history': history.toMap(),
    'advanced': advanced.toMap(),
  };

  factory AppSettings.fromMap(Map<String, dynamic> map) {
    Map<String, dynamic> sub(String key) =>
        (map[key] as Map?)?.cast<String, dynamic>() ?? const {};
    return AppSettings(
      schemaVersion: (map['schemaVersion'] as num?)?.toInt() ?? 1,
      currentSiteHost: map['currentSiteHost']?.toString() ?? '',
      appearance: AppearanceSettings.fromMap(sub('appearance')),
      startup: StartupSettings.fromMap(sub('startup')),
      reading: ReadingSettings.fromMap(sub('reading')),
      editor: EditorSettings.fromMap(sub('editor')),
      storage: StorageSettings.fromMap(sub('storage')),
      notice: NoticeSettings.fromMap(sub('notice')),
      share: ShareSettings.fromMap(sub('share')),
      history: HistorySettings.fromMap(sub('history')),
      advanced: AdvancedSettings.fromMap(sub('advanced')),
    );
  }
}

class AppearanceSettings {
  final String themeMode;
  final int seedColor;
  final bool pureBlackTheme;
  final bool showAvatars;
  final String avatarSizeMode;
  final int maxImageWidth;

  const AppearanceSettings({
    required this.themeMode,
    required this.seedColor,
    required this.pureBlackTheme,
    required this.showAvatars,
    required this.avatarSizeMode,
    required this.maxImageWidth,
  });

  factory AppearanceSettings.defaults() => const AppearanceSettings(
    themeMode: 'system',
    seedColor: 0xFF9E9E9E,
    pureBlackTheme: false,
    showAvatars: true,
    avatarSizeMode: 'middle',
    maxImageWidth: 600,
  );

  ThemeMode get themeModeValue => ThemeMode.values.firstWhere(
    (m) => m.name == themeMode,
    orElse: () => ThemeMode.system,
  );

  Color get seedColorValue => Color(seedColor);

  AvatarSizeMode get avatarSizeModeValue =>
      AvatarSizeMode.fromValue(avatarSizeMode);

  Map<String, dynamic> toMap() => {
    'themeMode': themeMode,
    'seedColor': seedColor,
    'pureBlackTheme': pureBlackTheme,
    'showAvatars': showAvatars,
    'avatarSizeMode': avatarSizeMode,
    'maxImageWidth': maxImageWidth,
  };

  factory AppearanceSettings.fromMap(Map<String, dynamic> map) {
    final d = AppearanceSettings.defaults();
    return AppearanceSettings(
      themeMode: map['themeMode']?.toString() ?? d.themeMode,
      seedColor: (map['seedColor'] as num?)?.toInt() ?? d.seedColor,
      pureBlackTheme: map['pureBlackTheme'] as bool? ?? d.pureBlackTheme,
      showAvatars: map['showAvatars'] as bool? ?? d.showAvatars,
      avatarSizeMode: map['avatarSizeMode']?.toString() ?? d.avatarSizeMode,
      maxImageWidth: (map['maxImageWidth'] as num?)?.toInt() ?? d.maxImageWidth,
    );
  }
}

class StartupSettings {
  final int defaultTabIndex;
  final bool doubleBackExit;
  final List<ManagedItem> guideTabs;
  final List<ManagedItem> homeSections;
  final List<ManagedItem> noticeTabs;
  final bool autoFrequentTabs;
  final Map<String, Map<String, int>> tabUsage;

  const StartupSettings({
    required this.defaultTabIndex,
    required this.doubleBackExit,
    required this.guideTabs,
    required this.homeSections,
    required this.noticeTabs,
    required this.autoFrequentTabs,
    required this.tabUsage,
  });

  factory StartupSettings.defaults() => StartupSettings(
    defaultTabIndex: 0,
    doubleBackExit: true,
    guideTabs: defaultGuideTabs(),
    homeSections: defaultHomeSections(),
    noticeTabs: defaultNoticeTabs(),
    autoFrequentTabs: true,
    tabUsage: const {},
  );

  Map<String, dynamic> toMap() => {
    'defaultTabIndex': defaultTabIndex,
    'doubleBackExit': doubleBackExit,
    'guideTabs': guideTabs.map((e) => e.toJson()).toList(),
    'homeSections': homeSections.map((e) => e.toJson()).toList(),
    'noticeTabs': noticeTabs.map((e) => e.toJson()).toList(),
    'autoFrequentTabs': autoFrequentTabs,
    'tabUsage': tabUsage,
  };

  factory StartupSettings.fromMap(Map<String, dynamic> map) {
    final d = StartupSettings.defaults();
    List<ManagedItem> items(String key, List<ManagedItem> fallback) {
      final raw = map[key];
      if (raw is! List) return fallback;
      return raw
          .whereType<Map>()
          .map((e) => ManagedItem.fromJson(e.cast<String, dynamic>()))
          .where((e) => e.id.isNotEmpty)
          .toList();
    }

    final usage = <String, Map<String, int>>{};
    final rawUsage = map['tabUsage'];
    if (rawUsage is Map) {
      for (final e in rawUsage.entries) {
        final inner = e.value;
        if (inner is! Map) continue;
        usage[e.key.toString()] = {
          for (final kv in inner.entries)
            kv.key.toString(): (kv.value as num).toInt(),
        };
      }
    }
    return StartupSettings(
      defaultTabIndex:
          (map['defaultTabIndex'] as num?)?.toInt() ?? d.defaultTabIndex,
      doubleBackExit: map['doubleBackExit'] as bool? ?? d.doubleBackExit,
      guideTabs: items(
        'guideTabs',
        d.guideTabs,
      ).where((e) => kSettingsTabLabels.containsKey(e.id)).toList(),
      homeSections: items(
        'homeSections',
        d.homeSections,
      ).where((e) => homeSectionIds.contains(e.id)).toList(),
      noticeTabs: items(
        'noticeTabs',
        d.noticeTabs,
      ).where((e) => noticeTabIds.contains(e.id)).toList(),
      autoFrequentTabs: map['autoFrequentTabs'] as bool? ?? d.autoFrequentTabs,
      tabUsage: usage,
    );
  }
}

class ReadingSettings {
  final double fontSize;
  final int codeBlockMaxLines;
  final int ratingMaxRows;
  final bool autoDetectUrls;
  final Set<String> disabledBbcodeTags;

  const ReadingSettings({
    required this.fontSize,
    required this.codeBlockMaxLines,
    required this.ratingMaxRows,
    required this.autoDetectUrls,
    required this.disabledBbcodeTags,
  });

  factory ReadingSettings.defaults() => const ReadingSettings(
    fontSize: 16,
    codeBlockMaxLines: 18,
    ratingMaxRows: 10,
    autoDetectUrls: true,
    disabledBbcodeTags: {},
  );

  Map<String, dynamic> toMap() => {
    'fontSize': fontSize,
    'codeBlockMaxLines': codeBlockMaxLines,
    'ratingMaxRows': ratingMaxRows,
    'autoDetectUrls': autoDetectUrls,
    'disabledBbcodeTags': disabledBbcodeTags.toList(),
  };

  factory ReadingSettings.fromMap(Map<String, dynamic> map) {
    final d = ReadingSettings.defaults();
    final tags = map['disabledBbcodeTags'];
    return ReadingSettings(
      fontSize: (map['fontSize'] as num?)?.toDouble() ?? d.fontSize,
      codeBlockMaxLines:
          (map['codeBlockMaxLines'] as num?)?.toInt() ?? d.codeBlockMaxLines,
      ratingMaxRows: (map['ratingMaxRows'] as num?)?.toInt() ?? d.ratingMaxRows,
      autoDetectUrls: map['autoDetectUrls'] as bool? ?? d.autoDetectUrls,
      disabledBbcodeTags: tags is List
          ? tags.map((e) => e.toString()).toSet()
          : d.disabledBbcodeTags,
    );
  }
}

class EditorSettings {
  final bool threadMiniEditor;
  final bool editorStartupCheck;
  final bool toolbarShortcutWhenHidden;
  final List<ManagedItem> quickReplies;
  final List<ManagedItem> toolbarItems;
  final Map<String, String> shortcuts;
  final Map<String, String> toolbarShortcuts;
  final int minSnapshotWordCount;
  final int autoSaveInterval;
  final int maxAutoSnapshots;

  const EditorSettings({
    required this.threadMiniEditor,
    required this.editorStartupCheck,
    required this.toolbarShortcutWhenHidden,
    required this.quickReplies,
    required this.toolbarItems,
    required this.shortcuts,
    required this.toolbarShortcuts,
    required this.minSnapshotWordCount,
    required this.autoSaveInterval,
    required this.maxAutoSnapshots,
  });

  factory EditorSettings.defaults() => EditorSettings(
    threadMiniEditor: true,
    editorStartupCheck: true,
    toolbarShortcutWhenHidden: true,
    quickReplies: defaultQuickReplies(),
    toolbarItems: const [],
    shortcuts: Map.from(ShortcutHelper.defaults),
    toolbarShortcuts: defaultToolbarShortcuts(),
    minSnapshotWordCount: 10,
    autoSaveInterval: 30,
    maxAutoSnapshots: 10,
  );

  Map<String, dynamic> toMap() => {
    'threadMiniEditor': threadMiniEditor,
    'editorStartupCheck': editorStartupCheck,
    'toolbarShortcutWhenHidden': toolbarShortcutWhenHidden,
    'quickReplies': quickReplies.map((e) => e.toJson()).toList(),
    'toolbarItems': toolbarItems.map((e) => e.toJson()).toList(),
    'shortcuts': shortcuts,
    'toolbarShortcuts': toolbarShortcuts,
    'minSnapshotWordCount': minSnapshotWordCount,
    'autoSaveInterval': autoSaveInterval,
    'maxAutoSnapshots': maxAutoSnapshots,
  };

  factory EditorSettings.fromMap(Map<String, dynamic> map) {
    final d = EditorSettings.defaults();
    List<ManagedItem> items(String key, List<ManagedItem> fallback) {
      final raw = map[key];
      if (raw is! List) return fallback;
      return raw
          .whereType<Map>()
          .map((e) => ManagedItem.fromJson(e.cast<String, dynamic>()))
          .where((e) => e.id.isNotEmpty)
          .toList();
    }

    Map<String, String> strMap(String key, Map<String, String> fallback) {
      final raw = map[key];
      if (raw is! Map) return fallback;
      return raw.map((k, v) => MapEntry(k.toString(), v.toString()));
    }

    return EditorSettings(
      threadMiniEditor: map['threadMiniEditor'] as bool? ?? d.threadMiniEditor,
      editorStartupCheck:
          map['editorStartupCheck'] as bool? ?? d.editorStartupCheck,
      toolbarShortcutWhenHidden:
          map['toolbarShortcutWhenHidden'] as bool? ??
          d.toolbarShortcutWhenHidden,
      quickReplies: items('quickReplies', d.quickReplies),
      toolbarItems: items('toolbarItems', d.toolbarItems),
      shortcuts: strMap('shortcuts', d.shortcuts),
      toolbarShortcuts: strMap('toolbarShortcuts', d.toolbarShortcuts),
      minSnapshotWordCount:
          (map['minSnapshotWordCount'] as num?)?.toInt() ??
          d.minSnapshotWordCount,
      autoSaveInterval:
          (map['autoSaveInterval'] as num?)?.toInt() ?? d.autoSaveInterval,
      maxAutoSnapshots:
          (map['maxAutoSnapshots'] as num?)?.toInt() ?? d.maxAutoSnapshots,
    );
  }
}

class StorageSettings {
  final int avatarCacheDays;
  final int emojiCacheDays;
  final int imageCacheDays;
  final int medalCacheDays;
  final int threadCacheDays;
  final bool threadCacheEnabled;
  final int threadCacheMaxVersions;
  final int threadCacheMaxKB;

  const StorageSettings({
    required this.avatarCacheDays,
    required this.emojiCacheDays,
    required this.imageCacheDays,
    required this.medalCacheDays,
    required this.threadCacheDays,
    required this.threadCacheEnabled,
    required this.threadCacheMaxVersions,
    required this.threadCacheMaxKB,
  });

  factory StorageSettings.defaults() {
    final cache = DefaultConfig.instance.cacheExpireDays;
    final thread = DefaultConfig.instance.threadCacheConfig;
    return StorageSettings(
      avatarCacheDays: cache.avatar,
      emojiCacheDays: cache.emoji,
      imageCacheDays: cache.image,
      medalCacheDays: cache.medal,
      threadCacheDays: thread.expireDays,
      threadCacheEnabled: true,
      threadCacheMaxVersions: 3,
      threadCacheMaxKB: thread.maxBytesPerThread ~/ 1024,
    );
  }

  Map<String, dynamic> toMap() => {
    'avatarCacheDays': avatarCacheDays,
    'emojiCacheDays': emojiCacheDays,
    'imageCacheDays': imageCacheDays,
    'medalCacheDays': medalCacheDays,
    'threadCacheDays': threadCacheDays,
    'threadCacheEnabled': threadCacheEnabled,
    'threadCacheMaxVersions': threadCacheMaxVersions,
    'threadCacheMaxKB': threadCacheMaxKB,
  };

  factory StorageSettings.fromMap(Map<String, dynamic> map) {
    final d = StorageSettings.defaults();
    return StorageSettings(
      avatarCacheDays:
          (map['avatarCacheDays'] as num?)?.toInt() ?? d.avatarCacheDays,
      emojiCacheDays:
          (map['emojiCacheDays'] as num?)?.toInt() ?? d.emojiCacheDays,
      imageCacheDays:
          (map['imageCacheDays'] as num?)?.toInt() ?? d.imageCacheDays,
      medalCacheDays:
          (map['medalCacheDays'] as num?)?.toInt() ?? d.medalCacheDays,
      threadCacheDays:
          (map['threadCacheDays'] as num?)?.toInt() ?? d.threadCacheDays,
      threadCacheEnabled:
          map['threadCacheEnabled'] as bool? ?? d.threadCacheEnabled,
      threadCacheMaxVersions:
          (map['threadCacheMaxVersions'] as num?)?.toInt() ??
          d.threadCacheMaxVersions,
      threadCacheMaxKB:
          (map['threadCacheMaxKB'] as num?)?.toInt() ?? d.threadCacheMaxKB,
    );
  }
}

class NoticeSettings {
  final int badgeMode;
  final bool checkEnabled;
  final Set<String> badgeGroups;

  const NoticeSettings({
    required this.badgeMode,
    required this.checkEnabled,
    required this.badgeGroups,
  });

  factory NoticeSettings.defaults() => NoticeSettings(
    badgeMode: NoticeBadgeMode.number.index,
    checkEnabled: true,
    badgeGroups: noticeGroupIds,
  );

  Map<String, dynamic> toMap() => {
    'badgeMode': badgeMode,
    'checkEnabled': checkEnabled,
    'badgeGroups': badgeGroups.toList(),
  };

  factory NoticeSettings.fromMap(Map<String, dynamic> map) {
    final d = NoticeSettings.defaults();
    final groups = map['badgeGroups'];
    return NoticeSettings(
      badgeMode: (map['badgeMode'] as num?)?.toInt() ?? d.badgeMode,
      checkEnabled: map['checkEnabled'] as bool? ?? d.checkEnabled,
      badgeGroups: groups is List
          ? groups
                .map((e) => e.toString())
                .where(noticeGroupIds.contains)
                .toSet()
          : d.badgeGroups,
    );
  }
}

class ShareSettings {
  final int maxHeight;
  final bool contentOnly;

  const ShareSettings({required this.maxHeight, required this.contentOnly});

  factory ShareSettings.defaults() =>
      const ShareSettings(maxHeight: 8000, contentOnly: false);

  Map<String, dynamic> toMap() => {
    'maxHeight': maxHeight,
    'contentOnly': contentOnly,
  };

  factory ShareSettings.fromMap(Map<String, dynamic> map) {
    final d = ShareSettings.defaults();
    return ShareSettings(
      maxHeight: (map['maxHeight'] as num?)?.toInt() ?? d.maxHeight,
      contentOnly: map['contentOnly'] as bool? ?? d.contentOnly,
    );
  }
}

class HistorySettings {
  final int maxCount;
  final String formatThread;
  final String formatUser;
  final String titleFormatThread;
  final String titleFormatUser;
  final String titleFormatMythread;
  final String titleFormatReply;

  const HistorySettings({
    required this.maxCount,
    required this.formatThread,
    required this.formatUser,
    required this.titleFormatThread,
    required this.titleFormatUser,
    required this.titleFormatMythread,
    required this.titleFormatReply,
  });

  factory HistorySettings.defaults() => const HistorySettings(
    maxCount: 200,
    formatThread: '{title}',
    formatUser: '{nickname}',
    titleFormatThread: '{title}',
    titleFormatUser: '{nickname}',
    titleFormatMythread: '{typeLabel}(UID={uid}, 第{page}页)',
    titleFormatReply: '{typeLabel}(UID={uid}, 第{page}页)',
  );

  Map<String, dynamic> toMap() => {
    'maxCount': maxCount,
    'formatThread': formatThread,
    'formatUser': formatUser,
    'titleFormatThread': titleFormatThread,
    'titleFormatUser': titleFormatUser,
    'titleFormatMythread': titleFormatMythread,
    'titleFormatReply': titleFormatReply,
  };

  factory HistorySettings.fromMap(Map<String, dynamic> map) {
    final d = HistorySettings.defaults();
    return HistorySettings(
      maxCount: (map['maxCount'] as num?)?.toInt() ?? d.maxCount,
      formatThread: map['formatThread']?.toString() ?? d.formatThread,
      formatUser: map['formatUser']?.toString() ?? d.formatUser,
      titleFormatThread:
          map['titleFormatThread']?.toString() ?? d.titleFormatThread,
      titleFormatUser: map['titleFormatUser']?.toString() ?? d.titleFormatUser,
      titleFormatMythread:
          map['titleFormatMythread']?.toString() ?? d.titleFormatMythread,
      titleFormatReply:
          map['titleFormatReply']?.toString() ?? d.titleFormatReply,
    );
  }
}

class AdvancedSettings {
  final bool autoCheckUpdate;
  final String skippedUpdateVersion;
  final bool developerMode;

  const AdvancedSettings({
    required this.autoCheckUpdate,
    required this.skippedUpdateVersion,
    required this.developerMode,
  });

  factory AdvancedSettings.defaults() => const AdvancedSettings(
    autoCheckUpdate: true,
    skippedUpdateVersion: '',
    developerMode: false,
  );

  Map<String, dynamic> toMap() => {
    'autoCheckUpdate': autoCheckUpdate,
    'skippedUpdateVersion': skippedUpdateVersion,
    'developerMode': developerMode,
  };

  factory AdvancedSettings.fromMap(Map<String, dynamic> map) {
    final d = AdvancedSettings.defaults();
    return AdvancedSettings(
      autoCheckUpdate: map['autoCheckUpdate'] as bool? ?? d.autoCheckUpdate,
      skippedUpdateVersion:
          map['skippedUpdateVersion']?.toString() ?? d.skippedUpdateVersion,
      developerMode: map['developerMode'] as bool? ?? d.developerMode,
    );
  }
}

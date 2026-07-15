import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// MT 图床服务 — 管理认证、上传、历史记录
///
/// 懒加载：首次上传时自动 GET / → 从 Set-Cookie 获取 session，
/// 从 HTML <meta name="csrf-token"> 获取 CSRF token。
/// 认证信息缓存约 2 小时，过期或 401 时自动重新获取。
class MtImageHosting {
  static const _baseUrl = 'https://img.binmt.cc';
  static const _uploadUrl = '$_baseUrl/upload';
  static const _historyKey = 'mt_image_history';

  final Dio _dio;

  String? _cookie;
  String? _csrfToken;
  DateTime? _authExpiry;

  MtImageHosting()
    : _dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 30),
          sendTimeout: const Duration(seconds: 30),
          responseType: ResponseType.plain,
        ),
      );

  // ==================== 认证 ====================

  /// 是否已验证且未过期
  bool get isAuthed =>
      _cookie != null &&
      _csrfToken != null &&
      _authExpiry != null &&
      DateTime.now().isBefore(_authExpiry!);

  /// 认证（获取 cookie + csrf token），支持 [onStatus] 回调显示状态
  Future<bool> auth({void Function(String status)? onStatus}) async {
    if (isAuthed) return true;
    onStatus?.call('验证中…');
    return _fetchCredential(onStatus: onStatus);
  }

  /// GET / → 取 cookie + 从 HTML meta 提取 csrf-token
  Future<bool> _fetchCredential({
    void Function(String status)? onStatus,
  }) async {
    try {
      onStatus?.call('连接中…');
      final resp = await _dio.getUri(
        Uri.parse(_baseUrl),
        options: Options(
          responseType: ResponseType.plain,
          // 禁止自动处理 cookie，由我们手动管理
          listFormat: ListFormat.csv,
        ),
      );

      final html = resp.data as String?;
      if (html == null || html.isEmpty) {
        onStatus?.call('认证失败：空响应');
        return false;
      }

      // 1. 从 Set-Cookie 提取所有 cookie
      final setCookies = resp.headers['set-cookie'];
      if (setCookies == null || setCookies.isEmpty) {
        onStatus?.call('认证失败：无 Cookie');
        return false;
      }

      final cookieParts = <String>[];
      for (final raw in setCookies) {
        final eqIdx = raw.indexOf('=');
        if (eqIdx < 0) continue;
        final semiIdx = raw.indexOf(';', eqIdx);
        final kv = semiIdx > 0 ? raw.substring(0, semiIdx) : raw.trim();
        cookieParts.add(kv);
      }
      if (cookieParts.isEmpty) {
        onStatus?.call('认证失败：Cookie 为空');
        return false;
      }
      _cookie = cookieParts.join('; ');

      // 2. 从 HTML 解析 <meta name="csrf-token" content="...">
      final csrfMatch = RegExp(
        r'''<meta\s+name="csrf-token"\s+content="([^"]+)"''',
        caseSensitive: false,
      ).firstMatch(html);

      if (csrfMatch == null) {
        onStatus?.call('认证失败：未找到 CSRF token');
        return false;
      }

      _csrfToken = csrfMatch.group(1);
      _authExpiry = DateTime.now().add(const Duration(hours: 1, minutes: 50));

      onStatus?.call('验证成功');
      return true;
    } on DioException catch (e) {
      _cookie = null;
      _csrfToken = null;
      _authExpiry = null;
      onStatus?.call('网络错误：${e.message}');
      return false;
    } catch (e) {
      _cookie = null;
      _csrfToken = null;
      _authExpiry = null;
      onStatus?.call('认证失败');
      return false;
    }
  }

  // ==================== 上传 ====================

  /// 上传单张图片
  ///
  /// 返回 [MtUploadResult] 或 null。
  /// [onProgress] 进度回调 (sent, total)。
  Future<MtUploadResult?> upload(
    String filePath, {
    void Function(int sent, int total)? onProgress,
  }) async {
    final file = File(filePath);
    if (!file.existsSync()) return null;

    final filename = file.path.split(RegExp(r'[/\\]')).last;

    try {
      final form = FormData.fromMap({
        'strategy_id': '2',
        'file': await MultipartFile.fromFile(filePath, filename: filename),
      });

      final resp = await _dio.post(
        _uploadUrl,
        data: form,
        options: Options(
          responseType: ResponseType.json,
          headers: {
            'x-csrf-token': _csrfToken ?? '',
            'x-requested-with': 'XMLHttpRequest',
            'accept': 'application/json, text/javascript, */*; q=0.01',
            'cookie': _cookie ?? '',
            'referer': _baseUrl,
            'origin': _baseUrl,
          },
        ),
        onSendProgress: onProgress,
      );

      if (resp.statusCode != 200) return null;

      final body = resp.data;
      if (body is Map && body['status'] == true) {
        final data = body['data'] as Map?;
        if (data == null) return null;

        final links = data['links'] as Map?;
        final result = MtUploadResult(
          url: links?['url'] as String? ?? '',
          bbcode: links?['bbcode'] as String? ?? '',
          originName: data['origin_name'] as String? ?? filename,
          size: (data['size'] as num?)?.toDouble() ?? 0.0,
          thumbnailUrl: links?['thumbnail_url'] as String? ?? '',
          uploadedAt: DateTime.now(),
        );

        await _addHistory(result);
        return result;
      }

      // token 过期 → 清除缓存
      if (body is Map && _isAuthError(body)) {
        _cookie = null;
        _csrfToken = null;
        _authExpiry = null;
      }

      return null;
    } on DioException {
      return null;
    }
  }

  bool _isAuthError(Map body) {
    final msg = (body['message'] as String?)?.toLowerCase() ?? '';
    return msg.contains('csrf') ||
        msg.contains('token') ||
        msg.contains('auth');
  }

  // ==================== 历史记录 ====================

  /// 获取历史记录
  ///
  /// [includeHidden] 为 false 时只返回未隐藏的记录（编辑器用），
  /// 默认最多返回 20 条，管理页面可传 [limit] 获取全部。
  Future<List<MtUploadResult>> getHistory({
    int limit = 20,
    bool includeHidden = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_historyKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      var list = jsonDecode(raw) as List;
      var results = list.map((e) => MtUploadResult.fromJson(e)).toList()
        ..sort((a, b) => b.uploadedAt.compareTo(a.uploadedAt));

      if (!includeHidden) results = results.where((r) => !r.hidden).toList();
      if (results.length > limit) results = results.sublist(0, limit);
      return results;
    } catch (_) {
      return [];
    }
  }

  Future<void> _addHistory(MtUploadResult result) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_historyKey);
    final list = (raw != null && raw.isNotEmpty)
        ? (jsonDecode(raw) as List)
        : <dynamic>[];

    list.removeWhere((e) => (e as Map)['url'] == result.url);
    list.insert(0, result.toJson());
    if (list.length > 200) list.removeRange(200, list.length);

    await prefs.setString(_historyKey, jsonEncode(list));
  }

  /// 永久删除单条历史
  Future<void> deleteHistory(String url) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_historyKey);
    if (raw == null || raw.isEmpty) return;
    final list = jsonDecode(raw) as List;
    list.removeWhere((e) => (e as Map)['url'] == url);
    await prefs.setString(_historyKey, jsonEncode(list));
  }

  /// 切换隐藏/显示
  Future<void> toggleHistoryHidden(String url) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_historyKey);
    if (raw == null || raw.isEmpty) return;
    final list = jsonDecode(raw) as List;
    for (final e in list) {
      final m = e as Map;
      if (m['url'] == url) {
        m['hidden'] = !(m['hidden'] == true);
        break;
      }
    }
    await prefs.setString(_historyKey, jsonEncode(list));
  }
}

/// MT 图床上传结果
class MtUploadResult {
  final String url;
  final String bbcode;
  final String originName;
  final double size;
  final String thumbnailUrl;
  final DateTime uploadedAt;
  final bool hidden;

  const MtUploadResult({
    required this.url,
    required this.bbcode,
    required this.originName,
    required this.size,
    required this.thumbnailUrl,
    required this.uploadedAt,
    this.hidden = false,
  });

  Map<String, dynamic> toJson() => {
    'url': url,
    'bbcode': bbcode,
    'originName': originName,
    'size': size,
    'thumbnailUrl': thumbnailUrl,
    'uploadedAt': uploadedAt.toIso8601String(),
    'hidden': hidden,
  };

  factory MtUploadResult.fromJson(Map<String, dynamic> json) => MtUploadResult(
    url: json['url'] as String? ?? '',
    bbcode: json['bbcode'] as String? ?? '',
    originName: json['originName'] as String? ?? '',
    size: (json['size'] as num?)?.toDouble() ?? 0.0,
    thumbnailUrl: json['thumbnailUrl'] as String? ?? '',
    uploadedAt:
        DateTime.tryParse(json['uploadedAt'] as String? ?? '') ??
        DateTime.now(),
    hidden: json['hidden'] == true,
  );

  MtUploadResult copyWith({bool? hidden}) => MtUploadResult(
    url: url,
    bbcode: bbcode,
    originName: originName,
    size: size,
    thumbnailUrl: thumbnailUrl,
    uploadedAt: uploadedAt,
    hidden: hidden ?? this.hidden,
  );

  String get sizeText {
    if (size < 1) return '${(size * 1024).toStringAsFixed(0)} KB';
    return '${size.toStringAsFixed(1)} MB';
  }
}

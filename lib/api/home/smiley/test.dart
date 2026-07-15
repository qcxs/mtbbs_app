import 'dart:io';
import 'package:dio/dio.dart';
import 'export.dart' as api;

/// 测试表情 API
///
/// 用法：
///   dart run lib/api/home/smiley/test.dart
///   dart run lib/api/home/smiley/test.dart --base-url=http://discuz.qcxs.top
void main(List<String> args) async {
  var baseUrl = 'https://bbs.binmt.cc';
  for (int i = 0; i < args.length; i++) {
    if (args[i] == '--base-url' && i + 1 < args.length) {
      baseUrl = args[i + 1];
    }
  }

  final dio = Dio(BaseOptions(baseUrl: baseUrl));

  try {
    final result = await api.fetchSmilies(dio);
    if (result['success'] != true) {
      stderr.writeln('失败: ${result['message']}');
      exit(1);
    }

    final groups = result['groups'] as List<dynamic>;
    final smilieIdMap = result['smilieIdMap'] as Map<String, dynamic>;
    final insertTextMap = result['insertTextMap'] as Map<String, dynamic>;

    print('站点: $baseUrl');
    print('分组数: ${groups.length}');
    print('表情总数: ${smilieIdMap.length}');
    print('');

    for (final g in groups) {
      final name = g['name'];
      final folder = g['folder'];
      final emojis = g['emojis'] as List<dynamic>;
      print('[$name] (folder: $folder, ${emojis.length}个)');
      for (final e in emojis.take(5)) {
        print('  ${e['smilieId']}: ${e['insertText']} → ${e['imageUrl']}');
      }
      if (emojis.length > 5) {
        print('  ... 还有 ${emojis.length - 5} 个');
      }
      print('');
    }

    // 验证 smilieIdMap 反向查找
    print('--- smilieIdMap 样例行 ---');
    smilieIdMap.entries.take(3).forEach((e) {
      print('  smilieId ${e.key} → insertText ${e.value}');
    });

    print('--- insertTextMap 样例行 ---');
    insertTextMap.entries.take(3).forEach((e) {
      print('  ${e.key} → ${e.value}');
    });
  } catch (e) {
    stderr.writeln('错误: $e');
    exit(1);
  }
}

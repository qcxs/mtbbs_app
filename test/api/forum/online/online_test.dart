import 'dart:io';
import 'package:dio/dio.dart';
import 'export.dart' as api;

void main(List<String> args) async {
  final baseUrl = args.isNotEmpty ? args[0] : 'https://bbs.binmt.cc';

  final dio = Dio(BaseOptions(baseUrl: baseUrl));
  final result = await api.fetchOnlineUsers(dio);

  if (result['success'] != true) {
    stderr.writeln('Error: ${result['message']}');
    exit(1);
  }

  final items = result['items'] as List;
  final stats = result['stats'] as String;

  print('Stats: $stats');
  print('Total: ${items.length}');
  print('');
  for (final item in items) {
    final m = item as Map<String, dynamic>;
    print('  [${m['type']}] ${m['username']} (${m['uid']}) — ${m['time']}');
  }
}

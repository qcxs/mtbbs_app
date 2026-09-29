import 'package:sembast/sembast_io.dart';
import 'package:mtbbs/core/app/app_paths.dart';
import 'package:mtbbs/models/editor_snapshot.dart';
import 'package:mtbbs/models/browse_record.dart';
import 'package:mtbbs/core/utils/logger.dart';

part 'database_helper_stores.dart';
part 'database_helper_kv.dart';
part 'database_helper_records.dart';

/// 数据库帮助类 — 基于 sembast（纯 Dart NoSQL）的统一持久化层
///
/// 全应用唯一持久化方案，替代 SharedPreferences。
/// 所有数据存储在单一 .db 文件中，按 Store 隔离。
///
/// sembast 100% Dart 实现，无需任何原生依赖，全平台开箱即用。
///
/// 各域的读写方法按域拆分到 part 中的 extension（见 database_helper_kv.dart /
/// database_helper_records.dart）；Store 常量见 database_helper_stores.dart。
class DatabaseHelper {
  DatabaseHelper._();
  static final DatabaseHelper instance = DatabaseHelper._();

  static Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _init();
    return _db!;
  }

  Future<Database> _init() async {
    final dbPath = await AppPaths.databasePath;
    final db = await databaseFactoryIo.openDatabase(dbPath);
    AppLogger.i('DB', 'opened: $dbPath');
    return db;
  }
}

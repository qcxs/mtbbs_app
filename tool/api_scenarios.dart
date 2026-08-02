/// 探针场景注册表（命令名 → 场景）
///
/// 按主题拆分为三个子模块，合并后对外接口不变：
/// - `scenarios/read_scenarios.dart`   只读场景（会话/导读/版块/帖子/用户/好友/消息/我的主题）
/// - `scenarios/write_scenarios.dart`  写操作（发帖/评论/回复/修改）
/// - `scenarios/debug_scenarios.dart`  调试（原始 HTTP）
///
/// 新增场景：在对应子模块注册即可，此处无需改动。
library;

import 'scenarios/debug_scenarios.dart';
import 'scenarios/read_scenarios.dart';
import 'scenarios/scenario_types.dart';
import 'scenarios/write_scenarios.dart';

export 'scenarios/scenario_types.dart' show ApiScenario;

/// 场景注册表（命令名 → 场景）
final Map<String, ApiScenario> scenarios = {
  ...readScenarios,
  ...writeScenarios,
  ...debugScenarios,
};

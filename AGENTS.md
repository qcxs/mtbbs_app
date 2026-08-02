# AGENTS.md — 给 AI 的项目导航

> 本文件供无项目上下文的 AI/人类在开始改代码前快速建立认知。
> **修改任何代码前，先查「任务 → 文档」路由表，读对应文档，再动手。**

## 项目一句话

Discuz（MT 论坛克米模板）的 Flutter 客户端。Discuz 无官方 API：`lib/api/` 按三文件规范（http/parse/export）抓取并解析 HTML/XML 为结构化 JSON，`widgets/bbcode` 层将 BBCode → AST → Widget 渲染。分层与管线见 `docs/01-概述与架构.md`。

## 铁律（违反会被打回）

1. **改代码前先读文档**：按下方路由表选读，`docs/07-经验教训.md` 收录全部踩坑，务必优先
2. **日志用 `AppLogger.{d/i/w/e}(tag, msg)`**，禁 `print`/`debugPrint`（lint 未强制，靠约定执行）
3. **import 用 `package:mtbbs/...` 绝对路径**，禁 `../` 相对导入（仅 barrel 文件的同目录 `export` 例外）
4. **网络图片必须走 `CachedNetworkImage` + 指定 `cacheManager`**（image/avatar/emoji 三层），禁 `Image.network()`、禁不带 cacheManager 的默认缓存
5. **持久化统一走 `DatabaseHelper`（sembast 单库）**，禁新增 SharedPreferences 依赖
6. **新增 API 必须三文件**：http 只管请求 / parse 纯解析（不打印列表日志）/ export 走 `parseWithLog` 统一输出日志
7. **验证闭环**：改完跑 `flutter analyze lib`；涉及真实请求用探针 `tool/api_probe_test.dart`（见 docs/10）

## 任务 → 文档路由表

| 任务类型 | 必读文档 |
|---------|---------|
| 首次接触项目 | 01（架构）+ 02（规范）+ 07（经验教训） |
| 新增 API（http/parse/export） | 02 + 10 + 11 |
| 写操作 API（发帖/评论/回复/修改/收藏） | 12 + 13 + 14 |
| 解析/渲染 Bug（BBCode、空白、布局） | 07（含三层测试诊断法） |
| 新增页面/功能 | 11（AI 冷启动手册） |
| 图片加载/缓存 | 01（图片缓存规范）+ 09 |
| 主题/夜间模式/配色 | 08 |
| 依赖行为确认/升级 | 09 |
| 状态管理/站点切换/持久化 | 04 |
| UA/解析策略 | 03 |
| 编辑器 | 06 + 12 |

## 文档阅读策略（省上下文）

- **必读**：01、02、07 —— 知识密度最高，决定代码是否"符合项目气质"
- **按需**：03/04/05/06/08/09/10/11/12/13/14 —— 遇到对应任务再读
- 每篇 docs 头部有「适用场景」标注，先看它再决定是否深入

## 验证闭环

- 静态检查：`flutter analyze lib`
- 真实请求：`flutter test tool/api_probe_test.dart --dart-define=cmd=help` 查看全部探针命令（docs/10）
- 渲染单测：`test/`（BBCode 渲染链路，docs/07 第 15-18 条）

# MT 论坛 — Flutter 客户端

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)

基于 Flutter 的 Discuz 论坛客户端，适配 **MT 论坛**（[bbs.binmt.cc](https://bbs.binmt.cc)）克米模板。

> 本项目使用 **GNU General Public License v3.0** 开源。  
> 允许自由使用、修改和分发，但**必须**：
> - 注明原作者及原始仓库
> - 修改后的版本也必须以 GPLv3 发布
> - 提供源代码

---

## 已实现功能

| 功能 | 说明 |
|------|------|
| **导读** | 最新/热门/精华/新帖列表 |
| **版块** | 版块分类浏览 + 帖子列表 |
| **帖子详情** | BBCode 渲染、评论、点赞、收藏、评分 |
| **编辑器** | 发帖/评论/回复/编辑，BBCode 工具栏，图片管理，MT 图床，粘贴图片上传，快照自动保存 |
| **社区** | 用户群组/列表 |
| **用户空间** | 个人资料、签名 |
| **多站点** | 多站点多账号切换 |
| **设置** | 自定义工具栏、快捷键、颜色主题、BBCode 渲染等 |
| **内置浏览器** | WebView 浏览 |
| **RSS** | 帖子列表 RSS |

## 运行环境

| 工具 | 版本 |
|------|------|
| Flutter | 3.44.2+ |
| Dart | 3.12.2+ |
| Android SDK | compileSdk 跟随 Flutter 默认（当前 36） |
| Windows | Windows 10+ (x64)，Visual Studio 2022（见下方打包前置） |

```bash
# 检查代码
flutter analyze lib/

# 运行（Windows x64）
flutter run -d windows

# 运行（Android）
flutter run -d <device_id>

# 测试 API（真实请求探针，docs/10-API探针使用规范.md）
flutter test tool/api_probe_test.dart --dart-define=cmd=help
```

## 本地打包

> 版本号统一由 `scripts/version.ps1` 从 pubspec.yaml（版本名）+ git 提交数（构建号）自动生成，详见 `docs/15-版本发布.md`。不要手动改安装包/关于页里的版本号。

### Windows x64（安装包）

#### 前置条件

- Visual Studio **2022**（17.13+，含**使用 C++ 的桌面开发**工作负载；工具链对齐说明见 `docs/15-版本发布.md`，勿用 VS2026）
- [Inno Setup](https://jrsoftware.org/isinfo.php) 6+（Unicode 版），安装后确保 `iscc` 在 PATH 中

#### 步骤

```powershell
# 1. 生成版本信息（版本名取自 pubspec.yaml）
powershell -ExecutionPolicy Bypass -File scripts\version.ps1

# 2. 编译 release 版
flutter build windows --release `
  --dart-define-from-file=mtbbs_release.json `
  --build-name=$env:MTBBS_VERSION_NAME `
  --build-number=$env:MTBBS_VERSION_CODE

# 3. 生成安装包（版本号自动取环境变量）
iscc installer\setup.iss
```

**安装包路径**：`build\MTBBS_v{版本}_Setup.exe`

**注意**：编译前确保没有 mtbbs.exe 进程在运行，否则 MSBuild 因文件锁定会报错。

```powershell
# 如遇文件锁定，先结束进程
Get-Process mtbbs -ErrorAction SilentlyContinue | Stop-Process -Force
```

### Android（APK）

```powershell
powershell -ExecutionPolicy Bypass -File scripts\version.ps1 android
flutter build apk --release `
  --dart-define-from-file=mtbbs_release.json `
  --build-name=$env:MTBBS_VERSION_NAME `
  --build-number=$env:MTBBS_VERSION_CODE `
  --target-platform android-arm64
```

输出在 `build\app\outputs\flutter-apk\app-release.apk`。

> 因 App 未上架商店，APK 需手动安装。多 ABI 全量打包去掉 `--target-platform` 参数即可。本地无 `android/key.properties` 时用 debug 签名（自测用），正式分发请配置签名（见 `docs/15-版本发布.md`）。

---

## Fork 与自建教程

如果你想基于此项目适配**你自己的 Discuz 论坛**，Fork 后按以下注意事项配置。

### 1. Fork 仓库

在 GitHub 上点击右上角 **Fork**，将仓库克隆到你的账号下。

```bash
git clone https://github.com/你的用户名/mtbbs_app.git
cd mtbbs_app
```

### 2. 遵守许可证（必须）

本项目为 **GPLv3**，Fork/修改/分发必须：

- 保留代码顶部版权声明与 `LICENSE` 文件（GPLv3 全文）
- 修改后的版本同样以 GPLv3 发布，并提供源代码
- 在 README 或 About 中注明原作者及原始仓库

建议在 README 中添加：

```markdown
> 本分支源自 [qcxs/mtbbs_app](https://github.com/qcxs/mtbbs_app)，基于 GPLv3 许可。
```

### 3. 配置站点信息

修改 `lib/config/site_config.dart`，将预置站点替换为你的论坛地址：

```dart
// 将默认站点改为你的论坛
SiteConfig.sites[0] = SiteInfo(
  name: '我的论坛',
  host: 'your-forum.com',
  ...
);
```

> 本项目针对 MT 论坛的克米模板适配。不同 Discuz 模板/版本的页面结构可能有差异，若解析异常，参考 `docs/03-UA与解析策略.md` 调整。

### 4. 修改 Android 应用标识（推荐）

`android/app/build.gradle.kts` 中 `applicationId = "com.github.qcxs.discuz"` 是原作者的应用 ID——**Fork 后务必改成你自己的**（如 `com.yourname.discuz`），否则与原版应用包名冲突：同一设备无法同时安装，也无法覆盖升级。debug / beta 变体分别带 `.debug` / `.beta` 后缀，可与正式版共存。

### 5. 使用 GitHub Actions 发布

Fork 后 Actions 默认可用，`release.yml` 为**手动触发**（`workflow_dispatch`，不会自动跑）：

1. 进入仓库 **Actions** 页 → 左侧选 **Release** → **Run workflow**
2. 勾选平台（Android / Windows），填 `tag` 参数：
   - **留空**：只构建不发布，产物在运行页底部作为 artifact 下载（推荐用于测试流程）
   - **填 `v1.0.0`**：构建后自动创建/更新 GitHub Release 并上传产物；若 tag 不存在则由发布动作自动创建（指向当前迁出的提交）
3. 版本号规则与完整发布流程见 `docs/15-版本发布.md`

**Android 签名（可选但正式分发必配）**：CI 默认降级为 debug 签名（仅自测可装）。正式发布需在仓库 **Settings → Secrets and variables → Actions** 配置以下 4 个变量，`release.yml` 会自动检测并正式签名；缺任一变量会静默降级，**不会报错**：

| Secret 名 | 说明 |
|-----------|------|
| `SIGN_KEYSTORE_BASE64` | `keytool` 生成的 keystore 文件 base64 编码 |
| `SIGN_STORE_PASSWORD` | keystore 密码 |
| `SIGN_KEY_ALIAS` | 密钥别名 |
| `SIGN_KEY_PASSWORD` | 密钥密码 |

Windows 端无需额外配置：CI 使用 `windows-2022` 镜像（与本地 VS2022 工具链对齐），Inno Setup 中文语言文件已随仓库内置。

## 文档

> AI 改代码前必读：见仓库根目录 [AGENTS.md](AGENTS.md)（铁律 + 任务→文档路由表）。

```
docs/
├── 01-概述与架构.md        项目架构与分层设计
├── 02-开发规范.md          API 流程、文件规范、UI 约束
├── 03-UA与解析策略.md      UA 与 Discuz 解析策略
├── 04-状态管理.md          状态管理、站点切换、持久化策略
├── 05-快捷键与撤销.md      快捷键系统与编辑器撤销机制
├── 06-编辑器.md            编辑器模式、快照、图床、粘贴
├── 07-经验教训.md          踩坑记录与最佳实践（必读）
├── 08-主题与夜间模式.md    颜色规范与深色主题适配指南
├── 09-依赖清单.md          依赖速查、行为关键点与大忌
├── 10-API探针使用规范.md   探针命令/参数/踩坑
├── 11-新增功能开发流程.md  AI 冷启动手册（新增列表/详情类功能）
├── 12-写操作API文档.md     发帖/评论/回复/修改
├── 13-修改API文档.md       帖子/评论修改
├── 14-新增删除收藏功能文档.md  写功能实战参考
└── 15-版本发布.md          版本号规则 / 本地打包 / GitHub 自动发布
```

文档聚焦"为什么这样做"，代码细节让 AI 读源码。

## 技术栈

| 工具 | 用途 |
|------|------|
| Flutter + Dart | 跨平台 UI |
| Dio | HTTP 客户端 + Cookie 持久化 |
| Provider | 状态管理 |
| GoRouter | 路由 |
| cached_network_image | 图片缓存 |
| photo_view | 图片查看器 |
| flutter_inappwebview | WebView（登录 + 内置浏览器） |
| url_launcher | 外部浏览器打开链接 |
| html | HTML/XML DOM 解析 |

## 核心目录

```
lib/
├── api/            Discuz HTML/XML → JSON 适配器
├── auth/           登录认证与多账号管理
├── config/         站点/导航/工具栏配置
├── core/           BBCode 解析、日志、快捷键等工具
├── pages/          页面组件
│   ├── browser/    内置浏览器
│   ├── community/  社区
│   ├── editor/     编辑器（发帖/评论/回复）
│   ├── guide/      导读
│   ├── home/       首页
│   ├── settings/   设置页及子页面
│   ├── thread/     帖子详情
│   └── user/       用户主页
├── providers/      全局状态
├── services/       Dio、MT 图床、剪贴板粘贴等服务
└── widgets/        通用组件
```

## 致谢

- [**PiliPlus**](https://github.com/bggRGjQaUbCoE/PiliPlus)：开源的 B 站客户端标杆，本项目的版本管理、GitHub Actions 发布与打包流程参考了其成熟实践
- **DeepSeek API**：量大管饱的推理能力，支撑了本项目大量的开发、调试与文档工作
- **Trae**：可视化编辑器，降低了 Flutter 开发的上手门槛，适合小白快速构建应用

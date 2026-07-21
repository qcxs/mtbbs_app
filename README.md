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
| Android SDK | compileSdk 35+ |
| Windows | Windows 10+ (x64) |

```bash
# 检查代码
flutter analyze lib/

# 运行（Windows x64）
flutter run -d windows

# 运行（Android）
flutter run -d <device_id>

# 测试 API（CLI）
dart run lib/api/forum/guide/test.dart
```

## 本地打包

### Windows x64

```powershell
flutter build windows --release
```

输出在 `build\windows\x64\runner\Release\`。

### Android x64（仅 x86_64）

```powershell
flutter build apk --release --target-platform android-x64
```

输出在 `build\app\outputs\flutter-apk\app-release.apk`。

> 因 App 未上架商店，APK 需手动安装。arm64 设备需自行加 `--target-platform android-arm64` 参数打包。

---

## Fork & 自建教程

如果你想基于此项目适配**你自己的 Discuz 论坛**，可以 Fork 后自行配置。

### 1. Fork 仓库

在 GitHub 上点击右上角 **Fork**，将仓库克隆到你的账号下。

```bash
git clone https://github.com/你的用户名/mtbbs_app.git
cd mtbbs_app
```

### 2. 遵守许可证

**你必须保留以下内容不变：**

- 代码顶部的版权声明（Copyright notice）
- `LICENSE` 文件（GPLv3 全文）
- 在 README 或 About 页面中注明原作者及原始仓库链接

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

## 文档

```
docs/
├── 01-概述与架构.md        项目架构与分层设计
├── 02-开发规范.md          API 流程、文件规范、UI 约束
├── 03-状态管理.md          状态管理、站点切换、持久化策略
├── 04-快捷键与撤销.md      快捷键系统与编辑器撤销机制
├── 05-编辑器.md            编辑器模式、快照、图床、粘贴
├── 06-经验教训.md          踩坑记录与最佳实践
└── 07-主题与夜间模式.md    颜色规范与深色主题适配指南
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

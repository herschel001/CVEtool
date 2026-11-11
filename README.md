# 截图剪贴板

菜单栏里的 macOS 截图和剪贴板历史工具。平时不占屏幕，需要时再唤出来。截过的图和复制过的文字、图片、链接、颜色放在同一条历史里，可以搜索找回。

目前提供源码，尚未发布 Release 安装包。请在本机构建；仓库中的打包脚本只做本地临时签名，不包含 Developer ID 签名或 Apple 公证。

## 能做什么

- 只住在菜单栏，没有 Dock 图标
- 区域、窗口、全屏截图
- 标注：箭头、矩形、椭圆、文字、马赛克、高亮
- 颜色为红、蓝、黑、黄、白
- 马赛克画笔大小可调
- 截完后复制、保存、钉在屏幕上，或丢弃
- 截图完成后移动或缩放的是已截下的图像，不重新抓取桌面内容
- 剪贴板历史：文本、图片、链接、颜色、截图
- 搜索、按类型筛选、选中后粘贴回刚才的应用
- 容量档位为 50 / 100 / 200 / 500 MB / 1 GB，默认 200 MB；超限时删除最早的记录，单条超限则拒绝写入历史
- 快捷键可在设置里修改
- 开机启动可在设置里开关，默认开启

## 环境

- macOS 15.2 或更高
- Swift 6.0 或更高版本，以及包含 macOS 15.2 API 的 macOS SDK
- 本机需可用 `swift`、`swiftc`、`iconutil` 和 `codesign`；可通过 Xcode 或对应的命令行开发工具提供

没有第三方 Swift 包依赖。

## 构建和运行

```bash
git clone https://github.com/herschel001/CVEtool.git
cd CVEtool
swift test
bash scripts/package-app.sh
open build/CVEtool.app
```

打包脚本生成调试版 `build/CVEtool.app`，从 `AppIcon.swift` 绘制图标并生成 `.icns`，最后使用 ad-hoc 签名。`build/`、`.build/` 都是生成目录，不需要上传；图标生成脚本与测试参考图片已包含在仓库中。

`swift build` 只编译，`swift run CVEtool` 可以直接运行可执行文件；需要验证权限、应用图标和开机启动时，使用打包后的 `.app`。

打开后看屏幕右上角的回形夹图标。应用文件使用绿色底板、白色回形夹，菜单栏使用同一轮廓的黑白模板图标。点图标打开菜单，历史通过「打开历史」或快捷键唤出。

| 操作 | 默认快捷键 |
| --- | --- |
| 区域截图 | `⌘⇧1` |
| 窗口截图 | `⌘⇧2` |
| 全屏截图 | `⌘⇧3` |
| 打开 / 收起历史 | `⌘⇧V` |

截图工具栏为纯图标浮条，悬停可查看中文提示。标注工具选中后显示五色色板，马赛克工具选中后显示大小滑条；红叉取消，绿色对勾完成并复制。

## 权限

第一次截图需要屏幕录制。自动粘贴需要辅助功能。

到「系统设置 → 隐私与安全性」里打开对应开关。当前版本会提示屏幕录制授权后完全退出应用再重新打开；辅助功能授权后可先返回重试，仍不能自动粘贴时再重开。列表里的名字是「截图剪贴板」或 CVEtool。未授权辅助功能时，历史内容仍会写入剪贴板，可以手动粘贴。

本地构建使用临时签名。更换应用路径、签名或重新构建后，系统可能需要重新授权；如权限开关已打开但仍不能使用，请检查权限列表中的应用是否对应当前构建。打包脚本不会完成用于公开分发的签名、公证或发布流程。

## 数据

历史默认保存在 `~/Library/Application Support/CVEtool`：`history.json` 保存索引和文本，`images/` 保存 PNG 图片。设置保存在 UserDefaults。历史文件未做应用层加密；应用不上传、不同步，也不导入其他剪贴板工具的历史数据库。

开发时可以指定独立的历史目录：

```bash
CVETOOL_SUPPORT_DIR="$(mktemp -d /tmp/CVEtool-dev.XXXXXX)" build/CVEtool.app/Contents/MacOS/CVEtool
```

该变量只隔离历史目录，UserDefaults 设置和系统权限仍由当前应用身份共享。

## 目录

- `Sources/CVEtoolApp/`：菜单栏、截图、剪贴板、设置
- `Sources/CVEtoolCore/`：历史存储、容量、分类、标注绘制
- `Tests/CVEtoolCoreTests/`：核心逻辑测试
- `Tests/CVEtoolAppTests/`：截图拖动、缩放、工具栏和图标测试
- `scripts/`、`Support/`：图标生成、应用打包和 `Info.plist`
- [需求文档](docs/prd/PRD-001.md)、[任务与人工验收清单](docs/任务计划.md)
- [原始界面设计稿](docs/主界面-设计稿.html)、[图标选型存档（04 已采用）](docs/icon-concepts/index.html)

`swift test` 运行全部 XCTest 测试；例如 `swift test --filter AppIconTests` 只检查图标。App 图标测试使用 `docs/icon-concepts/04-paperclip-*.png` 作为参考，修改或精简文档资源时需保留这些图片。权限、真实多屏截图、自动粘贴和开机启动仍需按人工验收清单实机检查，自动化测试通过不代表这些场景全部验收通过。

## 许可

个人项目，源码公开。未另选开源许可证；在补充许可证之前，请不要把它当作可以任意再分发的授权。

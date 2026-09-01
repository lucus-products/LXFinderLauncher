# LXFinderLauncher

macOS 菜单栏工具：**在 Finder 当前窗口所在的目录，一键打开终端或编辑器**。灵感来自 [Go2Shell](https://itunes.apple.com/cn/app/go2shell/id445770608)，用 SwiftUI + AppKit 从零实现。

```
Finder 正在浏览 /Users/me/Projects/foo
        │  点菜单栏 terminal 图标 或 按 ⌘⇧T
        ▼
Terminal / iTerm2 / 自定义终端 在该目录打开（新窗口或新标签页）
Cursor / VSCode 一键打开该目录
```

与仓库里的 [Lucus-Finder](../Lucus-Finder/README.md) 互补：Lucus-Finder 走 Finder 右键「服务」菜单（需选中文件/文件夹）；本工具走**菜单栏 + 全局快捷键**（不选中任何东西，随时取当前窗口目录）。

---

## 功能特性

| 功能 | 说明 |
|---|---|
| 菜单栏 + 全局快捷键 | 点击菜单栏图标，或按全局快捷键（默认 ⌘⇧T，可在设置中录制自定义） |
| 多终端支持 | Terminal（系统）、iTerm2、自定义终端（任意 .app 路径） |
| 新窗口 / 新标签页 | 可选在已有终端窗口**新建标签页**（而非新窗口） |
| 用编辑器打开 | Cursor（默认）、VSCode、自定义编辑器一键打开当前目录 |
| 菜单显示当前路径 | 菜单顶部实时显示 Finder 当前目录 |
| 复制路径 | 把当前目录完整 POSIX 路径复制到剪贴板 |
| 打开 Finder 目录 | 在 Finder 新窗口定位当前目录 |
| 开机自启 | 登录时自动启动（SMAppService） |
| 首次启动引导 | 首次运行弹窗说明用法与授权 |
| 检查更新 | 启动/手动检查更新源 JSON，发现新版本提示下载（轻量版，无需签名） |

---

## 快速使用

1. 构建并安装：
   ```bash
   ./build.sh          # Debug 构建 → build/Build/Products/Debug/LXFinderLauncher.app
   ```
   复制到 `~/Applications` 或 `/Applications`，双击运行。
2. 首次运行：会弹出欢迎框 + 「控制 Finder」授权请求，**点允许**。
3. 在 Finder 打开任意目录，点菜单栏 **terminal 图标 →「在此处打开终端」**，或在任意 App 按 **⌘⇧T**。

### 授权说明（重要）

本工具通过 Apple Events 读取 Finder 当前目录，首次使用会在
**系统设置 → 隐私与安全性 → 自动化** 中登记授权。若误拒，重置命令：

```bash
tccutil reset AppleEvents com.linx.LXFinderLauncher
```

「新建标签页」功能会额外请求控制 Terminal / iTerm2 的授权。

---

## 工程结构

```
LXFinderLauncher/
├── build.sh                    # 构建脚本（含命令解释）
├── LXFinderLauncher.xcodeproj    # Xcode 工程（PBXFileSystemSynchronizedRootGroup 同步组结构）
└── LXFinderLauncher/             # 源码（文件放入即自动进 target）
    ├── LXFinderLauncherApp.swift   # @main：MenuBarExtra + Settings 场景
    ├── AppDelegate.swift         # 注册热键、启动授权预检、首次欢迎引导
    ├── AppCommands.swift         # 所有动作唯一入口（打开终端/编辑器/复制/定位）
    ├── FinderPathProvider.swift  # 读取 Finder 前窗目录（osascript 子进程）
    ├── OSAScriptRunner.swift     # 公共 AppleScript 执行器（osascript 子进程）
    ├── TerminalLauncher.swift    # 终端协议 + Terminal/iTerm2/自定义 实现 + 工厂
    ├── EditorOpener.swift        # 编辑器协议 + Cursor/VSCode/自定义 实现 + 工厂
    ├── HotkeyManager.swift       # Carbon RegisterEventHotKey 全局热键
    ├── HotkeyRecorder.swift      # 设置页录制组合键
    ├── KeycodeTable.swift        # 键码 → 显示名映射（纯函数，可单测）
    ├── MenuContentView.swift     # 菜单栏菜单内容
    ├── SettingsView.swift        # 设置窗口
    └── Info.plist                # LSUIElement + NSAppleEventsUsageDescription
```

---

## 技术要点

- **纯菜单栏 App**：`LSUIElement = YES`，无 Dock 图标；`MenuBarExtra` + `.menuBarExtraStyle(.menu)`。
- **全局热键**：Carbon `RegisterEventHotKey`，无需任何 TCC 授权、系统级独占；`EventHotKeyRef` 必须强持有。
- **读取 Finder 目录用 osascript 子进程而非 NSAppleScript**——这是本项目最重要的一个坑，见下方变更历史 V1.1。
- **打开终端/编辑器**：用 `NSWorkspace.open([dir], withApplicationAt:)`，不通过 Apple Events 控制目标应用，避免额外授权。
- **开机自启**：`SMAppService.mainApp.register()`，需 App 位于 `/Applications`。

---

## 发布更新（免费分发 · GitHub Releases + Gist）

更新机制：App 启动/手动「检查更新」时请求一个**固定的 JSON**（`UpdateChecker.feedURL`），
读到 `downloadURL` 后跳转下载。因此需要两个「永远不变的地址」：JSON 的 URL 和下载包的 URL。

### 首次配置（一次性）

1. **建 GitHub 仓库**（如 `LXFinderLauncher`）——放 Releases。
2. **建 Gist 放 update.json**：`github.com → Gist → New gist`，内容照抄 `docs/update.json.example`。
3. **改代码**：把 `UpdateChecker.swift` 的 `feedURL` 换成你 Gist 的 Raw 链接：
   ```
   https://gist.githubusercontent.com/<用户名>/<gist-id>/raw/update.json
   ```

### 每次发版流程

```bash
# 1. 生成新的更新包
./distribute-free.sh        # → dist/LXFinderLauncher.zip
```
2. **GitHub → 仓库 → Releases → Draft a new release**
   - tag 填版本号：`v1.1.0`
   - 附件上传 `dist/LXFinderLauncher.zip`（**文件名保持 LXFinderLauncher.zip 不变**）
3. **编辑 Gist 的 update.json**：`version` 改成 `1.1.0`，`notes` 写本次更新内容。
4. 完事。已装用户下次启动（或点「检查更新」）即提示新版本。

### 为什么 downloadURL 不用每次改

JSON 里的下载地址填的是 **固定「最新版」链接**：
```
https://github.com/<用户名>/LXFinderLauncher/releases/latest/download/LXFinderLauncher.zip
```
GitHub 保证它永远指向「最新 Release 里名为 `LXFinderLauncher.zip` 的文件」，
所以每次发版只需上传同名 zip，JSON 不用动。

### 国内访问慢怎么办

- 下载链接套代理：`https://ghproxy.com/https://github.com/...`
- 或改用国内对象存储（阿里云 OSS / 腾讯 COS），把 zip 和 update.json 放同一桶，两个 URL 依然固定。

---

## 变更历史

### V1.0 · 初始版本
- 菜单栏 App（`MenuBarExtra` + `LSUIElement` 纯菜单栏，无 Dock 图标）。
- 全局快捷键：Carbon `RegisterEventHotKey`，默认 ⌘⇧T，设置页可录制自定义组合键。
- 在 Finder 当前目录打开 **Terminal**（`NSWorkspace.open`，无需额外授权）。
- 复制当前目录路径 / 打开 Finder 目录。
- 设置窗口：快捷键开关与录制、终端选择。
- 独立工程：复制改造 Lucus-Finder 的 `project.pbxproj`（同步组结构 + `GENERATE_INFOPLIST_FILE` 合并自定义 `Info.plist`）。

### V1.1 · 修复「路径一直是 Desktop」⭐⭐
**现象**：打开的终端始终落在桌面，而非 Finder 当前目录。

**根因**（两个问题叠加）：
1. **LSUIElement 菜单栏 App 直接发 Apple Events 时，系统不弹 TCC 授权框、静默拒绝**，返回 `-1743`；
2. AppleScript 脚本里 `on error` 把 `-1743` 吞掉，静默 fallback 桌面——既不报错也不 throw。

**修复**：
- 改用 **osascript 子进程**（`Process` 调 `/usr/bin/osascript`）发送 Apple Events，TCC 授权弹窗可正常显示，授权归因到本 App。
- `-1743` 错误向上冒泡，弹窗引导用户去「自动化」授权。
- 前窗获取失败时**枚举所有窗口**兜底。
- 启动时**预检一次授权**，主动弹窗。
- 接入 `os_log` 系统日志，便于 `log stream` 排查。

### V2.0 · 扩展：iTerm2 + 开机自启
- **iTerm2 支持**：设置中切换 Terminal / iTerm2（自动检测安装，未装则不显示）。
- **开机自启**：`SMAppService.mainApp` 注册登录项，设置中开关。

### V3.0 · 扩展：编辑器 / 新标签页 / 自定义终端 / 菜单路径 / 首次引导
- **用 Cursor 打开**：菜单新增「用 Cursor 打开」，在 Finder 目录用 Cursor 打开；设置可配置 VSCode 或自定义编辑器。
- **菜单显示当前路径**：菜单顶部实时显示 Finder 当前目录，每次展开刷新。
- **新标签页打开**：设置中可选「当前窗口新建标签页」，用 osascript 控制 Terminal / iTerm2 在现有窗口加标签页。
- **自定义终端**：支持 Warp / kitty 等任意 `.app` 路径（用通用 NSWorkspace 打开，不支持标签页）。
- **首次启动引导**：弹窗说明用法与授权。
- 抽象出 `OSAScriptRunner` 公共执行器（支持 argv 参数注入，避免路径拼接转义问题）。

### V3.1 · 轻量更新检查
- **检查更新**：菜单「检查更新…」+ 启动自动检查（设置中可关闭）。
- 免费分发无法用 Sparkle（其强制要求签名 + 公证），改用 `URLSession` 请求一个**静态 JSON**（版本号 + 下载地址），无需服务器、无需签名。
- 更新源：`UpdateChecker.feedURL`，发布前替换为自己托管的 JSON（GitHub Pages / Gist raw / 对象存储均可）。
- 版本比较 `UpdateChecker.isNewer` 为纯函数，附带单元测试（含多段数字、`v` 前缀等边界）。

---

*构建：`./build.sh [Debug|Release]`。技术栈：Swift 6 / SwiftUI / AppKit / Carbon / osascript。*

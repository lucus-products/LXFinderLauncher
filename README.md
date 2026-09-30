<div align="center">
  <img src="docs/logo.png" width="128" alt="LXFinderLauncher 图标">
  <h1>LXFinderLauncher</h1>
</div>

macOS 菜单栏工具：**在 Finder 当前窗口所在的目录，一键打开终端、编辑器，或执行你预设的命令**。灵感来自 [Go2Shell](https://itunes.apple.com/cn/app/go2shell/id445770608)，用 SwiftUI + AppKit 从零实现——不需要在 Finder 里选中任何文件，点菜单栏图标或按全局快捷键就行。

```
Finder 正在浏览 /Users/me/Projects/foo
        │  点菜单栏图标，或按全局快捷键 ⌘⇧T
        ▼
Terminal / iTerm2 / 自定义终端 在该目录打开（新窗口或新标签页）
Cursor / VSCode / 自定义编辑器 一键打开该目录
自定义动作（npm run dev、git pull…）在该目录的终端里执行
```

## 下载

[⬇️ 下载最新版（v1.2.0）](https://github.com/lucus-products/LXFinderLauncher/releases/latest/download/LXFinderLauncher.zip)

> 免费分发版未签名 Developer ID，首次运行请右键 App → **打开**（多一次确认），或用 `xattr -dr com.apple.quarantine` 解除隔离。

---

## 功能特性

| 功能 | 说明 |
|---|---|
| 菜单栏 + 全局快捷键 | 点击菜单栏图标，或按全局快捷键（打开终端 ⌘⇧T、创建文件 ⌃⌥⌘N、编辑器 ⌃⌥⌘E、复制路径 ⌃⌥⌘C，均可在设置中录制自定义） |
| 多终端支持 | Terminal（系统）、iTerm2、自定义终端（任意 .app 路径） |
| 新窗口 / 新标签页 | 可选在已有终端窗口**新建标签页**（而非新窗口） |
| 用编辑器打开 | Cursor / VSCode / 自定义编辑器，**可同时启用多个**并排序；启用多个时菜单收成一个子菜单，全局热键打开列表里第一个 |
| 自定义动作 | 配置 `{名字, 命令}`，菜单栏一键在 Finder 当前目录的终端里执行（如 `npm run dev` / `git pull` / `code .`）。命令由你自己的终端执行，本 App 不代跑，因此不需要额外授权 |
| 创建文件 | 菜单栏「创建文件」二级菜单就地新建文件（md / txt / docx / xlsx / pptx / json / yml / html），类型、顺序可在设置中配置，也能新增自定义格式 |
| 一键建文件 | 全局热键 **⌃⌥⌘N** 不弹窗直接建一个「未命名.<上次用的类型>」并在 Finder 中选中，可就地改名（同 Finder 的 ⌘⇧N 新建文件夹）；重名自动加序号，绝不覆盖 |
| 复制路径 | 把当前目录完整 POSIX 路径复制到剪贴板（有全局热键；复制成功无提示，粘贴即可确认） |
| 打开 Finder 目录 | 在 Finder 新窗口定位当前目录 |
| 开机自启 | 登录时自动启动（SMAppService） |
| 首次启动引导 | 首次运行弹窗说明用法与授权 |
| 检查更新 | 启动/手动检查更新源 JSON，发现新版本提示下载（轻量版，无需签名） |

---

## 快速使用

1. 构建并安装：
   ```bash
   ./scripts/build.sh          # Debug 构建 → dist-build/Build/Products/Debug/LXFinderLauncher.app
   ```
   复制到 `~/Applications` 或 `/Applications`，双击运行。
2. 首次运行：会弹出欢迎框 + 「控制 Finder」授权请求，**点允许**。
3. 在 Finder 打开任意目录，点菜单栏 **terminal 图标 →「在此处打开终端」**，或在任意 App 按 **⌘⇧T**。
4. 想就地建文件：按 **⌃⌥⌘N** 直接生成「未命名.<上次用的类型>」并在 Finder 中选中，敲名字回车即改名；想一上来就指定名字和类型，走菜单栏 **「创建文件 → 某个类型」**。

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
├── scripts/                     # 构建 / 分发 / 发布脚本
│   ├── README.md                # 四个脚本各自的用法与「发版前必看」
│   ├── build.sh                 # 构建脚本（含命令解释）
│   ├── make-blank-templates.sh  # 生成 Templates/ 下的空白 Office 模板
│   ├── distribute-free.sh       # 免费分发打包（路径 A，$0）
│   └── release.sh               # 签名 + 公证 + 打 DMG（路径 B，$99/年）
├── LXFinderLauncher.xcodeproj    # Xcode 工程（PBXFileSystemSynchronizedRootGroup 同步组结构）
└── LXFinderLauncher/             # 源码（文件放入即自动进 target，子目录自动成为分组）
    ├── App/                      # 入口与生命周期
    │   ├── LXFinderLauncherApp.swift   # @main：MenuBarExtra + Settings 场景
    │   ├── AppDelegate.swift           # 注册热键、启动授权预检、首次欢迎引导
    │   ├── AppCommands.swift           # 所有动作唯一入口（终端/编辑器/自制动作/复制/建文件/定位）
    │   └── SettingsOpener.swift        # 打开设置窗口并保证置前（LSUIElement 的坑）
    ├── Views/                    # 界面
    │   ├── MenuContentView.swift       # 菜单栏菜单内容
    │   └── SettingsView.swift          # 设置窗口（侧边栏 + 七个面板）
    ├── Services/                 # 与外部系统打交道
    │   ├── FinderPathProvider.swift    # 读取 Finder 前窗目录（osascript 子进程）
    │   ├── OSAScriptRunner.swift       # 公共 AppleScript 执行器（osascript 子进程）
    │   ├── TerminalLauncher.swift      # 终端协议 + Terminal/iTerm2/自定义 实现 + 工厂 + 执行命令的脚本
    │   ├── EditorOpener.swift          # 编辑器协议 + 按 App 打开 + 解析工厂
    │   ├── EditorEntry.swift           # 编辑器列表模型与 UserDefaults 读写（含旧单选配置派生）
    │   └── UpdateChecker.swift         # 检查更新（读取更新源 JSON）
    ├── FileCreation/             # 创建文件
    │   ├── FileTemplate.swift          # 类型列表模型与 UserDefaults 读写
    │   └── FileCreator.swift           # 文件名归一化、写盘、输入弹窗
    ├── CustomActions/            # 自定义动作
    │   └── CustomAction.swift          # 动作列表模型与 UserDefaults 读写
    ├── Hotkey/                   # 全局热键
    │   ├── HotkeyManager.swift         # Carbon RegisterEventHotKey 多热键管理
    │   ├── HotkeyRecorder.swift        # 设置页录制组合键
    │   └── KeycodeTable.swift          # 键码 → 显示名映射（纯函数，可单测）
    ├── Templates/                # 空白 Office 模板（由 scripts/make-blank-templates.sh 生成）
    ├── Assets.xcassets           # 应用图标与强调色
    └── Info.plist                # LSUIElement + 各项 TCC 用途说明
```

---

## 技术要点

- **纯菜单栏 App**：`LSUIElement = YES`，无 Dock 图标；`MenuBarExtra` + `.menuBarExtraStyle(.menu)`。
- **全局热键**：Carbon `RegisterEventHotKey`，无需任何 TCC 授权，也是免授权方案里唯一能「吞掉」按键的（`NSEvent` 全局监听只能旁观会双触发、`CGEventTap` 要辅助功能权限）。支持多个热键，靠 `EventHotKeyID.id` 分发。
  - **它不是系统级独占**：跨进程重复注册不会失败、两边都收到通知，「注册成功」≠「别的 App 收不到」。真正会失败的是同进程内两个热键撞同一组合（`eventHotKeyExistsErr`）与系统保留组合键，所以设置页把「与另一个热键重复」和「注册失败」分开提示。
  - Carbon 回调返回 `eventNotHandledErr` 才是「放行」——返回任何其它值都会终止事件传递。所以处理器必须校验 `EventHotKeyID.signature`，不是自己的一律放行，否则会吞掉同一 target 上 AppKit/SwiftUI 内部注册的热键事件。
  - 创建文件用 ⌃⌥⌘N 而**不是** ⌥⌘N：后者是 Finder 的「新建智能文件夹」，而 Finder 恰好是这个功能唯一的使用场景。
  - `@AppStorage` 只把默认值放在自己的属性包装器里、**不写进 UserDefaults**，而 `HotkeyManager` 直接读 UserDefaults——所以启动时必须先 `GlobalHotkey.registerDefaults()`，否则默认热键注册不上（`bool` 读到 false），且 `integer` 读到 `0` 会去劫持字母 A。
- **读取 Finder 目录用 osascript 子进程而非 NSAppleScript**——这是本项目最重要的一个坑，见下方变更历史 V1.0.0。
- **打开终端/编辑器**：用 `NSWorkspace.open([dir], withApplicationAt:)`，不通过 Apple Events 控制目标应用，避免额外授权。
- **创建文件的空白 Office 模板**：docx/xlsx/pptx 是 OOXML（zip 包），0 字节的空文件会被 Word/Excel/PowerPoint 判为「文件已损坏」。所以随包带三个最小可用的空白文档（`Templates/`），创建时直接拷贝；纯文本类格式空文件即合法，走 0 字节分支。模板由 `scripts/make-blank-templates.sh` 生成，不要手工改 `Templates/` 里的文件。
- **菜单项的即时性**：`.menuBarExtraStyle(.menu)` 下**打开菜单不会触发视图重算**（[FB13683957](https://github.com/feedback-assistant/reports/issues/477)）。所以菜单里依赖设置的项必须用 `@AppStorage` 读，用 `UserDefaults.standard` 静态读要重启 App 才生效。
- **设置窗口的侧边栏**：`HStack { List(.listStyle(.sidebar)) ; 详情 }` 手写，**不用 `NavigationSplitView`**。后者会无条件往窗口注入工具栏上的 sidebar toggle（`Settings` 场景本来没有工具栏），且 Apple 已确认的 rdar://122947424 会让 detail 列多出工具栏高度的空白——而 `Settings` 场景按根视图 ideal size 决定窗口尺寸，那层高度会让窗口尺寸失控。侧边栏材质与圆角选中高亮本来就来自 `.listStyle(.sidebar)`。新增一个面板只需往 `SettingsPane` 加一个 case + 一个 `xxxPane` 计算属性。
- **自定义动作不自己执行命令**：命令是**通过 argv 注入**（脚本里只出现 `item 2 of argv`）送进终端的，绝不拼进 AppleScript 源码——命令里可能有引号、`$`、反斜杠，拼进字符串字面量会被 AppleScript 的转义规则改写，轻则语法错、重则执行了另一条命令。`TerminalCommandScript` 的签名干脆不接收命令参数，从类型上杜绝这种拼法；`OSAScriptRunner` 侧则必须在参数前加 `--` 终止符，否则 `--help` 这种以 `-` 开头的命令会被 osascript 自己的 getopt 当成选项吃掉。
- **可配置列表共用一套写回管线**：「创建文件 / 编辑器 / 自定义动作」三份列表都是「本地 `@State` 草稿 → 400ms 防抖 → 与 `lastSyncedXxxJSON` 比对 → 写 `@AppStorage`」。那个比对是**必需而非优化**（`onAppear` 装载也会触发 `onChange`，不拦住就会把当前值固化进 UserDefaults），所以三者共用 `encodedList` / `debouncedWrite` 两个 helper；但**各持有自己的 `Task` 句柄**——共用会让编辑一份取消掉另一份还没落盘的改动。
- **编辑器列表从旧的单选配置派生**：老版本存 `editorKind`（0=关闭 1=Cursor 2=VSCode 3=自定义）+ `customEditorPath`，新版本存 `editors`（JSON 列表）。只有 `editors` 键为空时才派生，写过就以列表为准。用「读时派生」而不是「启动时写一次迁移」，是为了让「升级 → 降级改 editorKind → 再升级」这条序列也正确（写一次的话旧值会被永久回滚成迁移当时的快照），也避免给从没碰过编辑器的用户写进一个 `"[]"`。
- **开机自启**：`SMAppService.mainApp.register()`，需 App 位于 `/Applications`。

---

## 变更历史

### V1.2.0 · 多编辑器与自定义动作
- **多编辑器并存**：编辑器从单选改为列表，可以同时启用 Cursor / VSCode / 自定义编辑器并调整顺序。启用多个时菜单收成一个「用编辑器打开」子菜单；全局热键打开列表里的第一个。**老的单选配置会自动派生**成新列表，不需要重新设置。
- **自定义动作**：设置里配置 `{名字, 命令}`，菜单栏「自定义动作」子菜单一键在 Finder 当前目录的终端里执行（如 `npm run dev`、`git pull`、`code .`）。命令由你自己的终端执行，**本 App 不代跑任何东西**，所以不新增任何授权。自定义终端注入不了命令，菜单里会整段置灰并说明原因。
- 新增两个全局热键：**⌃⌥⌘E**（用编辑器打开）、**⌃⌥⌘C**（复制当前目录路径），可在设置里改或关掉。
- 修复：**自动化授权被拒时「点了没反应、也没有提示」**。「打开终端」的 AppleScript 错误被就地 `print` 吞掉，而 `print` 在 Release 构建里根本无处可见；现在错误一路上抛到弹窗，并且「打开授权设置」按钮能直达对应的系统设置面板（此前 `OSAScriptError` 没有映射到面板）。同类问题一并修掉：配了 iTerm2 / 自定义终端但它不在原位时同样是静默失败。
- 修复：`osascript` 的参数没有加 `--` 终止符，以 `-` 开头的参数（如 `--help`）会被 osascript 自己的 getopt 当成选项而直接失败。

### V1.1.8 · 修复权限反复弹窗
- **重要修复**：v1.1.7 的签名证书被吊销，导致「打开终端 / 用编辑器打开 / 创建文件」每次都重新弹授权框，系统设置里的「自动化」开关也永远不生效。原因是 TCC 授权按代码签名匹配，签名校验不过就匹配不上任何记录。本版用有效证书重新签名。
- `scripts/distribute-free.sh` 新增**签名校验闸门**：打包后强制校验签名，被吊销/失效的证书签名会直接中止发布，杜绝同类问题再次流出。

### V1.1.7 · 创建文件
- 新增「创建文件」功能：菜单栏二级菜单就地新建文件（md / txt / docx / xlsx / pptx / json / yml / html），类型与顺序可在设置中配置，也能新增自定义格式。docx / xlsx / pptx 内置最小可用的空白模板，创建出来可直接双击打开。
- 新增全局热键 **⌃⌥⌘N**：不弹窗直接建一个「未命名.<上次用的类型>」并在 Finder 中选中，可就地改名；重名自动加序号，绝不覆盖。
- 设置页改为**侧边栏 + 详情面板**布局，分「通用 / 快捷键 / 终端 / 编辑器 / 创建文件 / 权限」六个面板。
- 修复：录制快捷键时中途关闭设置窗口，会导致全局热键永久失效（热键被临时注销后不再注册回来）。
- 修复：全新安装时默认热键不生效——设置页开关显示「已启用」但实际从未注册。

### V1.1.6 · 终端打开方式优化与快捷键体验
- 终端「打开位置」：选择「新窗口」时**总是新建独立窗口**（不再并入已有窗口成为标签页）。
- 「新建标签页」改为智能行为：当前没有已打开的终端时新建窗口，已有窗口时在其新建标签页；选项文案与语义说明同步更新。
- 修复 iTerm2 选择「新窗口」时窗口一闪即退的问题。
- 快捷键：失败/错误弹窗不再被遮挡；设置页补充快捷键用途说明；组合键被占用（注册失败）时红字提示。

### V1.1.5 · 解决设置页面遮挡问题
- 修复菜单栏点击「设置…」时，设置窗口落在其它窗口后面、被遮挡的问题（现在打开前会自动激活 App 并置顶窗口）。

### V1.1.4 · 更换应用图标
- 应用图标替换为新图（1024×1024 透明背景源图，生成全尺寸）。
- 菜单栏图标默认显示 App 图标，设置中可切换回终端图标。

### V1.1.3 · 更换应用图标
- 应用图标替换为新设计（1024×1024 源图生成全尺寸，含透明背景）。

### V1.1.1 · 移除路径显示
- 移除菜单顶部「当前路径」显示（路径获取异常、长路径拉伸菜单）。

### V1.1.0 · 更新机制验证版
- 版本号升级，用于验证「检查更新 → 提示新版 → 下载安装」的完整升级链路。

### V1.0.0 · 首个正式版
- 纯菜单栏 App（`MenuBarExtra` + `LSUIElement`，无 Dock 图标）。
- 全局快捷键：Carbon `RegisterEventHotKey`，默认 ⌘⇧T，设置页可录制自定义组合键。
- 在 Finder 当前目录打开 **Terminal / iTerm2 / 自定义终端**（`NSWorkspace.open`，无需额外授权），支持新窗口 / 新标签页。
- **用 Cursor / VSCode / 自定义编辑器** 一键打开当前目录。
- 菜单顶部实时显示 Finder 当前目录，一键复制路径 / 在 Finder 定位。
- **开机自启**：`SMAppService.mainApp` 注册登录项，设置中开关。
- **首次启动引导**：弹窗说明用法与授权。
- **检查更新**：`URLSession` 请求静态 JSON（版本号 + 下载地址），免费分发无需签名即可自更新。
- 独立工程：复制改造 Lucus-Finder 的 `project.pbxproj`（同步组结构 + `GENERATE_INFOPLIST_FILE` 合并自定义 `Info.plist`）。

> 关键技术：读取 Finder 当前目录用 **osascript 子进程**（`/usr/bin/osascript`）而非 `NSAppleScript`——
> 菜单栏 App 直接发 Apple Events 会被 TCC 静默拒绝（返回 `-1743`），子进程方式才能正常弹出授权框并拿到目录。
> 详见上文「技术要点」。

## 相关

姊妹工具 **Lucus-Finder** 走 Finder 右键「服务」菜单，需要先在 Finder 里选中文件或文件夹；本工具走**菜单栏 + 全局快捷键**，不选中任何东西也能随时取当前窗口目录。

---

*构建：`./scripts/build.sh [Debug|Release]`。技术栈：Swift 6 / SwiftUI / AppKit / Carbon / osascript。*

# LXFinderLauncher 开发说明

面向要改这个项目的人。功能与使用说明见 [README](README.md)。

## 构建与运行

* 用 Xcode 打开 `LXFinderLauncher.xcodeproj` 直接 `⌘R` 最省事——纯菜单栏 App，跑起来**没有窗口也没有 Dock 图标**，去菜单栏找。

* 命令行构建：

```bash
./scripts/build.sh            # Debug → dist-build/Build/Products/Debug/
./scripts/build.sh Release    # Release（合并成单一二进制，才可分发）
```

要试**开机自启**得把产物复制到 `/Applications`——⌘R 跑的是 DerivedData 里的副本，那个功能不生效（开关会自动弹回来）。首次运行会请求「控制 Finder」授权，见 [README](README.md) 的「授权说明」。

> Debug 产物含 `debug.dylib` 薄壳，只适合本机调试；对外分发用 Release。

## 工程结构

```
LXFinderLauncher/
├── scripts/                    # 构建 / 打包 / 发布（四个脚本的用法见 scripts/README.md）
├── LXFinderLauncher.xcodeproj  # 同步组结构（PBXFileSystemSynchronizedRootGroup）
└── LXFinderLauncher/           # 源码：文件丢进目录即自动进 target，子目录自动成为分组
    ├── App/                    # 入口与生命周期；AppCommands 是所有动作的唯一入口
    ├── Views/                  # 菜单栏菜单、设置窗口（侧边栏 + 七个面板）
    ├── Services/               # Finder 目录、osascript、终端/编辑器启动、复制格式、更新检查
    ├── FileCreation/           # 创建文件：类型模型 + 写盘
    ├── CustomActions/          # 自定义动作：模型与读写
    ├── Hotkey/                 # Carbon 全局热键：管理、录制、键码映射
    ├── Templates/              # 空白 Office 模板（make-blank-templates.sh 生成，勿手改）
    ├── Assets.xcassets         # 应用图标与强调色
    └── Info.plist              # LSUIElement + 各项 TCC 用途说明
```

## 技术要点

改代码前值得先看的几件事，大多是踩过坑才定下来的。

### 应用形态与窗口

- **纯菜单栏 App**：`LSUIElement = YES`，无 Dock 图标；`MenuBarExtra` + `.menuBarExtraStyle(.menu)`。
- **菜单项的即时性**：`.menuBarExtraStyle(.menu)` 下**打开菜单不会触发视图重算**（[FB13683957](https://github.com/feedback-assistant/reports/issues/477)）。所以菜单里依赖设置的项必须用 `@AppStorage` 读，用 `UserDefaults.standard` 静态读要重启 App 才生效。
- **设置窗口的侧边栏**：`HStack { List(.listStyle(.sidebar)) ; 详情 }` 手写，**不用 `NavigationSplitView`**。
  - 它会无条件注入工具栏上的 sidebar toggle，且 rdar://122947424 让 detail 列多出工具栏高度的空白——`Settings` 场景按根视图 ideal size 定窗口尺寸，那层高度会让尺寸失控。
  - 侧边栏材质与圆角选中高亮本来就来自 `.listStyle(.sidebar)`。新增面板只需往 `SettingsPane` 加一个 case + 一个 `xxxPane` 计算属性。
- **开机自启**：`SMAppService.mainApp.register()`，需 App 位于 `/Applications`。

### 全局热键

- Carbon `RegisterEventHotKey`：无需任何 TCC 授权，也是免授权方案里唯一能「吞掉」按键的（`NSEvent` 全局监听只能旁观、`CGEventTap` 要辅助功能权限）。多个热键靠 `EventHotKeyID.id` 分发。
  - **它不是系统级独占**：跨进程重复注册不会失败、两边都收到通知，「注册成功」≠「别的 App 收不到」。真正会失败的是同进程内两个热键撞同一组合（`eventHotKeyExistsErr`）与系统保留组合键，所以设置页把「与另一个热键重复」和「注册失败」分开提示。
  - Carbon 回调返回 `eventNotHandledErr` 才是「放行」——返回任何其它值都会终止事件传递。所以处理器必须校验 `EventHotKeyID.signature`，不是自己的一律放行，否则会吞掉同一 target 上 AppKit/SwiftUI 内部注册的热键事件。
  - 创建文件用 ⌃⌥⌘N 而**不是** ⌥⌘N：后者是 Finder 的「新建智能文件夹」，而 Finder 恰好是这个功能唯一的使用场景。
  - `@AppStorage` 只把默认值放在自己的属性包装器里、**不写进 UserDefaults**，而 `HotkeyManager` 直接读 UserDefaults——所以启动时必须先 `GlobalHotkey.registerDefaults()`，否则默认热键注册不上（`bool` 读到 false），且 `integer` 读到 `0` 会去劫持字母 A。

### 与 Finder / 终端的交互

- **读取 Finder 目录用 osascript 子进程而非 NSAppleScript**——这是本项目最重要的一个坑，见 [README 的变更历史 V1.0.0](README.md)。
- **打开终端/编辑器**：用 `NSWorkspace.open([dir], withApplicationAt:)`，不通过 Apple Events 控制目标应用，避免额外授权。
- **自定义动作不自己执行命令**：命令是**通过 argv 注入**（脚本里只出现 `item 2 of argv`）送进终端的，绝不拼进 AppleScript 源码。
  - 命令里可能有引号、`$`、反斜杠，拼进字符串字面量会被 AppleScript 的转义规则改写，轻则语法错、重则执行了另一条命令。`TerminalCommandScript` 的签名干脆不接收命令参数，从类型上杜绝这种拼法。
  - `OSAScriptRunner` 侧则必须在参数前加 `--` 终止符，否则 `--help` 这种以 `-` 开头的命令会被 osascript 自己的 getopt 当成选项吃掉。

### 配置与资源

- **可配置列表共用一套写回管线**：「创建文件 / 编辑器 / 自定义动作」三份都是「本地草稿 → 400ms 防抖 → 与 `lastSyncedXxxJSON` 比对 → 写 `@AppStorage`」，共用 `encodedList` / `debouncedWrite`，但**各持自己的 `Task` 句柄**——共用会让编辑一份取消掉另一份还没落盘的改动。
  - 那个比对是**必需而非优化**：`onAppear` 装载也会触发 `onChange`，不拦住就会把当前值固化进 UserDefaults。
- **编辑器列表从旧的单选配置派生**：老版本存 `editorKind`（0=关闭 1=Cursor 2=VSCode 3=自定义）+ `customEditorPath`，新版本存 `editors`（JSON 列表）；`editors` 键为空时才派生，写过就以列表为准。
  - 用「读时派生」而非「启动时写一次迁移」：后者会让「升级 → 降级改 `editorKind` → 再升级」的旧值被永久回滚成迁移当时的快照。
- **创建文件的空白 Office 模板**：docx/xlsx/pptx 是 OOXML（zip 包），0 字节空文件会被 Word/Excel/PowerPoint 判为损坏，所以随包带三个最小可用的空白文档（`Templates/`）直接拷贝；纯文本类空文件即合法。模板由脚本生成，**不要手工改** `Templates/` 里的文件。

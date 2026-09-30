# LXFinderLauncher 源码解析

写给**没怎么读过 macOS 项目源码**的人。目标不是「介绍每个 API」，而是让你读完能回答三个问题：

1. 这个 App 到底是怎么运转的？
2. 我想改某个东西，该动哪个文件？
3. 这些写法为什么是这样，换个写法行不行？

配套文档：
- [README.md](README.md) —— 功能与使用说明
- [README_dev.md](README_dev.md) —— 构建、工程结构、技术要点（踩坑记录）

---

## 目录

1. [先搞懂这个 App 在干什么](#1-先搞懂这个-app-在干什么)
2. [整体架构](#2-整体架构)
3. [文件地图](#3-文件地图)
4. [逐文件详解](#4-逐文件详解)
5. [三条完整的调用链](#5-三条完整的调用链)
6. [数据存在哪：UserDefaults 键全表](#6-数据存在哪userdefaults-键全表)
7. [术语表](#7-术语表)
8. [想改代码，从哪下手](#8-想改代码从哪下手)

---

## 1. 先搞懂这个 App 在干什么

### 一句话

**它在 Finder 里，一键打开终端 / 编辑器 / 执行命令。**

### 用户视角的完整流程

```
你在 Finder 里浏览 /Users/me/Projects/foo
        │
        │  按下全局热键 ⇧⌘T（或点菜单栏图标）
        ▼
App 问 Finder：「你当前窗口在看哪个目录？」
        │
        ▼
Finder 回答：/Users/me/Projects/foo
        │
        ▼
App 让 Terminal 在这个目录开一个窗口
```

听起来简单，但中间有三处是 macOS 特有的麻烦，整个项目的复杂度几乎都来自它们：

| 麻烦 | 说明 |
|---|---|
| **怎么问 Finder？** | macOS 只允许通过 **Apple Events**（AppleScript 那套）问。App 自己要发 Apple Event 又需要用户授权（**TCC**），而菜单栏 App 发出去还会被静默拒绝——所以只能**开一个子进程** `osascript` 去问 |
| **怎么开终端？** | Terminal / iTerm2 要精确控制「新窗口还是新标签页」也得发 Apple Events，又要一遍授权；能不用就尽量不用（`NSWorkspace` 走 Launch Services，不要授权） |
| **热键怎么按？** | 全局热键（App 不在前台也能响应）在 macOS 上有三种做法，前两种要么会双触发、要么要辅助功能权限，只有 **Carbon** 那套免授权 |

这三件事的答案决定了整个项目的骨架。

---

## 2. 整体架构

### 分层图

```
┌─────────────────────────────────────────────────────────────┐
│  入口层  App/                                                │
│    LXFinderLauncherApp  ← @main，程序从这里开始              │
│    AppDelegate          ← 启动时要做的事（注册热键、预检授权）│
└───────────────────────────┬─────────────────────────────────┘
                            │
┌───────────────────────────▼─────────────────────────────────┐
│  界面层  Views/                                              │
│    MenuContentView  ← 菜单栏点开的那个菜单                    │
│    SettingsView     ← 设置窗口（854 行，最大的文件）          │
└───────────────────────────┬─────────────────────────────────┘
                            │  所有按钮都只调 AppCommands
┌───────────────────────────▼─────────────────────────────────┐
│  动作层  App/AppCommands.swift                               │
│    ★ 所有用户动作的唯一入口，菜单和热键都走这里               │
└───────────────────────────┬─────────────────────────────────┘
                            │
┌───────────────────────────▼─────────────────────────────────┐
│  服务层  Services/ + FileCreation/ + CustomActions/          │
│    FinderPathProvider  ← 问 Finder 当前目录                  │
│    OSAScriptRunner     ← 执行 AppleScript 的通用工具         │
│    TerminalLauncher    ← 打开终端 / 在终端里跑命令           │
│    EditorOpener        ← 打开编辑器                          │
│    PathCopier          ← 把路径格式化成五种文本              │
│    FileCreator         ← 创建文件                            │
│    UpdateChecker       ← 检查更新                            │
└───────────────────────────┬─────────────────────────────────┘
                            │
┌───────────────────────────▼─────────────────────────────────┐
│  系统层（macOS 提供的能力）                                   │
│    AppleScript / osascript 子进程   ← 问 Finder、控制终端    │
│    NSWorkspace                      ← 用 App 打开目录        │
│    Carbon RegisterEventHotKey       ← 全局热键               │
│    UserDefaults                     ← 存配置（没有数据库）    │
└─────────────────────────────────────────────────────────────┘
```

### 三条主线

读这个项目，只要抓住三条线就不会迷路：

**主线一：启动时发生了什么**

```
main() → LXFinderLauncherApp → AppDelegate.applicationDidFinishLaunching
          ① 注册热键默认值
          ② 把「热键触发 → 哪个动作」连起来
          ③ 注册全部热键
          ④ 预检一次 Finder 授权（主动弹授权框）
          ⑤ 首次运行弹欢迎框
          ⑥ 后台检查更新
```

**主线二：一个动作怎么从用户手上走到系统**

```
用户按热键 / 点菜单
   → HotkeyManager 或 MenuContentView
   → AppCommands 的某个方法        ← 唯一的岔路口，所有动作都汇到这里
   → Services 里的某个工具
   → osascript 子进程 / NSWorkspace / 文件系统
```

**主线三：配置怎么存、怎么同步到界面**

```
UserDefaults（系统的键值存储，就是一个 plist 文件）
   ↕ @AppStorage（SwiftUI 的「会自动刷新界面」的读写包装）
Views（设置页负责改，菜单负责读）
```

### 五条贯穿全局的设计原则

这五条是理解代码为什么长这样的钥匙：

**① App 自己不执行任何东西**

「自定义动作」要跑 `npm run dev`——App **不是**自己去 `Process()` 起个 shell，而是打开终端、把命令「敲」进去，由**用户自己的终端**执行。

好处是双重的：不新增任何系统授权；「跑什么」的责任留在用户和终端那边。

**② 所有动作收敛到一个入口**

菜单点击、全局热键——两条完全不同的触发路径，最后都调 `AppCommands.shared.xxx()`。加一个新功能只需要在 `AppCommands` 加一个方法，然后从两个地方调用。这避免了「菜单里能用、热键不能用」这类不一致。

**③ 配置 = 一个 JSON 字符串存在 UserDefaults 里**

没有数据库、没有配置文件。三份可编辑列表（文件类型、编辑器、自定义动作）都是：

```
[结构体] --JSONEncoder--> JSON 字符串 --存进--> UserDefaults 的某个 key
    ↑                                                    │
    └────────JSONDecoder<---------------------------------┘
```

界面上用 `@AppStorage("那个key")` 读写，好处是 SwiftUI 会自动观察变化、刷新界面。

**④ 错误必须一路抛到用户脸上**

这是踩过坑改出来的：以前终端的错误被就地 `print` 掉了，而 `print` 在 Release 版里根本无处可见——用户看到的是「点了没反应」，完全不知道发生了什么。现在所有失败都 `throws` 到 `AppCommands`，由它弹出带「打开授权设置」按钮的对话框。

**⑤ 能抽成纯函数的一定抽出来**

「纯函数」= 不看全局状态、不改外部世界、给同样的输入永远返回同样的输出。这样的函数**能脱离 App 单独测试**。

比如 `PathCopier`（路径格式化）、`KeycodeTable`（键码转显示名）、`EditorStore`（编辑器列表解析）都是纯的，`LXFinderLauncherTests.swift` 里全都在测它们。

---

## 3. 文件地图

```
LXFinderLauncher/
│
├── App/                          【入口与生命周期】
│   ├── LXFinderLauncherApp.swift   @main 程序入口，定义菜单栏和设置两个界面
│   ├── AppDelegate.swift           启动时要做的六件事；热键→动作的分发表
│   ├── AppCommands.swift           ★ 所有用户动作的唯一入口
│   ├── MenuBarFeedback.swift       菜单栏图标「闪一下」的瞬时反馈
│   └── SettingsOpener.swift        打开设置窗口并保证它不被别的窗口挡住
│
├── Views/                        【界面】
│   ├── MenuContentView.swift       菜单栏图标点开后看到的菜单
│   └── SettingsView.swift          设置窗口（侧边栏 + 七个面板）★最大的文件
│
├── Services/                     【与外部系统打交道】
│   ├── FinderPathProvider.swift    问 Finder：你现在在看哪个目录？
│   ├── OSAScriptRunner.swift       通用的 AppleScript 执行工具（开子进程）
│   ├── TerminalLauncher.swift      打开终端 / 在终端里执行命令
│   ├── EditorOpener.swift          用编辑器打开一个目录
│   ├── EditorEntry.swift           编辑器列表的模型与读写（含旧配置迁移）
│   ├── PathCopier.swift            把路径渲染成五种格式的文本
│   └── UpdateChecker.swift         检查更新（拉一个 JSON 比版本号）
│
├── FileCreation/                 【创建文件】
│   ├── FileTemplate.swift          文件类型的模型与读写
│   └── FileCreator.swift           文件名清洗、写盘、弹窗询问
│
├── CustomActions/                【自定义动作】
│   └── CustomAction.swift          动作（名字+命令）的模型与读写
│
├── Hotkey/                       【全局热键】
│   ├── HotkeyManager.swift         热键的定义、注册、注销、撞车检测
│   ├── HotkeyRecorder.swift        设置页里「按下组合键」的录制逻辑
│   └── KeycodeTable.swift          键码 → 显示成 "⇧⌘T" 这种样子
│
├── Templates/                    【资源】
│   ├── blank.docx / .xlsx / .pptx  空白的 Office 文档模板
│
├── Assets.xcassets/              【资源】应用图标、强调色
└── Info.plist                    【配置】告诉系统：这是纯菜单栏 App + 各项权限用途说明
```

测试：

```
LXFinderLauncherTests/     774 行，测纯逻辑（用 Swift Testing 框架）
LXFinderLauncherUITests/    23 行，只测「App 能启动」
```

**总计约 3650 行 Swift 代码。**

---

## 4. 逐文件详解

### 4.1 入口层 `App/`

---

#### `LXFinderLauncherApp.swift`（58 行）

**作用**：程序的起点。SwiftUI 里带 `@main` 标记的 `App` 结构体就是入口，相当于其它语言的 `main()`。

**内容**：

```swift
@main
struct LXFinderLauncherApp: App {
    var body: some Scene {
        MenuBarExtra { MenuContentView() } label: { MenuBarIconView() }
            .menuBarExtraStyle(.menu)

        Settings { SettingsView() }
    }
}
```

`Scene` 可以理解成「一种界面」：

| Scene | 是什么 |
|---|---|
| `MenuBarExtra` | **菜单栏图标**。点它弹出的内容由 `MenuContentView` 决定，图标本身由 `MenuBarIconView` 决定 |
| `Settings { }` | 设置窗口。macOS 会自动把它放到 App 菜单的「设置…」下 |

`.menuBarExtraStyle(.menu)` 很关键：它让弹出的内容表现得像**原生菜单**（有菜单那种高亮、键盘导航），而不是一个浮动的面板。代价是菜单项只能用 `Button("文字")` 这种最朴素的写法，图标、自定义视图都不渲染——这一点在 `MenuContentView` 里还会提到。

同一个文件里还有两个小东西：

- `MenuBarIconView` —— 菜单栏上那个 18×18 的小图标。它读 `@AppStorage("menuBarIconStyle")` 决定显示 App 图标还是终端图标，另外还观察 `MenuBarFeedback` 来显示「闪一下」的反馈。
- `AppIconImage.menuBar()` —— 把 App 图标缩放到菜单栏尺寸的小工具。

---

#### `AppDelegate.swift`（85 行）

**作用**：启动时该做的事，以及「按了热键 → 执行哪个动作」的分发表。

`@NSApplicationDelegateAdaptor(AppDelegate.self)` 让 SwiftUI 能挂一个传统的 AppKit 代理进来——因为有些事 SwiftUI 的 `App` 里没法做（比如启动时机、`NSApplication` 级别的事件）。

**`applicationDidFinishLaunching` 里的六件事，顺序不能乱**：

| 顺序 | 做什么 | 为什么是这个位置 |
|---|---|---|
| ① | `GlobalHotkey.registerDefaults()` | **必须最先**。`@AppStorage` 的默认值只存在于自己的包装器里、不会写进 UserDefaults；而读热键配置的代码是直接读 UserDefaults 的。不先注册默认值，`bool` 会读成 `false`（热键根本注册不上），`integer` 会读成 `0`——而 `0` 正好是字母 A 的键码，会**全局劫持字母 A** |
| ② | 给 `HotkeyManager.shared.onTrigger` 赋值 | 这是一个 `switch`，把每个热键映射到 `AppCommands` 的某个方法 |
| ③ | `HotkeyManager.shared.applySettings()` | 按配置注册全部热键 |
| ④ | 预检Finder授权 | 主动问一次 Finder 目录，让授权框在用户第一次点击**之前**就弹出来 |
| ⑤ | 首次运行弹欢迎框 | 用 `hasSeenWelcome` 这个键保证只弹一次 |
| ⑥ | 后台检查更新 | 用 `object(forKey:) as? Bool ?? true` 读开关——注意不是 `bool(forKey:)`，因为要区分「用户关掉了」和「键不存在」 |

**②那个 switch 长这样**：

```swift
HotkeyManager.shared.onTrigger = { hotkey in
    switch hotkey {
    case .openTerminal: AppCommands.shared.openTerminalHere()
    case .createFile:   AppCommands.shared.createFileQuickly()
    case .openEditor:   AppCommands.shared.openInEditorFirst()
    case .copyPath:     AppCommands.shared.copyCurrentPath()
    }
}
```

这是**穷尽 switch**：如果不给新加的热键写分支，编译器直接报错。这是 Swift 的一个很有用的特性——它保证你不会忘记处理新情况。

---

#### `AppCommands.swift`（253 行）★

**作用**：**所有用户动作的唯一入口**。

不管用户是按热键还是点菜单，最终都调这个类里的方法。这样做的好处是：动作的实现只有一份，不会出现「菜单能用热键不能用」。

它是一个**单例**（`static let shared`），`private init()` 保证外面不能自己 new 一个。

```swift
@MainActor
final class AppCommands {
    static let shared = AppCommands()
    private init() {}
    ...
}
```

`@MainActor` 是 Swift 并发安全的标记，意思是「这个类里的东西只能在主线程上用」。这很重要，因为所有 UI 操作（弹窗、改剪贴板）都必须在主线程。

**公开的方法（也就是这个 App 能做的所有事）**：

| 方法 | 做什么 |
|---|---|
| `openTerminalHere()` | 在当前目录开终端 |
| `openInEditor(_:)` | 用指定的一个编辑器打开 |
| `openInEditorFirst()` | 用编辑器列表里第一个打开（热键用） |
| `runAction(_:)` | 执行一条自定义动作 |
| `createFile(using:)` | 弹窗问名字，然后创建文件 |
| `createFileQuickly()` | 不弹窗，直接建一个「未命名」文件（热键用） |
| `copyCurrentPath(format:)` | 把路径按指定格式复制到剪贴板 |
| `revealInFinder()` | 在 Finder 里打开当前目录 |
| `checkForUpdates(silent:)` | 检查更新 |

注意每个方法的骨架几乎都一样——**「取值 → 做事 → 出错就弹窗」**：

```swift
func openTerminalHere() {
    do {
        let url = try FinderPathProvider.currentDirectory()   // 取值
        try launcher.openTerminal(at: url, mode: terminalMode) // 做事
    } catch {
        presentError(error)                                     // 出错就弹窗
    }
}
```

**两个私有但很重要的方法**：

`presentError(_:)` —— 统一的错误弹窗。它先 `NSApp.activate(ignoringOtherApps: true)` 把自己激活，否则菜单栏 App 的弹窗会**落在别的窗口后面**，用户以为没反应。然后如果这个错误是「授权被拒」，它会多给一个「打开授权设置」按钮，点了直接跳到系统设置里对应的面板。

`privacySettingsURL(for:)` —— 判断某个错误该跳到哪个系统设置面板：

| 错误类型 | 跳转到 |
|---|---|
| `FinderPathError.tccDenied` | 隐私与安全性 → 自动化 |
| `OSAScriptError.tccDenied` | 隐私与安全性 → 自动化 |
| `FileCreationError.noPermission` | 隐私与安全性 → 文件与文件夹 |
| 其它 | 不给按钮，只有一个「好」 |

最后那个 `else` 分支很重要：**不是授权问题就不要给「打开授权设置」按钮**，否则会把用户引到一个无关的面板，白费功夫。

---

#### `MenuBarFeedback.swift`（48 行）

**作用**：让菜单栏图标「闪一下」。

**为什么需要它**：复制路径这个操作成功后，屏幕上**什么变化都没有**——剪贴板悄悄换了内容。用户按了热键却看不到任何反馈，会以为热键坏了。

**怎么实现的**：一个单例，持有一个 `flashSymbol` 属性：

```swift
@MainActor
final class MenuBarFeedback: ObservableObject {
    static let shared = MenuBarFeedback()
    @Published private(set) var flashSymbol: String?   // 非 nil 时图标换成这个符号
    private var resetTask: Task<Void, Never>?

    func flash(_ symbol: String = "checkmark.circle.fill") {
        flashSymbol = symbol
        resetTask?.cancel()                    // 取消上一次的复位计时
        resetTask = Task {
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            self.flashSymbol = nil
        }
    }
}
```

三个设计点：

1. **`@Published`** 让 `MenuBarIconView` 能观察到变化并重绘。
2. **先取消上一次的计时再重启**：连续触发时会延长这次闪烁，而不是排队闪两下——快速连按两次热键，用户应该看到一次持续的反馈。
3. **700ms**：太短看不见，太长会让图标看起来像被永久改变了。

---

#### `SettingsOpener.swift`（78 行）

**作用**：打开设置窗口，并保证它**显示在最前面**。

**为什么需要**：这个 App 是菜单栏应用（`Info.plist` 里 `LSUIElement = true`），它的性质是「平时不是前台 App」。SwiftUI 的 `Settings` 场景只负责把窗口显示出来，**不会**激活这个 App——所以当你在别的 App 里（比如 Finder）打开设置，窗口会出现在 Finder 后面，看起来像没打开。

**怎么做的**：

1. 通过一个隐藏的 `NSViewRepresentable`（`SettingsWindowCapture`）在设置窗口出现时抓到它的 `NSWindow` 引用并缓存起来。SwiftUI 没有公开获取 `Settings` 场景窗口的 API，这是最稳的办法。
2. 打开时先 `NSApp.activate(ignoringOtherApps: true)` 把自己变成前台 App，再 `makeKeyAndOrderFront` 把窗口提到最前。

**还有一个细节**：`open(pane:)` 能指定打开到哪个面板。它不是用一个「一次性标记」，而是把面板名**写进 UserDefaults**——因为设置窗口**已经开着**的时候也要能切过去，用一次性标记的话第二次点就没反应了。`SettingsView` 用 `@AppStorage` 读同一个键，所以键一变界面立刻跟着变。

---

### 4.2 界面层 `Views/`

---

#### `MenuContentView.swift`（178 行）

**作用**：菜单栏图标点开后看到的那份菜单。

**这个文件里最重要的知识**：`.menuBarExtraStyle(.menu)` 有两条限制。

**限制一：打开菜单不会触发视图重算。**

SwiftUI 靠「状态变化」来决定要不要重算界面，而「用户打开了菜单」不是一个状态变化（这是 SwiftUI 的一个已知问题，[FB13683957](https://github.com/feedback-assistant/reports/issues/477)）。

后果：菜单里显示的内容如果是从设置读出来的，就**必须用 `@AppStorage` 读**——它是 SwiftUI 能观察到的依赖。如果用 `UserDefaults.standard.string(forKey:)` 这种静态读法，改完设置要**重启 App** 菜单才会更新。

```swift
// ✅ 对：@AppStorage 会被观察
@AppStorage(EditorStore.defaultsKey) private var editorsJSON = ""

// ❌ 错：静态读，改设置后要重启才生效
let json = UserDefaults.standard.string(forKey: "editors")
```

**限制二：菜单里只能用最简单的 `Button("文字")`。**

`Label` 的图标、各种 `modifier`、自定义视图在菜单里都不会渲染。所以你会看到菜单项全都是朴素的文字按钮。

**菜单的结构**（和用户看到的对应）：

```
在此处打开终端
用 XXX 打开               ← 只启用 1 个编辑器时；≥2 个时变成子菜单
复制路径 ▸                ← 子菜单：5 种格式
打开 Finder 目录
─────────────────
创建文件 ▸
自定义动作 ▸
─────────────────
检查更新…
设置…
─────────────────
退出 LXFinderLauncher
```

**为什么有些菜单项要写 `DispatchQueue.main.async`？**

```swift
Button("管理文件类型…") {
    DispatchQueue.main.async {                      // ← 为什么要这样
        SettingsOpener.open(pane: .newFile) { openSettings() }
    }
}
```

因为要弹窗的操作如果直接调用，弹窗会在**菜单还处于「按下」状态**时就弹出来，抢不到键盘焦点。丢到下一个 runloop 周期（`async`）等菜单先关掉，弹窗才能正常获得焦点。

---

#### `SettingsView.swift`（854 行）★ 最大的文件

**作用**：设置窗口的全部界面。

**它为什么这么大**：因为它包含七个面板，而且其中三份「可编辑列表」各自都要一套完整的增删改排序逻辑。

**结构**：

```
SettingsView
├── sidebar          左侧边栏（List + .listStyle(.sidebar)）
└── detail           右侧详情
    ├── generalPane      通用：菜单栏图标、开机自启、检查更新
    ├── shortcutsPane    快捷键：每个热键一行（开关 + 名称 + 录制按钮）
    ├── terminalPane     终端：Terminal / iTerm2 / 自定义
    ├── editorPane       编辑器：列表
    ├── newFilePane      创建文件：类型列表
    ├── actionsPane      自定义动作：动作列表
    └── permissionsPane  权限：直达系统设置面板的按钮
```

**`SettingsPane` 枚举** —— 侧边栏的每一项：

```swift
enum SettingsPane: String, CaseIterable, Identifiable {
    static let defaultsKey = "settingsPane"
    case general, shortcuts, terminal, editor, newFile, actions, permissions
    var title: String { ... }   // 侧边栏显示的名字
    var symbol: String { ... }  // 侧边栏显示的图标名
}
```

`rawValue` 默认就是 case 名（`"general"` 等），它会被**存进 UserDefaults**。所以**改 case 名等于让老用户停留在哪个面板的记录失效**——这是持久化契约，发布后不能随便改名。

加一个新面板要改四处：枚举本身、`title`、`symbol`、`detail` 里的 switch。其中三处是穷尽 switch，编译器会提醒你。

**三份列表的「写回管线」** —— 这是这个文件里最值得理解的部分。

以「创建文件」的类型列表为例，界面上的编辑过程是这样的：

```
用户敲字 → @State templates（内存里的草稿数组）
              ↓ .onChange 触发
          防抖 400ms（连续输入只保留最后一次）
              ↓
          和「上次已同步的值」比较
              ↓ 变了才写
          @AppStorage fileTemplatesJSON → UserDefaults
```

**为什么要这么绕？** 三个原因，缺一不可：

1. **不要直接绑 `@AppStorage`**：那样每敲一个字符都会写一次 UserDefaults，连带菜单视图反复重算。
2. **要防抖**：菜单栏菜单在反复重算时有个已知的渲染问题（列表会「追加而非替换」），所以要尽量少触发。
3. **必须和「上次已同步的值」比较**：这一条**不是性能优化，是必需的**——`onAppear` 装载列表这个动作本身也会触发 `onChange`，如果不拦住，「只是打开了一下设置页」就会把当前值固化进 UserDefaults。以后版本想给新用户加默认项，老用户就再也看不到了。

三份列表各有一套 `@State`：`templates` / `editors` / `actions`，各自有自己的防抖任务句柄和「上次已同步的 JSON」。**不能共用一个任务句柄**——共用会让编辑一份列表时把另一份还没落盘的改动取消掉。

---

### 4.3 服务层 `Services/`

---

#### `FinderPathProvider.swift`（95 行）

**作用**：问 Finder「你当前窗口在看哪个目录」，拿到一个路径。

**核心是这段 AppleScript**：

```applescript
tell application "Finder"
    try
        return POSIX path of (target of front window as alias)
    on error errMsg number errNum
        if errNum is -1743 then error errMsg number errNum   -- 授权被拒，必须抛出去
        try
            repeat with w in windows                          -- 前窗取不到就枚举所有窗口
                try
                    return POSIX path of (target of w as alias)
                on error
                end try
            end repeat
        end try
        return POSIX path of (path to desktop folder)          -- 全都失败就回退桌面
    end try
end tell
```

三个细节：

- `-1743` 是「用户拒绝了自动化授权」的错误码。这个**不能**被 try 兜住，必须往外抛——不然用户看到的就是「路径莫名其妙变成桌面了」而不是「你没授权」。
- `POSIX path of` 把 AppleScript 的路径格式（`Macintosh HD:Users:me:...`）转成 Unix 格式（`/Users/me/...`）。
- 上层 `currentDirectory()` 在本机没装 Finder 时会直接返回桌面，不浪费一次子进程调用。

---

#### `OSAScriptRunner.swift`（88 行）

**作用**：执行 AppleScript 的通用工具。整个项目所有跟 Finder / 终端说话的代码，最后都落到这里。

**它是怎么执行的**：开一个子进程跑系统的 `/usr/bin/osascript`：

```swift
task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
task.arguments = ["-e", script, "--"] + arguments
```

**为什么要开子进程，而不是用 `NSAppleScript`？**

这是这个项目**最重要的一个坑**：菜单栏 App 直接发 Apple Events，系统**不会弹出授权框，而是静默拒绝**（返回 `-1743`）。走 `osascript` 子进程，授权框才会正常弹出来。

**参数是怎么传的**——注意 `-e` 后面跟脚本、再往后是参数，脚本里用 `on run argv` 接收：

```applescript
on run argv
    set thePath to item 1 of argv
    ...
end run
```

这样做是为了**避免把内容拼进脚本源码**。假设目录是 `/Users/me/it's here`，如果拼进 AppleScript 字符串，那个单引号会破坏语法。走 argv 就完全没有转义问题。

**`--` 是干什么的**：`osascript` 用自己的参数解析器（getopt），**以 `-` 开头的参数会被它当成自己的选项**。实测 `osascript -e … -foo` 会直接报 `illegal option -- f`。用户配的自定义命令完全可能是 `--help`、`-la` 这种形式，所以必须在参数前加 `--` 表示「选项到此为止」。

**错误处理**：脚本失败时 `osascript` 会在 stderr 输出形如 `… (-1743)` 的文字。这里会去里面找错误码，翻译成 `OSAScriptError.tccDenied` / `.timeoutOrBusy` / `.unknown`。

---

#### `TerminalLauncher.swift`（373 行）

**作用**：打开终端，以及在终端里执行命令。

**结构**：

```
TerminalLauncher（协议）
├── SystemTerminalLauncher    系统 Terminal
├── ITermLauncher             iTerm2
└── CustomTerminalLauncher    用户指定的任意 .app

TerminalLauncherFactory       按设置选一个实现
TerminalCommandScript         把「在目录 X 执行命令 Y」翻译成 AppleScript
TerminalError                 错误类型
```

**协议**（也就是「所有终端都必须会做的事」）：

```swift
protocol TerminalLauncher {
    func openTerminal(at directory: URL, mode: TerminalOpenMode) throws
    func run(_ command: String, at directory: URL, mode: TerminalOpenMode) throws
}
```

注意两个方法都是 `throws`。这是踩坑改出来的——见 [原则④](#2-整体架构)。

**四种「打开方式」的组合**：

| 终端 | 状态 | 怎么打开 |
|---|---|---|
| Terminal | 没运行 | `NSWorkspace.open([目录], withApplicationAt: Terminal.app)`——启动即是一个干净的新窗口 |
| Terminal | 已运行 | AppleScript `do script "cd ..."`——精确控制新窗口 / 新标签页 |
| iTerm2 | 没运行 | 同 Terminal |
| iTerm2 | 已运行 | AppleScript `create window/tab` + `write text` |

**为什么没运行时不用 AppleScript？** 因为 `osascript` 唤起 Terminal 时，Terminal 会先弹一个**默认窗口**，然后我们的脚本再开一个——用户会看到两个窗口。用 `NSWorkspace` 就没有这个问题。

**执行命令的脚本长这样**（注意命令是从 `item 2 of argv` 拿的）：

```applescript
on run argv
    set thePath to item 1 of argv
    set theCommand to item 2 of argv
    tell application "Terminal"
        activate
        do script ("cd " & quoted form of thePath & " && " & theCommand)
    end tell
end run
```

- `quoted form of` 是 AppleScript 的「给 shell 用的引用」，它会把路径安全地加上单引号（`/Users/me/My Documents` → `'/Users/me/My Documents'`）。
- 命令本身**不做任何加工**，原样拼在后面——因为那是用户自己写的 shell 语法，任何「清洗」都是在破坏它。

**`TerminalCommandScript` 这个类型有一个刻意的设计**：它接收 `mode` 但不接收命令，命令只能通过 `OSAScriptRunner` 的 `arguments` 传进去。**从类型层面杜绝了「把命令拼进脚本源码」这种写法。**

**iTerm 有个特别的坑**（代码注释里记着）：不能写 `create window with default profile command "cd …"`——iTerm 把 `command` 当成一次性启动命令，`cd` 一执行完会话就结束、窗口一闪即关。正确做法是先建一个默认的**交互式**会话，再用 `write text` 把 `cd` 送进去，这样 shell 会留在原地。

---

#### `EditorOpener.swift`（103 行）

**作用**：用编辑器打开一个目录。

**结构很薄**，因为三种编辑器（Cursor / VSCode / 自定义）**唯一的区别就是「怎么解析出 App 的路径」**，解析之后的动作完全一样：

```swift
protocol EditorOpener {
    func openEditor(at directory: URL)
}

struct AppBundleEditorOpener: EditorOpener {   // 唯一的实现
    let appURL: URL
    func openEditor(at directory: URL) {
        NSWorkspace.shared.open([directory], withApplicationAt: appURL, ...)
    }
}

enum EditorOpenerFactory {
    static func resolve(_ entry: EditorEntry) throws -> any EditorOpener
    static func isInstalled(_ kind: EditorKind) -> Bool
}
```

**`resolve` 会 `throws`**：如果配置里的编辑器 App 找不到了，它会抛 `EditorOpenError.appNotFound`。这是刻意的——菜单项是照着用户配置渲染的，配置失效时必须说出来，静默返回会让用户以为「点了没反应是 App 坏了」。

**用 `NSWorkspace` 而不是 Apple Events**：走 Launch Services，不需要额外的系统授权。

---

#### `EditorEntry.swift`（179 行）

**作用**：编辑器列表的数据模型 + 读写 + **从旧配置迁移**。

**`EditorKind`** —— 编辑器的种类：

```swift
enum EditorKind: Int, Codable {
    case cursor = 1    // rawValue 沿用旧版本的 editorKind 取值
    case vscode = 2
    case custom = 3
}
```

注意**没有 `0`**：旧版本里 `0` 表示「关闭」，而「关闭」对应的应该是**一个空列表**，不是某个种类。这个区别在迁移时很重要。

**`EditorEntry`** —— 列表里的一项：

```swift
struct EditorEntry: Codable, Identifiable, Hashable {
    let id: UUID          // 稳定标识，列表的增删改排序都靠它
    var kind: EditorKind
    var name: String      // 菜单里显示的名字
    var path: String      // 只有 .custom 用
    var enabled: Bool
}
```

`init(from decoder:)` 是**宽容解码**：单独一个字段缺失或类型不对时退回默认值，而不是让整份配置解码失败。因为硬失败会把用户配了半天的编辑器全丢掉。

**从旧配置派生**（这个文件的精华）：

老版本存的是 `editorKind`（一个整数，单选）+ `customEditorPath`；新版本存 `editors`（一个 JSON 列表）。升级时怎么把旧配置变成新列表？

```swift
static func editors(from json: String, legacyKind: Int, legacyPath: String) -> [EditorEntry] {
    if !json.isEmpty, let list = try? JSONDecoder().decode(...) {
        return list                                   // 新键有值 → 以它为准
    }
    return derived(fromLegacyKind: legacyKind, path: legacyPath)  // 新键为空 → 从旧键派生
}
```

**为什么用「读时派生」而不是「启动时迁移一次」**？两个理由：

1. 一次性迁移会给**从没碰过编辑器的用户**也写进一个 `"[]"`，从此他们享受不到将来版本的默认值。
2. 更糟的是「升级 → 降级改 `editorKind` → 再升级」这条路径：一次性迁移写下的旧值会把用户后来的改动永久回滚掉。

派生是**无状态的**：只要用户没在新列表里动过手，旧键始终是权威。

派生出来的那一项用**固定 UUID**（`2F000000-...-000000000001`），不能写成 `UUID()`——因为这个派生结果会被反复解码去做 SwiftUI 的列表身份比对，每次现生成新 id 会让列表身份抖动。

---

#### `PathCopier.swift`（69 行）

**作用**：把路径渲染成五种格式的文本。

```swift
enum PathCopyFormat: String, CaseIterable, Identifiable {
    case fullPath      // /Users/me/Documents
    case fileName      // Documents
    case cdCommand     // cd '/Users/me/Documents'
    case markdownLink  // [Documents](file:///Users/me/Documents/)
    case fileURL       // file:///Users/me/Documents/
}

enum PathCopier {
    static func text(for url: URL, format: PathCopyFormat) -> String
    static func fileName(of url: URL) -> String
    static func shellQuoted(_ text: String) -> String
}
```

**这个文件为什么值得单独存在**：因为它是**纯函数**，能脱离 App 单独测试。而它处理的是**转义**——最容易出错、出错后果最严重的部分（粘进终端跑不了，或者更糟，跑成了另一条命令）。

**`shellQuoted` 的全部内容就是这一行**：

```swift
"'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
```

单引号引用是 shell 里最安全的引用方式：单引号内的一切都是字面量，`$`、反引号、`!` 通通不解释。**唯一的例外是单引号本身**——它必须写成 `'\''`，意思是「结束引用 + 一个转义的单引号 + 重新开始引用」。

验证过：目录名 `it's $HOME \`x\` here` 生成的命令丢进真实 shell，能正确进去，且 `$HOME` 和反引号**没有被展开**。

---

#### `UpdateChecker.swift`（115 行）

**作用**：检查有没有新版本。

**为什么不用 Sparkle**（macOS 上最常见的更新框架）：Sparkle 强制要求 App 有签名，而这个项目走的是「免费分发、不签名」路线。

**改成什么**：拉一个静态 JSON 比版本号。JSON 放在 GitHub Gist 上，免费、无需服务器：

```json
{
  "version": "1.3.0",
  "downloadURL": "https://github.com/.../releases/latest/download/LXFinderLauncher.zip",
  "notes": "本次更新内容"
}
```

`downloadURL` 用的是 GitHub Releases 的**固定「最新版」链接**——它永远指向「最新一个 Release 里名为 `LXFinderLauncher.zip` 的文件」。所以每次发版只要上传同名的 zip 就行，JSON 里的下载地址永远不用改。

**版本比较** `isNewer(_:than:)` 是纯函数（所以能单测）：把 `1.3.0` 按 `.` 切开、逐段比数字。用 `Int($0.filter { $0.isNumber })` 是为了容忍 `v1.3.0` 这种带前缀的写法。

---

### 4.4 创建文件 `FileCreation/`

---

#### `FileTemplate.swift`（157 行）

**作用**：文件类型的模型与读写。

```swift
struct FileTemplate: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String    // 显示名，如「Word 文档」
    var ext: String     // 扩展名，不含点，如 "docx"
    var enabled: Bool   // 是否出现在菜单里
}
```

**`FileTemplateStore` 里的三个约定**，后来被另外两份列表（编辑器、自定义动作）抄了：

1. **空串 = 首次运行**：`@AppStorage` 的默认值不会写进 UserDefaults，所以键不存在时读到的是 `""`，而 `""` 不是合法 JSON——两种「没有配置」的情况自然落在同一个分支。
2. **能解出 `[]` 就尊重空**：那是用户主动把类型删光了，不能拿默认值盖回去。
3. **默认列表用固定 UUID**：默认列表会被反复解码做列表身份比对，每次现生成新 id 会让列表抖动。

**`menuTemplates(from:)`** 做过滤：只保留「启用的」且「扩展名非空」的项。扩展名为空的是用户在设置页点了「添加类型」还没填完的草稿。

**为什么默认列表里没有 `.doc` / `.xls` / `.ppt`**：这几个是老的 OLE2 二进制格式，没法合成出最小可用的空白文件，留在默认列表里只会得到一个双击报「文件已损坏」的菜单项。

---

#### `FileCreator.swift`（289 行）

**作用**：文件名清洗、写盘、弹窗。

**分成三块，界限很清楚**：

**① `FileNameNormalizer` —— 纯函数，把用户输入变成最终文件名**

```swift
static func resolve(_ input: String, ext: String) throws -> String
```

规则：

| 输入 | 输出 | 为什么 |
|---|---|---|
| `报告` | `报告.md` | 自动补扩展名 |
| `报告.md` | `报告.md` | 已有扩展名就不重复补 |
| `v1.2 报告` | `v1.2 报告.md` | `1.2` 里那个点**不算扩展名**（限制为末尾 1–10 位字母数字） |
| `.gitignore` | `.gitignore` | 点开头的按「点文件」处理，不补成 `.gitignore.md` |
| `a/b:c` | `abc` | 去掉 `/` 和 `:` |

**② `FileCreator.create(...)` —— 写盘，无 UI，可单测**

扩展名是 `docx` / `xlsx` / `pptx` 时，从 App 包里拷贝一个空白模板；其它格式写一个 0 字节文件。

**为什么 Office 格式要带模板**：这三个格式本质上都是 zip 包（OOXML），0 字节的空文件会被 Word / Excel 判为「文件已损坏」。所以 `Templates/` 里随包带了三个最小可用的空白文档。

**③ `promptAndCreate(...)` —— 弹窗交互**

用 `NSAlert` 问文件名，同名时问要不要覆盖。注意每个 `NSAlert` 前面都有 `NSApp.activate(ignoringOtherApps: true)`——原因和 `SettingsOpener` 一样，不激活的话弹窗会落到别的窗口后面。

---

### 4.5 自定义动作 `CustomActions/`

---

#### `CustomAction.swift`（119 行）

**作用**：一条「自定义动作」的模型与读写。

```swift
struct CustomAction: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String      // 显示名
    var command: String   // 要执行的命令，如 "npm run dev"
    var enabled: Bool
}
```

**`defaultActions` 是空的**，这是刻意的：这个列表里每一条都会被**真的拿去执行**，默认塞一条示例等于替用户决定在他自己的目录里跑什么。

**`menuActions(from:)` 过滤三种情况**：

1. 没勾选的
2. 名字或命令为空的（用户在设置页点了「添加动作」还没填完的草稿）
3. **命令超过 1024 字符的**——Terminal 的 `do script` 和 iTerm 的 `write text` 对超长文本没有明确的行为保证，可能在终端那边被截断成另一条命令，宁可不显示

**`normalize`** 的规则要特别注意：

```swift
result.name = action.name.trimmingCharacters(in: .whitespacesAndNewlines)
result.command = action.command
    .trimmingCharacters(in: .whitespacesAndNewlines)
    .replacingOccurrences(of: "\n", with: " ")   // 换行压成空格
    .replacingOccurrences(of: "\r", with: " ")
```

- 名字：去掉首尾空白。
- 命令：去首尾空白 + **把换行压成空格**，**中间一个字符都不动**。

**为什么必须处理换行**：换行会变成终端里的多次回车，等于把一条命令拆成几条依次执行，语义完全变了。

**为什么中间不能动**：命令里可能有 `&&`、引号、管道、`$`，任何「清洗」都是在破坏它。

---

### 4.6 热键 `Hotkey/`

---

#### `HotkeyManager.swift`（288 行）

**作用**：热键的定义、注册、注销、撞车检测。

**第一部分：`GlobalHotkey` 枚举** —— 定义有哪些热键：

```swift
enum GlobalHotkey: UInt32, CaseIterable, Identifiable {
    case openTerminal = 1
    case createFile = 2
    case openEditor = 3
    case copyPath = 4
    ...
}
```

`UInt32` 的 `rawValue` 就是 Carbon 热键的 ID。加一个 case 时，编译器会强制你补齐四个计算属性：`title`、`keyPrefix`、`defaultKeyCode`、`defaultModifiers`。这是好事——不会漏。

**注意 `keyPrefix` 里的这条注释**：

```swift
/// `openTerminal` 必须沿用 "hotkey" 这个旧前缀，**不要**改成对称的 "openTerminalHotkey"——
/// 改了等于让老用户已经录好的组合键丢失。
case .openTerminal: return "hotkey"
```

老用户录的组合键存在 `hotkeyKeyCode` / `hotkeyModifiers` 这些键里，前缀一改就读不到了。有一个测试专门锁着这条。

**第二部分：`HotkeyManager` 单例** —— 真正干活的。

```swift
func register(_ hotkey: GlobalHotkey, keyCode: UInt32, modifiers: UInt32) -> Bool
func unregister(_ hotkey: GlobalHotkey)
func applySettings()          // 按 UserDefaults 里的配置注册全部热键
```

**Carbon 回调的几个关键点**（代码注释里写得很详细）：

1. **`EventHotKeyRef` / `EventHandlerRef` 必须强持有**（存在字典里），丢了引用热键会**静默失效**。
2. **C 回调不能捕获 `self`**（它是 C 闭包），所以通过 `userData` 把对象传进去。
3. **返回 `eventNotHandledErr` 才是「放行」**——返回任何其它值都会**终止事件传递**。所以处理器必须校验 `EventHotKeyID.signature`，不是自己的一律放行，否则会吞掉同一 target 上 AppKit / SwiftUI 内部注册的热键事件。
4. **事件处理器全程只装一次**——装两次会让一次按键触发两次回调。

**`applySettings()` 里的撞车检测**值得看：它遍历所有热键，用一个字典记录「哪些组合键已经被占了」。如果两个热键配成了同一个组合，后一个会被标记成 `.duplicate(of:)` 并给出提示文案。

注意提示文案分两种，**必须区分开**：

- `.duplicate` → 「与『另一个热键』的快捷键重复，请重新录制」 ← 该改的是**另一个热键**
- `.failed` → 「注册失败：可能被系统保留，或已被某个独占注册的 App 占用」 ← 该改的是**这个组合键**

说成同一个会把用户引到错误的操作上。

**还有一个反直觉的事实**（注释里写了）：Carbon 全局热键**不是系统级独占**的。跨进程重复注册不会失败，两边都会收到通知——所以「注册成功」不等于「别的 App 收不到」。

---

#### `HotkeyRecorder.swift`（111 行）

**作用**：设置页里「按下组合键」的录制逻辑。

**怎么录**：用 `NSEvent.addLocalMonitorForEvents(matching: .keyDown)` 装一个本地键盘监听，把按下的键转成 `(keyCode, carbonModifiers)`。

```swift
monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
    if Self.isModifierKeyCode(keyCode) { return nil }   // 纯修饰键忽略
    let carbon = Self.carbonModifiers(from: flags)
    guard carbon != 0 else { return nil }               // 拒绝无修饰键的裸按键
    self.finish(...)
    return nil                                          // 返回 nil = 吞掉这个按键
}
```

**本地监听返回 `nil` 在 AppKit 里等于「吞掉这个按键」**，返回 `event` 才是放行。

**这里有个很细的取舍**（注释里写明了）：开始录制时只注销**正在录的那一个**热键，另一个保持可用。代价是录制 A 时如果用户按下了 B 的组合键，B 的动作会**真的执行**（对「创建文件」来说意味着录制中途可能凭空多出一个文件）。另一种做法是录制期间全注销，但代价是录制中途崩溃会让两个热键都静默失效。作者选了前者。

**`cancel()` 必须有**：

```swift
func cancel() {
    removeMonitor()
    guard recordingTarget != nil else { return }
    recordingTarget = nil
    HotkeyManager.shared.applySettings()   // ← 把注销掉的热键注册回来
}
```

因为 `begin()` 会先注销那个热键，而收尾只靠 `finish()`（录制成功才调）。少了 `cancel()`，用户点了录制又直接关掉设置窗口，热键就再也不会被注册回来——**快捷键静默失效**。这是修复过的一个真实 bug。

**孤儿监听器的坑**：闭包里如果 `self` 已释放，必须 `return event`（放行）而不是 `return nil`——返回 `nil` 会变成一个「吞掉全 App 所有按键」的孤儿监听器。

---

#### `KeycodeTable.swift`（110 行）

**作用**：把键码翻译成人看得懂的样子（`17` + `768` → `"⇧⌘T"`）。

**为什么字母要显式映射**：键盘扫描码不按字母顺序连续（`A` 是 0、`S` 是 1、`D` 是 2……），所以只能用一张表。

**修饰键的拼接顺序是 `⌃⌥⇧⌘`**：

```swift
if modifiers & controlKey != 0 { result += "⌃" }
if modifiers & optionKey  != 0 { result += "⌥" }
if modifiers & shiftKey   != 0 { result += "⇧" }
if modifiers & cmdKey     != 0 { result += "⌘" }
```

这正是 Apple 官方的书写顺序，所以 `cmdKey | shiftKey` 显示成 **`⇧⌘T`** 而不是 `⌘⇧T`。写文档时要注意这个顺序。

---

### 4.7 资源与配置

| 文件 | 说明 |
|---|---|
| `Templates/blank.docx` `.xlsx` `.pptx` | 空白 Office 模板，由 `scripts/make-blank-templates.sh` 生成。**不要手工改**——它们会在构建时被拷进 App 包 |
| `Assets.xcassets/AppIcon.appiconset/` | 应用图标的全套尺寸（16pt 到 512pt@2x） |
| `Assets.xcassets/AccentColor.colorset/` | 界面强调色 |
| `Info.plist` | 见下 |

**`Info.plist` 里最关键的一条**：

```xml
<key>LSUIElement</key>
<true/>
```

`LSUIElement = true` 让这个 App 变成**纯菜单栏应用**：没有 Dock 图标、不出现在 Cmd+Tab 的 App 切换器里。这是「菜单栏工具」的标志性配置。

另外还有几条 **TCC 用途说明**，它们会在系统弹授权框时显示给用户看：

| 键 | 什么时候用 |
|---|---|
| `NSAppleEventsUsageDescription` | 弹「控制 Finder / 控制 Terminal」授权框时 |
| `NSDesktopFolderUsageDescription` | 往桌面写文件被拦时 |
| `NSDocumentsFolderUsageDescription` | 往文稿写文件被拦时 |
| `NSDownloadsFolderUsageDescription` | 往下载写文件被拦时 |

**这三条文件夹说明是必需的**：缺了它们，系统会**直接拒绝**而不是弹窗征询——用户连授权的机会都没有。而 `FinderPathProvider` 在取不到 Finder 窗口时会回退到桌面，正好落在受保护的范围内。

---

### 4.8 测试

#### `LXFinderLauncherTests.swift`（774 行）

用 **Swift Testing** 框架（`import Testing`、`@Test`、`#expect`），不是老的 XCTest。当前共 **15 个测试套件、85 条用例**。

**测的全是纯逻辑**，因为只有纯逻辑能脱离 App 单独跑：

| 测试套件 | 测什么 |
|---|---|
| `LXFinderLauncherTests` | 键码转显示名 |
| `UpdateCheckerTests` | 版本号比较 |
| `FileTemplateStoreTests` | 列表解析、宽容解码、往返保序 |
| `FileNameNormalizerTests` | 文件名清洗的各种边界 |
| `FileCreatorTests` | 真的往临时目录写文件来验证 |
| `GlobalHotkeyTests` | 热键前缀唯一、默认组合不撞车 |
| `QuickCreateTemplateTests` | 热键直建时选哪个类型 |
| `EditorStoreTests` | 编辑器列表解析 + 旧配置派生 |
| `CustomActionStoreTests` | 动作列表 + 草稿过滤 + 命令规范化 |
| `TerminalCommandScriptTests` | 生成的脚本里**必须有** `item 2 of argv` |
| `TerminalLauncherErrorTests` | 自定义终端缺失时要抛错，不能静默 |
| `AppleScriptSyntaxTests` | 用 `osacompile` **真的编译一遍**生成的脚本 |
| `OSAScriptRunnerArgumentTests` | 参数原样送达（含 `--help` 这种以 `-` 开头的） |
| `PrivacySettingsURLTests` | 授权错误映射到正确的系统设置面板 |
| `PathCopierTests` | 五种格式的转义 |

**其中两个测试的思路值得学**：

- `AppleScriptSyntaxTests`：光比较字符串是抓不到语法错的（项目里踩过「`on run argv` 少了 `end run` 报 -2741」），所以它调 `osacompile` 把生成的脚本**真编译一遍**。只编译不执行，不会打开任何终端窗口。
- `readmeExampleMatchesActualOutput`：把 README 里那张示例表格的五个值**钉死**。以后改了实现却忘了改文档，这条测试会红。

#### `LXFinderLauncherUITests.swift`（23 行）

只测「App 能启动」。UI 测试跑得慢、也难维护，这个项目只留了最小的一条。

---

## 5. 三条完整的调用链

看懂这三条，整个项目就通了。

### 链路 A：按 ⌃⌥⌘C 复制路径

这是**最简单也最完整**的一条，因为它不涉及 Apple Event 到目标应用。

```
① 用户按下 ⌃⌥⌘C
        │
② Carbon 捕获到热键（系统级，App 不在前台也能收到）
        │  回调里校验 signature 是 'FLTH'，取出 ID = 4
        ▼
③ HotkeyManager 的 C 回调
   → Task { @MainActor } 派发到主线程
   → manager.onTrigger?(.copyPath)
        │
④ AppDelegate 里那个 switch
   → case .copyPath: AppCommands.shared.copyCurrentPath()
        │
⑤ AppCommands.copyCurrentPath(format: .fullPath)
   │
   ├─ 先问 Finder 当前目录：
   │     FinderPathProvider.currentDirectory()
   │       → OSAScriptRunner.run(脚本)          ← 开子进程 /usr/bin/osascript
   │       →   osascript 编译脚本 → 发 Apple Event 给 Finder
   │       →   Finder 返回 POSIX path
   │       → 返回 URL(fileURLWithPath:..., isDirectory: true)
   │
   ├─ PathCopier.text(for: url, format: .fullPath)   ← 纯函数，渲染成文本
   │
   ├─ NSPasteboard.general.clearContents()
   │  NSPasteboard.general.setString(..., forType: .string)   ← 写剪贴板
   │
   └─ MenuBarFeedback.shared.flash()
        → flashSymbol = "checkmark.circle.fill"
        → @Published 触发 →
⑥ MenuBarIconView 重绘，菜单栏图标变成勾
        │
⑦ 700ms 后 Task 醒来，flashSymbol = nil，图标变回去
```

**整条链路涉及的文件**：`HotkeyManager` → `AppDelegate` → `AppCommands` → `FinderPathProvider` → `OSAScriptRunner` → `PathCopier` → `MenuBarFeedback` → `LXFinderLauncherApp`。

**耗时大约 240ms**（其中 osascript 启动 + 编译约 50ms，Apple Event 往返约 190ms）。

---

### 链路 B：点菜单「在此处打开终端」

这是**唯一一条会请求第二种授权**的链路。

```
① 用户点菜单栏图标 → 点「在此处打开终端」
        │
② MenuContentView
   → Button("在此处打开终端") { AppCommands.shared.openTerminalHere() }
        │
③ AppCommands.openTerminalHere()
   ├─ FinderPathProvider.currentDirectory()   ← 同上，需要「控制 Finder」授权
   │
   ├─ TerminalLauncherFactory.make()          ← 按设置选实现
   │     读 UserDefaults 的 "terminalKind"：0=Terminal 1=iTerm2 2=自定义
   │
   └─ launcher.openTerminal(at: url, mode: terminalMode)
        │
④ SystemTerminalLauncher.openTerminal
   │
   ├─ if !isRunning {                          ← 分支一：终端没开着
   │      NSWorkspace.shared.open([目录], withApplicationAt: Terminal.app)
   │      → 启动即是一个干净的新窗口，不需要任何授权 ✅
   │  }
   │
   └─ else {                                   ← 分支二：终端已经开着
          try OSAScriptRunner.run(脚本, arguments: [目录路径])
          → osascript → tell application "Terminal" → do script "cd '...'"
          → ⚠️ 需要「控制 Terminal」授权
      }
```

**注意两个分支的授权差异**：分支一不需要授权，分支二需要。所以「第一次用」往往不会弹终端授权，第二次才弹——这个行为容易让人困惑。

**如果授权被拒**：`OSAScriptRunner` 会抛 `OSAScriptError.tccDenied` → 一路抛到 `AppCommands` → `presentError` → 弹出带「打开授权设置」按钮的对话框 → 点了直接跳到「系统设置 → 隐私与安全性 → 自动化」。

---

### 链路 C：点「自定义动作 → 部署」

这是**最复杂**的一条，也是这个项目最有意思的设计。

```
① 用户点 菜单栏图标 → 自定义动作 ▸ → 部署
        │
② MenuContentView
   → Button(action.name) { DispatchQueue.main.async { AppCommands.shared.runAction(action) } }
        │                                          ↑ 等菜单先关掉，弹窗才抢得到焦点
        ▼
③ AppCommands.runAction(_ action: CustomAction)
   ├─ FinderPathProvider.currentDirectory()      ← 问 Finder
   ├─ terminalMode                                ← 读设置的「打开位置」
   └─ launcher.run(action.command, at: url, mode: terminalMode)
        │
④ SystemTerminalLauncher.run(_ command:at:mode:)
   │
   ├─ TerminalCommandScript.terminal(mode: .newWindow)
   │     生成 AppleScript 源码（★ 里面**没有**命令原文）：
   │       on run argv
   │           set thePath to item 1 of argv
   │           set theCommand to item 2 of argv        ← 命令从这里拿
   │           tell application "Terminal"
   │               activate
   │               do script ("cd " & quoted form of thePath & " && " & theCommand)
   │           end tell
   │       end run
   │
   └─ try OSAScriptRunner.run(脚本, arguments: [目录路径, 命令])
        │
        │  ★ 关键：命令是作为**命令行参数**传进去的，不是拼在脚本字符串里
        │     task.arguments = ["-e", 脚本, "--", 目录路径, 命令]
        │
⑤ osascript 子进程启动
   → AppleScript 运行时把 argv[1] / argv[2] 交给脚本
   → tell application "Terminal"（需要「控制 Terminal」授权）
   → do script "cd '/Users/me/Projects/foo' && npm run dev"
        │
⑥ Terminal 开一个新窗口，shell 执行：
      cd '/Users/me/Projects/foo' && npm run dev
   → 命令跑完，shell 留在原地（因为用的是 do script，不是 command=）
```

**为什么命令一定要走 argv 而不能拼进脚本**：

假设命令是 `echo "it's here"`。如果拼进 AppleScript 源码：

```applescript
do script "cd '/tmp' && echo "it's here""     ← 引号打架，语法直接错
```

拼错了轻则报错，**重则执行了另一条命令**——这是安全问题，不只是 bug。

`TerminalCommandScript` 这个类型**接收 `mode` 但不接收命令**，所以从类型层面就写不出「拼进去」这种代码。`TerminalCommandScriptTests` 里还有一条测试断言「生成的源码里必须出现 `item 2 of argv`」。

**App 全程没有执行任何命令**——它只是「让终端去打这一行字」。所以不需要额外授权，能跑什么完全取决于用户在终端里的权限。

---

## 6. 数据存在哪：UserDefaults 键全表

这个 App **没有数据库、没有配置文件**，所有设置都存在 macOS 的 `UserDefaults` 里。

你可以用下面这条命令看到全部内容：

```bash
defaults read com.linx.LXFinderLauncher
```

### 界面设置

| 键 | 类型 | 默认值 | 用途 |
|---|---|---|---|
| `menuBarIconStyle` | Int | `0` | 0 = App 图标，1 = 终端图标 |
| `settingsPane` | String | `"general"` | 设置窗口停在哪个面板 |
| `launchAtLogin` | Bool | `false` | 开机自启 |
| `autoCheckUpdates` | Bool | `true` | 启动时自动检查更新 |
| `hasSeenWelcome` | Bool | `false` | 首次引导弹过了没 |

### 终端

| 键 | 类型 | 默认值 | 用途 |
|---|---|---|---|
| `terminalKind` | Int | `0` | 0 = Terminal，1 = iTerm2，2 = 自定义 |
| `customTerminalPath` | String | `""` | 自定义终端的 .app 路径 |
| `terminalOpenMode` | Int | `0` | 0 = 新窗口，1 = 新标签页 |

### 列表类（都是 JSON 字符串）

| 键 | 默认值 | 用途 |
|---|---|---|
| `editors` | `""` | 编辑器列表（`[EditorEntry]` 的 JSON） |
| `fileTemplates` | `""` | 文件类型列表（`[FileTemplate]` 的 JSON） |
| `customActions` | `""` | 自定义动作列表（`[CustomAction]` 的 JSON） |
| `lastUsedFileTemplateExt` | `""` | 热键直建时「上次用过的扩展名」 |

**为什么 `lastUsedFileTemplateExt` 存的是扩展名而不是 id**：列表本身是可编辑的，用户删掉再重加会换一个新 id，而扩展名更耐用；`defaults read` 时也一眼看得懂。

### 旧键（只为迁移保留，不要删）

| 键 | 类型 | 用途 |
|---|---|---|
| `editorKind` | Int | 旧版的单选编辑器：0 = 关闭，1 = Cursor，2 = VSCode，3 = 自定义 |
| `customEditorPath` | String | 旧版自定义编辑器的路径 |

这两个键**在新版本里不再被写入**，但 `EditorStore` 在 `editors` 为空时还会读它们来派生。

### 全局热键（每个热键三个键）

键名由 `GlobalHotkey.keyPrefix` 拼出来：

| 热键 | 前缀 | 默认键码 | 默认修饰键 | 显示为 |
|---|---|---|---|---|
| 打开终端 | `hotkey` ⚠️ | `17`（T） | `768`（⌘⇧） | `⇧⌘T` |
| 创建文件 | `createFileHotkey` | `45`（N） | `6400`（⌃⌥⌘） | `⌃⌥⌘N` |
| 用编辑器打开 | `openEditorHotkey` | `14`（E） | `6400`（⌃⌥⌘） | `⌃⌥⌘E` |
| 复制路径 | `copyPathHotkey` | `8`（C） | `6400`（⌃⌥⌘） | `⌃⌥⌘C` |

每个热键有三个键：`<前缀>Enabled`（Bool）、`<前缀>KeyCode`（Int）、`<前缀>Modifiers`（Int）。

⚠️ 「打开终端」的前缀是 `hotkey` 而不是 `openTerminalHotkey`——因为它是最早做的，老用户已经录好的组合键存在 `hotkeyKeyCode` 这些键里，**改名等于让那些配置丢失**。

---

## 7. 术语表

| 术语 | 白话解释 |
|---|---|
| **LSUIElement** | `Info.plist` 里的一个设置。设为 `true` 让 App 变成「纯菜单栏应用」：没有 Dock 图标、不在 Cmd+Tab 里出现 |
| **MenuBarExtra** | SwiftUI 里创建菜单栏图标的 API |
| **SwiftUI / AppKit** | SwiftUI 是苹果新的声明式 UI 框架（描述「界面长什么样」）；AppKit 是老的命令式框架（描述「怎么操作界面元素」）。两者混用是 macOS 开发的常态——本项目用 SwiftUI 搭界面，用 AppKit 做弹窗、剪贴板、打开 App 这些事 |
| **TCC** | 就是你在「系统设置 → 隐私与安全性」里看到的那些权限开关。全称 Transparency, Consent, and Control |
| **Apple Event / AppleScript** | macOS 上 App 之间互相控制的机制。AppleScript 是写这种控制的脚本语言 |
| **osascript** | 命令行工具，用来执行 AppleScript。本项目**开子进程**跑它，而不是在 App 里直接发 Apple Event |
| **automation / 自动化** | TCC 里「让 App 控制另一个 App」的那一类权限 |
| **NSWorkspace** | AppKit 里负责「用某个 App 打开某个文件/目录」的类。走 Launch Services，**不需要** TCC 授权 |
| **Launch Services** | macOS 里负责「什么文件用什么 App 打开」的子系统 |
| **Carbon** | 苹果很老的一套 C 语言 API，大部分已经废弃，但 `RegisterEventHotKey`（全局热键）至今没有现代替代品 |
| **keyCode** | 键盘按键的数字编号。注意它按**物理位置**编码，不按字符 |
| **UserDefaults** | macOS 的键值存储，每个 App 一个（本质是一个 plist 文件）。适合存设置，不适合存大量数据 |
| **@AppStorage** | SwiftUI 的属性包装器，读写 UserDefaults 并**自动刷新界面** |
| **@State / @StateObject / @ObservedObject** | SwiftUI 里三种「状态」，区别在于谁拥有它、变化时谁重绘 |
| **@MainActor** | 标记「只能在主线程上用」。UI 相关的代码几乎都需要它 |
| **纯函数** | 不看全局状态、不改外部世界、同样输入永远同样输出的函数。好处是**能脱离 App 单独测试** |
| **穷尽 switch** | Swift 的 `switch` 如果覆盖了所有可能情况，就不需要写 `default`；漏了一种编译器会报错。本项目用它来保证「加了新热键不会忘记处理」 |
| **throws / do-catch** | Swift 的错误传播机制。函数标 `throws` 表示「我可能失败」，调用处必须用 `try` 并处理 |
| **OOXML** | `.docx` / `.xlsx` / `.pptx` 的内部格式，本质是一个 zip 包 |
| **argv** | 命令行参数数组。本项目用它把数据安全地传给 AppleScript，避免字符串拼接的转义问题 |

---

## 8. 想改代码，从哪下手

### 常见需求 → 该动哪里

| 我想…… | 改哪 |
|---|---|
| 加一个新动作（菜单项） | ① `AppCommands` 加一个方法<br>② `MenuContentView` 加一个 `Button`<br>③ 如果要配热键，`HotkeyManager` 的 `GlobalHotkey` 加 case，再到 `AppDelegate` 的分发 switch 加一行 |
| 支持一个新的终端 | `TerminalLauncher.swift` 加一个实现 `TerminalLauncher` 协议的结构体，再到 `TerminalLauncherFactory.make()` 里加分支 |
| 支持一个新的编辑器 | 通常不用改代码——在设置里「添加编辑器 → 自定义」填路径就行。内置的要加，就在 `EditorKind` 加 case |
| 加一种复制格式 | `PathCopier` 的 `PathCopyFormat` 加 case + `text(for:format:)` 加分支。菜单会自动多一项（它遍历 `allCases`） |
| 加一个设置面板 | 见「界面层 `Views/`」里 `SettingsView.swift` 的说明，要改四处 |
| 改默认热键 | `GlobalHotkey` 的 `defaultKeyCode` / `defaultModifiers`。⚠️ 只影响**新用户**，老用户的配置已经存在 UserDefaults 里了 |
| 改更新源地址 | `UpdateChecker.feedURL` |
| 加一个文件类型 | 不用改代码，设置页「添加类型」即可。默认列表在 `FileTemplateStore.defaultTemplates` |

### 改代码时的几条硬性约束

这些是踩过坑才定下来的，改之前先看一眼：

1. **不要用 `UserDefaults.standard` 静态读菜单要显示的东西**——`.menuBarExtraStyle(.menu)` 下打开菜单不重算视图，只有 `@AppStorage` 会被观察到。用静态读法，改完设置要重启 App 才生效。
2. **不要改 `openTerminal` 热键的 `keyPrefix`**（`"hotkey"`）——老用户的配置会丢。
3. **不要改 `SettingsPane` 的 case 名**——它是持久化契约，改了老用户停留在哪个面板的记录会失效。
4. **不要把命令 / 路径拼进 AppleScript 源码**——走 `OSAScriptRunner` 的 `arguments`。
5. **不要吞掉错误**——`print` 在 Release 版里无处可见，用户只会看到「点了没反应」。
6. **列表里的默认项要用固定 UUID**，不要写 `UUID()`——否则列表身份每次都在变，界面会抖。

### 推荐的阅读顺序

如果你想系统地读完这个项目：

```
第 1 步   LXFinderLauncherApp.swift      ← 58 行，看 App 由哪两块组成
第 2 步   AppDelegate.swift               ← 85 行，看启动流程
第 3 步   MenuContentView.swift           ← 178 行，看有哪些功能
第 4 步   AppCommands.swift               ← 253 行，看每个功能怎么实现
第 5 步   FinderPathProvider.swift        ← 95 行，看最核心的一次系统调用
第 6 步   OSAScriptRunner.swift           ← 88 行，看它是怎么执行的
第 7 步   TerminalLauncher.swift          ← 373 行，看最完整的服务实现
第 8 步   SettingsView.swift              ← 854 行，最后看，它是纯体力活
```

前七步加起来不到 1200 行，读完就能理解整个项目的运转方式。`SettingsView` 虽然最大，但它是**重复度最高的文件**——理解了其中一个面板，剩下六个都是同一套模式。

---

*本文档随代码更新。如果发现描述和代码对不上，以代码为准，并欢迎顺手把这里也改对。*

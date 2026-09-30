//
//  TerminalLauncher.swift
//  LXFinderLauncher
//
//  Created by 启业云03 on 2026/9/1.
//

import AppKit

/// 终端打开位置：
/// - newWindow：总是新建一个终端窗口；
/// - newTab：当前没有已打开的终端时新建窗口，已有窗口时在窗口里新建标签页。
enum TerminalOpenMode: Int {
    case newWindow = 0
    case newTab = 1
}

/// 终端启动器协议：不同终端、不同打开位置实现 openTerminal / run。
protocol TerminalLauncher {
    /// 在指定目录打开终端。
    ///
    /// - Throws: AppleScript 失败时抛 `OSAScriptError`；配置的终端不存在时抛 `TerminalError`。
    ///
    /// **错误必须往上抛，不能就地吞掉。** 自动化授权被拒（`-1743`）是这里最常见的失败，
    /// 而 `print` 在 Release 构建里根本无处可见——用户看到的就是「点了没反应、也没有提示」，
    /// 完全无从下手。调用方（`AppCommands`）会把 `tccDenied` 翻译成带「打开授权设置」按钮的弹窗。
    func openTerminal(at directory: URL, mode: TerminalOpenMode) throws

    /// 在指定目录执行一条命令。
    ///
    /// 实现方式是把命令**送进终端**（先 `cd` 到目录，再执行），App 自己绝不 fork shell。
    /// 好处是双重的：不新增任何 TCC 授权，「跑什么」的责任也留在用户和终端那边。
    ///
    /// - Throws: `TerminalError`（终端不支持 / 不存在）；AppleScript 失败抛 `OSAScriptError`。
    func run(_ command: String, at directory: URL, mode: TerminalOpenMode) throws
}

/// 终端相关操作的错误。
enum TerminalError: LocalizedError {
    /// 当前配置的终端不支持注入命令（自定义终端只能被 NSWorkspace 打开目录）。
    case unsupportedTerminal(String)
    /// 配置里指的终端 App 找不到。
    case appMissing(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedTerminal(let name):
            return "「\(name)」不支持自动执行命令。请在「设置 → 终端」里改用 Terminal 或 iTerm2。"
        case .appMissing(let name):
            return "找不到「\(name)」。请确认它还在原来的位置，或到「设置 → 终端」里改一下配置。"
        }
    }
}

/// 把「在某个目录执行一条命令」翻译成 AppleScript 源码。
///
/// 单独抽出来是为了能单测——**命令只能通过 argv 注入**这条不变量太关键了：
/// 命令是用户自由输入的，里面可能有引号、反斜杠、`$`，一旦被拼进 AppleScript 的
/// 字符串字面量就会被它的转义规则改写，轻则报语法错，重则执行了另一条命令。
/// 所以源码里只出现 `item 2 of argv`，命令原文只经由 `OSAScriptRunner` 的 arguments 传入。
///
/// 与之配套的是 `OSAScriptRunner.run` 里那个 `--` 参数终止符：命令可能是 `--help`
/// 这种以 `-` 开头的形式，不加 `--` 会被 osascript 自己的 getopt 当成选项吃掉。
enum TerminalCommandScript {

    /// 系统 Terminal。
    static func terminal(mode: TerminalOpenMode) -> String {
        switch mode {
        case .newWindow:
            // do script 不指定 in window，Terminal 会强制新建独立窗口。
            return """
            on run argv
                set thePath to item 1 of argv
                set theCommand to item 2 of argv
                tell application "Terminal"
                    activate
                    do script ("cd " & quoted form of thePath & " && " & theCommand)
                end tell
            end run
            """
        case .newTab:
            return """
            on run argv
                set thePath to item 1 of argv
                set theCommand to item 2 of argv
                tell application "Terminal"
                    activate
                    if (count of windows) is 0 then
                        do script ("cd " & quoted form of thePath & " && " & theCommand)
                    else
                        do script ("cd " & quoted form of thePath & " && " & theCommand) in front window
                    end if
                end tell
            end run
            """
        }
    }

    /// iTerm2。
    ///
    /// 先建默认会话、再 `write text`，理由同 `ITermLauncher.openTerminal` 里那段注释：
    /// iTerm 把 `command=` 当一次性启动命令，`cd` 一跑完会话就结束、窗口一闪即关。
    /// `write text` 是把一行送进已经跑起来的交互式 shell，命令跑完 shell 留在原地。
    static func iTerm(mode: TerminalOpenMode) -> String {
        switch mode {
        case .newWindow:
            return """
            on run argv
                set thePath to item 1 of argv
                set theCommand to item 2 of argv
                tell application "iTerm"
                    activate
                    set theWin to create window with default profile
                    tell current session of theWin to write text ("cd " & quoted form of thePath & " && " & theCommand)
                end tell
            end run
            """
        case .newTab:
            // 同样不能写成「往 front window 的 current session 写」——那可能是用户正在
            // 跑 vim / npm 的那个会话，命令会被直接敲进它里面。必须先 create tab 再写新会话。
            return """
            on run argv
                set thePath to item 1 of argv
                set theCommand to item 2 of argv
                tell application "iTerm"
                    activate
                    if (count of windows) is 0 then
                        set theWin to create window with default profile
                        tell current session of theWin to write text ("cd " & quoted form of thePath & " && " & theCommand)
                    else
                        tell current window to create tab with default profile
                        tell current session of current window to write text ("cd " & quoted form of thePath & " && " & theCommand)
                    end if
                end tell
            end run
            """
        }
    }
}

// MARK: - 系统 Terminal

/// 系统 Terminal 实现：新窗口 / 新建标签页都用 AppleScript 精确控制；
/// 仅当 Terminal 未运行时交给 NSWorkspace（此时必然新开窗口，
/// 也能避免 osascript 唤起时额外弹出一个默认窗口）。
struct SystemTerminalLauncher: TerminalLauncher {

    private static let bundleID = "com.apple.Terminal"

    func openTerminal(at directory: URL, mode: TerminalOpenMode) throws {
        // 未运行 = 还没有任何 Terminal 窗口，两种模式都是新开一个目标目录的窗口。
        if !Self.isRunning {
            openInNewAppWindow(directory)
            return
        }

        // 已运行：用 AppleScript 按模式精确开「新窗口」或「新建标签页」。
        let script: String
        switch mode {
        case .newWindow:
            // do script 不指定 in window，Terminal 会强制新建独立窗口。
            // 不能再用 NSWorkspace.open 目录：Terminal 已运行时系统可能
            // 把它并入已有窗口变成标签页。
            script = """
            on run argv
                set thePath to item 1 of argv
                tell application "Terminal"
                    activate
                    do script "cd " & quoted form of thePath
                end tell
            end run
            """
        case .newTab:
            // 已有窗口则新建标签页；意外无窗口（进程保活）时兜底新建窗口。
            script = """
            on run argv
                set thePath to item 1 of argv
                tell application "Terminal"
                    activate
                    if (count of windows) is 0 then
                        do script "cd " & quoted form of thePath
                    else
                        do script "cd " & quoted form of thePath in front window
                    end if
                end tell
            end run
            """
        }
        try OSAScriptRunner.run(script, arguments: [directory.path])
    }

    func run(_ command: String, at directory: URL, mode: TerminalOpenMode) throws {
        // 已知限制（冷启动）：Terminal 还没运行时，osascript 会先把 Terminal 拉起来
        // （它会自己开一个默认窗口），`do script` 再开一个命令窗口，于是会看到两个窗口。
        // `openTerminal` 靠「没运行就走 NSWorkspace」躲开了这个，但那条路传不了命令。
        // 只在「Terminal 从没开过 + 第一次用自定义动作」时出现，没为它引入轮询等待
        // Terminal 起来的那套异步逻辑——收益不抵复杂度。
        try OSAScriptRunner.run(TerminalCommandScript.terminal(mode: mode),
                                arguments: [directory.path, command])
    }

    /// Terminal 是否已在运行（只查询，不触发启动）。
    private static var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    /// 未运行：让系统以「目录」为启动文档启动，启动即是一个干净的新窗口。
    private func openInNewAppWindow(_ directory: URL) {
        let app = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.open([directory], withApplicationAt: app,
                                configuration: config) { _, error in
            if let error { print("[LXFinderLauncher] 打开 Terminal 失败：\(error)") }
        }
    }
}

// MARK: - iTerm2

/// iTerm2 实现：新窗口 / 新建标签页用 AppleScript 精确控制，未运行交给 NSWorkspace。
struct ITermLauncher: TerminalLauncher {

    private static let bundleID = "com.googlecode.iterm2"

    func openTerminal(at directory: URL, mode: TerminalOpenMode) throws {
        // 设置里选了 iTerm2 但它不在原位时必须说出来——之前这里是 print，
        // Release 构建里用户看到的就是「点了没反应」。
        guard let iterm = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleID) else {
            throw TerminalError.appMissing("iTerm2")
        }
        // 未运行 = 还没有任何 iTerm 窗口，两种模式都是新开一个目标目录的窗口。
        if !Self.isRunning {
            openInNewAppWindow(directory, app: iterm)
            return
        }

        // 已运行：用 AppleScript 按模式精确开「新窗口」或「新建标签页」。
        //
        // 注意：不能写 `create window/tab with default profile command "cd …"`——
        // iTerm 把 command 当一次性启动命令，cd 一执行完会话就结束、窗口一闪即关。
        // 正确做法：先建一个默认的交互式会话窗口，再向它发送 cd 命令，shell 保持存活。
        let script: String
        switch mode {
        case .newWindow:
            // create window 强制新建独立窗口（不能靠 NSWorkspace.open，可能并入已有窗口）。
            script = """
            on run argv
                set thePath to item 1 of argv
                tell application "iTerm"
                    activate
                    set theWin to create window with default profile
                    tell current session of theWin to write text "cd " & quoted form of thePath
                end tell
            end run
            """
        case .newTab:
            // 已有窗口则新建标签页；意外无窗口（进程保活）时兜底新建窗口。
            script = """
            on run argv
                set thePath to item 1 of argv
                tell application "iTerm"
                    activate
                    if (count of windows) is 0 then
                        set theWin to create window with default profile
                        tell current session of theWin to write text "cd " & quoted form of thePath
                    else
                        tell current window to create tab with default profile
                        tell current session of current window to write text "cd " & quoted form of thePath
                    end if
                end tell
            end run
            """
        }
        try run(script, directory: directory)
    }

    func run(_ command: String, at directory: URL, mode: TerminalOpenMode) throws {
        try OSAScriptRunner.run(TerminalCommandScript.iTerm(mode: mode),
                                arguments: [directory.path, command])
    }

    /// iTerm2 是否已在运行（只查询，不触发启动）。
    private static var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    /// 未运行：让系统以「目录」为启动文档启动，启动即是一个干净的新窗口。
    private func openInNewAppWindow(_ directory: URL, app: URL) {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.open([directory], withApplicationAt: app,
                                configuration: config) { _, error in
            if let error { print("[LXFinderLauncher] 打开 iTerm2 失败：\(error)") }
        }
    }

    private func run(_ script: String, directory: URL) throws {
        try OSAScriptRunner.run(script, arguments: [directory.path])
    }
}

// MARK: - 自定义终端

/// 自定义终端：用 NSWorkspace 打开指定 .app（不支持 AppleScript 标签页的通用方案）。
struct CustomTerminalLauncher: TerminalLauncher {
    let appURL: URL

    func openTerminal(at directory: URL, mode: TerminalOpenMode) throws {
        // 配了自定义终端但 App 不在原位时，必须说出来——之前这里是 print，Release 构建里
        // 用户看到的就是「点了没反应」。
        guard FileManager.default.fileExists(atPath: appURL.path) else {
            throw TerminalError.appMissing(appURL.deletingPathExtension().lastPathComponent)
        }

        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.open([directory], withApplicationAt: appURL,
                                configuration: config) { _, error in
            // 这个失败只能异步拿到，没有往上抛的通道；留下控制台痕迹。
            if let error { print("[LXFinderLauncher] 打开自定义终端失败：\(error)") }
        }
    }

    func run(_ command: String, at directory: URL, mode: TerminalOpenMode) throws {
        // 自定义终端只会被 NSWorkspace 打开目录，没有任何注入命令的手段。
        // 菜单里会把自定义动作整段置灰（见 MenuContentView），这里再兜一道，
        // 免得将来有别的调用点绕过菜单直接调。
        throw TerminalError.unsupportedTerminal(
            appURL.deletingPathExtension().lastPathComponent)
    }
}

// MARK: - 工厂

/// 终端工厂：按设置选择具体终端。
enum TerminalLauncherFactory {

    /// UserDefaults 键：terminalKind（0=Terminal 1=iTerm2 2=自定义）、
    /// customTerminalPath、terminalOpenMode（0=新窗口 1=新标签页）。
    static func make() -> any TerminalLauncher {
        switch UserDefaults.standard.integer(forKey: "terminalKind") {
        case 1:
            return ITermLauncher()
        case 2:
            if let path = UserDefaults.standard.string(forKey: "customTerminalPath"),
               FileManager.default.fileExists(atPath: path) {
                return CustomTerminalLauncher(appURL: URL(fileURLWithPath: path))
            }
            return SystemTerminalLauncher()
        default:
            return SystemTerminalLauncher()
        }
    }

    /// 当前终端的显示名（菜单/设置提示用）。
    static func displayName() -> String {
        switch UserDefaults.standard.integer(forKey: "terminalKind") {
        case 1: return "iTerm2"
        case 2:
            if let path = UserDefaults.standard.string(forKey: "customTerminalPath") {
                return (path as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "")
            }
            return "自定义终端"
        default: return "Terminal"
        }
    }

    /// iTerm2 是否已安装（供设置页启用/禁用选项）。
    static func isITermInstalled() -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.googlecode.iterm2") != nil
    }
}

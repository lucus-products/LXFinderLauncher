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

/// 终端启动器协议：不同终端、不同打开位置实现 openTerminal。
protocol TerminalLauncher {
    func openTerminal(at directory: URL, mode: TerminalOpenMode)
}

// MARK: - 系统 Terminal

/// 系统 Terminal 实现：新窗口 / 新建标签页都用 AppleScript 精确控制；
/// 仅当 Terminal 未运行时交给 NSWorkspace（此时必然新开窗口，
/// 也能避免 osascript 唤起时额外弹出一个默认窗口）。
struct SystemTerminalLauncher: TerminalLauncher {

    private static let bundleID = "com.apple.Terminal"

    func openTerminal(at directory: URL, mode: TerminalOpenMode) {
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
        run(script, directory: directory)
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

    private func run(_ script: String, directory: URL) {
        do {
            try OSAScriptRunner.run(script, arguments: [directory.path])
        } catch {
            print("[LXFinderLauncher] Terminal 控制失败：\(error)")
        }
    }
}

// MARK: - iTerm2

/// iTerm2 实现：新窗口 / 新建标签页用 AppleScript 精确控制，未运行交给 NSWorkspace。
struct ITermLauncher: TerminalLauncher {

    private static let bundleID = "com.googlecode.iterm2"

    func openTerminal(at directory: URL, mode: TerminalOpenMode) {
        guard let iterm = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleID) else {
            print("[LXFinderLauncher] 未检测到 iTerm2")
            return
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
        run(script, directory: directory)
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

    private func run(_ script: String, directory: URL) {
        do {
            try OSAScriptRunner.run(script, arguments: [directory.path])
        } catch {
            print("[LXFinderLauncher] iTerm2 控制失败：\(error)")
        }
    }
}

// MARK: - 自定义终端

/// 自定义终端：用 NSWorkspace 打开指定 .app（不支持 AppleScript 标签页的通用方案）。
struct CustomTerminalLauncher: TerminalLauncher {
    let appURL: URL

    func openTerminal(at directory: URL, mode: TerminalOpenMode) {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.open([directory], withApplicationAt: appURL,
                                configuration: config) { _, error in
            if let error { print("[LXFinderLauncher] 打开自定义终端失败：\(error)") }
        }
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

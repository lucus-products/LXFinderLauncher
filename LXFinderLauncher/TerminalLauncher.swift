//
//  TerminalLauncher.swift
//  LXFinderLauncher
//
//  Created by 启业云03 on 2026/9/1.
//

import AppKit

/// 终端打开位置：新窗口 / 当前窗口新建标签页。
enum TerminalOpenMode: Int {
    case newWindow = 0
    case newTab = 1
}

/// 终端启动器协议：不同终端、不同打开位置实现 openTerminal。
protocol TerminalLauncher {
    func openTerminal(at directory: URL, mode: TerminalOpenMode)
}

// MARK: - 系统 Terminal

/// 系统 Terminal 实现：新窗口用 NSWorkspace，新标签页用 osascript 控制。
struct SystemTerminalLauncher: TerminalLauncher {
    func openTerminal(at directory: URL, mode: TerminalOpenMode) {
        switch mode {
        case .newWindow:
            let app = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.open([directory], withApplicationAt: app,
                                    configuration: config) { _, error in
                if let error { print("[LXFinderLauncher] 打开终端失败：\(error)") }
            }
        case .newTab:
            // 在当前 Terminal 窗口新建标签页并 cd；无窗口则新建窗口。
            let script = """
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
            do {
                try OSAScriptRunner.run(script, arguments: [directory.path])
            } catch {
                print("[LXFinderLauncher] Terminal 新建标签页失败：\(error)")
            }
        }
    }
}

// MARK: - iTerm2

/// iTerm2 实现：新窗口用 NSWorkspace，新标签页用 osascript 控制。
struct ITermLauncher: TerminalLauncher {
    func openTerminal(at directory: URL, mode: TerminalOpenMode) {
        switch mode {
        case .newWindow:
            guard let iterm = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.googlecode.iterm2") else {
                print("[LXFinderLauncher] 未检测到 iTerm2")
                return
            }
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.open([directory], withApplicationAt: iterm,
                                    configuration: config) { _, error in
                if let error { print("[LXFinderLauncher] 打开 iTerm2 失败：\(error)") }
            }
        case .newTab:
            // 在当前 iTerm 窗口新建标签页并 cd；无窗口则新建窗口。
            let script = """
            on run argv
                set thePath to item 1 of argv
                tell application "iTerm"
                    activate
                    if (count of windows) is 0 then
                        create window with default profile command "cd " & quoted form of thePath
                    else
                        tell current window to create tab with default profile command "cd " & quoted form of thePath
                    end if
                end tell
            end run
            """
            do {
                try OSAScriptRunner.run(script, arguments: [directory.path])
            } catch {
                print("[LXFinderLauncher] iTerm2 新建标签页失败：\(error)")
            }
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

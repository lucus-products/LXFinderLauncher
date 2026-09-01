//
//  AppDelegate.swift
//  LXFinderLauncher
//
//  Created by 启业云03 on 2026/9/1.
//

import AppKit
import OSLog

private let logger = Logger(subsystem: "com.linx.LXFinderLauncher", category: "AppLifecycle")

final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 全局热键触发 → 打开终端。
        HotkeyManager.shared.onTrigger = {
            AppCommands.shared.openTerminalHere()
        }
        // 按 UserDefaults 配置注册热键。
        HotkeyManager.shared.applySettings()
        logger.debug("热键注册完成")

        // 预检一次自动化授权：首次运行主动弹出「控制 Finder」授权框，
        // 避免用户之后点击时困惑于「路径一直是桌面」。
        Task { @MainActor in
            NSApp.activate(ignoringOtherApps: true)
            do {
                let url = try FinderPathProvider.currentDirectory()
                logger.debug("预检取到目录：\(url.path, privacy: .public)")
            } catch {
                logger.error("预检失败：\(String(describing: error), privacy: .public)")
            }
        }

        // 首次启动欢迎引导。
        if !UserDefaults.standard.bool(forKey: "hasSeenWelcome") {
            UserDefaults.standard.set(true, forKey: "hasSeenWelcome")
            showWelcome()
        }

        // 启动时异步检查更新（默认开启，可在设置中关闭）。
        let autoCheck = UserDefaults.standard.object(forKey: "autoCheckUpdates") as? Bool ?? true
        if autoCheck {
            AppCommands.shared.checkForUpdates(silent: true)
        }
    }

    /// 首次启动弹窗：说明用法与授权。
    private func showWelcome() {
        Task { @MainActor in
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = "欢迎使用 LXFinderLauncher"
            alert.informativeText = """
            在 Finder 当前目录打开终端或编辑器：
            · 点菜单栏 terminal 图标，或按全局快捷键（默认 ⌘⇧T）
            · 首次使用会请求「控制 Finder」的授权，点允许即可。

            设置里可切换终端（Terminal / iTerm2 / 自定义）、
            配置用 Cursor 等编辑器打开、开启开机自启。
            """
            alert.addButton(withTitle: "开始使用")
            alert.runModal()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotkeyManager.shared.unregister()
    }
}

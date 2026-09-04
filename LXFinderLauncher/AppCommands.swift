//
//  AppCommands.swift
//  LXFinderLauncher
//
//  Created by 启业云03 on 2026/9/1.
//

import AppKit

/// 所有用户动作的唯一入口（菜单点击 / 全局热键都走这里）。
@MainActor
final class AppCommands {

    static let shared = AppCommands()

    /// 按设置动态选择终端（Terminal / iTerm2）。
    private var launcher: any TerminalLauncher {
        TerminalLauncherFactory.make()
    }

    private init() {}

    /// 在当前 Finder 目录打开终端（按设置的终端与打开位置）。
    func openTerminalHere() {
        do {
            let url = try FinderPathProvider.currentDirectory()
            let mode: TerminalOpenMode = UserDefaults.standard.integer(forKey: "terminalOpenMode") == 1 ? .newTab : .newWindow
            launcher.openTerminal(at: url, mode: mode)
        } catch {
            presentError(error)
        }
    }

    /// 复制当前 Finder 目录的路径到剪贴板。
    func copyCurrentPath() {
        do {
            let url = try FinderPathProvider.currentDirectory()
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url.path, forType: .string)
        } catch {
            presentError(error)
        }
    }

    /// 在 Finder 中定位当前目录（新窗口打开）。
    func revealInFinder() {
        do {
            let url = try FinderPathProvider.currentDirectory()
            NSWorkspace.shared.open(url)
        } catch {
            presentError(error)
        }
    }

    /// 用配置的编辑器打开当前 Finder 目录。
    func openInEditor() {
        guard let opener = EditorOpenerFactory.make() else { return }
        do {
            let url = try FinderPathProvider.currentDirectory()
            opener.openEditor(at: url)
        } catch {
            presentError(error)
        }
    }

    /// 检查更新。silent = true 时（启动自动检查）失败静默、无新版本不打扰。
    func checkForUpdates(silent: Bool = false) {
        UpdateChecker.check { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let info):
                    if UpdateChecker.isNewer(info.version, than: UpdateChecker.currentVersion) {
                        self?.presentUpdateAvailable(info)
                    } else if !silent {
                        self?.presentMessage("当前已是最新版本（\(UpdateChecker.currentVersion)）。")
                    }
                case .failure(let error):
                    if !silent {
                        self?.presentMessage("检查更新失败：\(error.localizedDescription)")
                    }
                }
            }
        }
    }

    // MARK: - 更新弹窗

    /// 有新版本：弹出下载提示。
    private func presentUpdateAvailable(_ info: UpdateInfo) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "发现新版本 \(info.version)"
        var text = "当前版本：\(UpdateChecker.currentVersion)\n最新版本：\(info.version)"
        if let notes = info.notes, !notes.isEmpty {
            text += "\n\n更新内容：\n\(notes)"
        }
        alert.informativeText = text
        alert.addButton(withTitle: "前往下载")
        alert.addButton(withTitle: "稍后")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(info.downloadURL)
        }
    }

    /// 普通信息弹窗。
    private func presentMessage(_ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "LXFinderLauncher"
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    // MARK: - 错误呈现

    private func presentError(_ error: Error) {
        // 必须先把本 App 激活，否则 accessory 菜单栏 App 的错误弹窗会落在其它窗口后面，
        // 用户（尤其全局快捷键触发时）会以为“没有反应”。
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "LXFinderLauncher"
        alert.informativeText = error.localizedDescription

        if case FinderPathError.tccDenied = error {
            alert.addButton(withTitle: "打开授权设置")
            alert.addButton(withTitle: "取消")
            if alert.runModal() == .alertFirstButtonReturn {
                let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!
                NSWorkspace.shared.open(url)
            }
        } else {
            alert.addButton(withTitle: "好")
            alert.runModal()
        }
    }
}

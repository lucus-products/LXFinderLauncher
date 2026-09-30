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

    /// 设置里的「打开位置」：0 = 新窗口，1 = 新标签页。
    private var terminalMode: TerminalOpenMode {
        UserDefaults.standard.integer(forKey: "terminalOpenMode") == 1 ? .newTab : .newWindow
    }

    /// 在当前 Finder 目录打开终端（按设置的终端与打开位置）。
    func openTerminalHere() {
        do {
            let url = try FinderPathProvider.currentDirectory()
            try launcher.openTerminal(at: url, mode: terminalMode)
        } catch {
            presentError(error)
        }
    }

    /// 执行一条自定义动作：在 Finder 当前目录的终端里跑它配置的命令。
    ///
    /// App 自己不执行任何命令——命令是送进用户配置的终端、由他的 shell 跑的。
    /// 终端跟随「打开位置」设置，与「打开终端」保持一致，免得同一个 App 里有两套位置语义。
    func runAction(_ action: CustomAction) {
        do {
            let url = try FinderPathProvider.currentDirectory()
            try launcher.run(action.command, at: url, mode: terminalMode)
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

    /// 在当前 Finder 目录按模板创建文件，并在 Finder 中选中它。
    func createFile(using template: FileTemplate) {
        do {
            let directory = try FinderPathProvider.currentDirectory()
            guard let url = try FileCreator.promptAndCreate(template: template, in: directory) else {
                return   // 用户取消，不是错误
            }
            recordLastUsedExt(of: url)
            // 输入弹窗已经关掉了再激活 Finder，否则两边的激活会话会互相打架。
            FileCreator.reveal(url, in: directory)
        } catch {
            presentError(error)
        }
    }

    /// 全局热键：**不问名字**，直接用「上次用过的类型」建一个文件并在 Finder 中选中。
    ///
    /// 与菜单路径的唯一区别就是「不问名字」——文件名用「未命名.<扩展名>」、重名自动加序号，
    /// 建完在 Finder 里选中，用户可以就地改名（同 Finder 自己的 ⌘⇧N 新建文件夹）。
    func createFileQuickly() {
        do {
            let directory = try FinderPathProvider.currentDirectory()
            guard let template = FileTemplateStore.quickCreateTemplate(
                from: UserDefaults.standard.string(forKey: FileTemplateStore.defaultsKey) ?? "",
                lastUsedExt: UserDefaults.standard.string(forKey: FileTemplateStore.lastUsedExtKey) ?? ""
            ) else {
                // 不能静默失败：热键没有任何可见反馈，不提示的话用户只会以为热键坏了。
                presentMessage("还没有启用的文件类型。请先在「设置 → 创建文件」里添加一个类型并勾选它。")
                return
            }

            let url = try FileCreator.createUntitled(template: template, in: directory)
            recordLastUsedExt(of: url)
            FileCreator.reveal(url, in: directory)
        } catch {
            presentError(error)
        }
    }

    /// 记住这次实际建出来的扩展名，供下次热键直建复用。
    ///
    /// 记的是**文件实际的**扩展名而不是模板的：用户在命名弹窗里可以显式写别的扩展名
    /// （如选 Markdown 却输入「报告.txt」），那次才代表他真正想要什么。
    private func recordLastUsedExt(of url: URL) {
        let ext = FileTemplateStore.normalizeExtension(url.pathExtension)
        guard !ext.isEmpty else { return }
        UserDefaults.standard.set(ext, forKey: FileTemplateStore.lastUsedExtKey)
    }

    /// 用指定编辑器打开当前 Finder 目录。
    func openInEditor(_ entry: EditorEntry) {
        do {
            let opener = try EditorOpenerFactory.resolve(entry)
            let url = try FinderPathProvider.currentDirectory()
            opener.openEditor(at: url)
        } catch {
            presentError(error)
        }
    }

    /// 全局热键：用编辑器列表里**第一个**启用的打开当前 Finder 目录。
    ///
    /// 与菜单路径的唯一区别是「没配编辑器时必须出声」：热键没有任何可见入口，
    /// 静默 return 的话用户只会以为热键坏了、而不是以为该去配置
    /// （同 createFileQuickly 里 no-template 那条分支的处理）。
    func openInEditorFirst() {
        guard let first = Self.enabledEditors().first else {
            presentMessage("还没有启用任何编辑器。请先在「设置 → 编辑器」里添加一个。")
            return
        }
        openInEditor(first)
    }

    /// 当前启用的编辑器列表。
    ///
    /// 热键路径没有菜单那样的 SwiftUI 观察环境，只能静态读 UserDefaults；
    /// 好在热键每次触发都读一次，拿到的就是最新配置。
    static func enabledEditors() -> [EditorEntry] {
        EditorStore.menuEditors(
            from: UserDefaults.standard.string(forKey: EditorStore.defaultsKey) ?? "",
            legacyKind: UserDefaults.standard.integer(forKey: EditorStore.legacyKindKey),
            legacyPath: UserDefaults.standard.string(forKey: EditorStore.legacyPathKey) ?? "")
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

        // 授权类错误多给一个直达系统设置的按钮——只有那里能真正解决问题，
        // 光说「没有权限」用户不知道该去哪儿改。
        if let settingsURL = Self.privacySettingsURL(for: error) {
            alert.addButton(withTitle: "打开授权设置")
            alert.addButton(withTitle: "取消")
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(settingsURL)
            }
        } else {
            alert.addButton(withTitle: "好")
            alert.runModal()
        }
    }

    /// 授权类错误对应系统设置里的哪个面板；不是授权问题则返回 nil。
    ///
    /// 非 private 是为了能单测：漏掉一个分支的后果是用户只看到「没有授权」却拿不到
    /// 直达设置的按钮——而这正是「点了没反应」最需要被修好的地方。
    static func privacySettingsURL(for error: Error) -> URL? {
        let pane: String
        if case FinderPathError.tccDenied = error {
            pane = "Privacy_Automation"          // 控制 Finder：读当前目录
        } else if case OSAScriptError.tccDenied = error {
            pane = "Privacy_Automation"          // 控制 Finder / 终端：自动化授权被拒
        } else if case FileCreationError.noPermission = error {
            pane = "Privacy_FilesAndFolders"     // 写桌面 / 文稿 / 下载
        } else {
            return nil
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")
    }
}

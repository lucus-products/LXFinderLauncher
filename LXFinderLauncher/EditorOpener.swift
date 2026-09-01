//
//  EditorOpener.swift
//  LXFinderLauncher
//
//  Created by 启业云03 on 2026/9/1.
//

import AppKit

/// 编辑器启动器协议：在 Finder 当前目录用编辑器打开。
protocol EditorOpener {
    func openEditor(at directory: URL)
}

// MARK: - 具体编辑器

/// Cursor：bundle id `com.todesktop.230313mzl4w4u92`。
struct CursorEditorOpener: EditorOpener {
    func openEditor(at directory: URL) {
        if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.todesktop.230313mzl4w4u92") {
            openWith(app, at: directory)
            return
        }
        // bundle id 兜底：直接按路径找。
        let fallback = URL(fileURLWithPath: "/Applications/Cursor.app")
        if FileManager.default.fileExists(atPath: fallback.path) {
            openWith(fallback, at: directory)
        } else {
            print("[LXFinderLauncher] 未检测到 Cursor")
        }
    }
}

/// Visual Studio Code：bundle id `com.microsoft.VSCode`。
struct VSCodeEditorOpener: EditorOpener {
    func openEditor(at directory: URL) {
        if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.microsoft.VSCode") {
            openWith(app, at: directory)
            return
        }
        let fallback = URL(fileURLWithPath: "/Applications/Visual Studio Code.app")
        if FileManager.default.fileExists(atPath: fallback.path) {
            openWith(fallback, at: directory)
        } else {
            print("[LXFinderLauncher] 未检测到 Visual Studio Code")
        }
    }
}

/// 自定义编辑器：按用户填写的路径打开。
struct CustomEditorOpener: EditorOpener {
    let appURL: URL

    func openEditor(at directory: URL) {
        if FileManager.default.fileExists(atPath: appURL.path) {
            openWith(appURL, at: directory)
        } else {
            print("[LXFinderLauncher] 自定义编辑器路径不存在：\(appURL.path)")
        }
    }
}

private func openWith(_ app: URL, at directory: URL) {
    let config = NSWorkspace.OpenConfiguration()
    config.activates = true
    NSWorkspace.shared.open([directory], withApplicationAt: app,
                            configuration: config) { _, error in
        if let error { print("[LXFinderLauncher] 打开编辑器失败：\(error)") }
    }
}

// MARK: - 工厂

/// 编辑器工厂：按设置选择具体编辑器。
enum EditorOpenerFactory {

    /// UserDefaults 键：editorKind（0=关闭 1=Cursor 2=VSCode 3=自定义）、customEditorPath。
    static func make() -> EditorOpener? {
        switch UserDefaults.standard.integer(forKey: "editorKind") {
        case 1: return CursorEditorOpener()
        case 2: return VSCodeEditorOpener()
        case 3:
            if let path = UserDefaults.standard.string(forKey: "customEditorPath"),
               FileManager.default.fileExists(atPath: path) {
                return CustomEditorOpener(appURL: URL(fileURLWithPath: path))
            }
            return nil
        default: return nil
        }
    }

    /// 是否配置了可用的编辑器（决定菜单是否显示「用 X 打开」）。
    static func isEnabled() -> Bool {
        make() != nil
    }

    /// 当前编辑器显示名（菜单项文案）。
    static func displayName() -> String {
        switch UserDefaults.standard.integer(forKey: "editorKind") {
        case 1: return "Cursor"
        case 2: return "Visual Studio Code"
        case 3:
            if let path = UserDefaults.standard.string(forKey: "customEditorPath") {
                return (path as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "")
            }
            return "自定义编辑器"
        default: return "编辑器"
        }
    }

    /// Cursor 是否已安装。
    static func isCursorInstalled() -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.todesktop.230313mzl4w4u92") != nil
            || FileManager.default.fileExists(atPath: "/Applications/Cursor.app")
    }

    /// VSCode 是否已安装。
    static func isVSCodeInstalled() -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.microsoft.VSCode") != nil
            || FileManager.default.fileExists(atPath: "/Applications/Visual Studio Code.app")
    }
}

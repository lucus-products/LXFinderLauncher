//
//  EditorOpener.swift
//  LXFinderLauncher
//
//  Created by 启业云03 on 2026/9/1.
//

import AppKit

/// 编辑器启动器协议：在 Finder 当前目录用编辑器打开。
///
/// 目前只有「按 App 打开」一种形态，所以只有一个实现；留协议是为了将来能接
/// 不走 .app 的编辑器（比如通过命令行工具打开）。
protocol EditorOpener {
    func openEditor(at directory: URL)
}

// MARK: - 错误

/// 打开编辑器时的错误。
enum EditorOpenError: LocalizedError {
    /// 配置里指的编辑器 App 找不到。
    case appNotFound(String)

    var errorDescription: String? {
        switch self {
        case .appNotFound(let name):
            return "找不到「\(name)」。请确认它还在原来的位置，或到「设置 → 编辑器」里改一下配置。"
        }
    }
}

// MARK: - 实现

/// 按 App 路径打开目录。
///
/// 三种编辑器（Cursor / VSCode / 自定义）的差别**只在于怎么解析出 App 的路径**，
/// 解析之后的动作完全一样，所以不必各写一个类型——解析统一放在
/// `EditorOpenerFactory.resolve(_:)`，这里只负责打开。
struct AppBundleEditorOpener: EditorOpener {

    let appURL: URL

    func openEditor(at directory: URL) {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        // 走 Launch Services，不通过 Apple Events 控制目标应用，避免额外授权。
        NSWorkspace.shared.open([directory], withApplicationAt: appURL,
                                configuration: config) { _, error in
            if let error { print("[LXFinderLauncher] 打开编辑器失败：\(error)") }
        }
    }
}

// MARK: - 工厂

/// 编辑器工厂：把一条 `EditorEntry` 解析成可用的编辑器。
enum EditorOpenerFactory {

    /// 把一条配置解析成编辑器。App 找不到时抛错，而不是静默失败。
    ///
    /// 菜单项是照着用户配置渲染的，配置里的路径失效就必须说出来：静默返回会让用户
    /// 以为「点了没反应」是 App 坏了，而不是自己的配置需要更新。
    static func resolve(_ entry: EditorEntry) throws -> any EditorOpener {
        guard let app = resolveAppURL(for: entry) else {
            throw EditorOpenError.appNotFound(entry.name)
        }
        return AppBundleEditorOpener(appURL: app)
    }

    /// 解析一条配置指向的 App。
    ///
    /// 内置编辑器优先按 bundle id 找（能正确处理 App 不在 `/Applications` 的情况），
    /// 找不到再退回默认安装路径；自定义编辑器直接用用户填的路径。
    private static func resolveAppURL(for entry: EditorEntry) -> URL? {
        if let bundleID = entry.kind.bundleID,
           let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return app
        }

        let path = entry.kind == .custom ? entry.path : (entry.kind.fallbackPath ?? "")
        guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }

    /// 某种内置编辑器是否已安装（供设置页决定要不要提供这个选项）。
    ///
    /// 只在视图初始化时求值一次，不随文件系统变化刷新——与改造前的行为一致。
    static func isInstalled(_ kind: EditorKind) -> Bool {
        guard let bundleID = kind.bundleID,
              let fallbackPath = kind.fallbackPath
        else { return false }

        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
            || FileManager.default.fileExists(atPath: fallbackPath)
    }

    /// Cursor 是否已安装。
    static func isCursorInstalled() -> Bool { isInstalled(.cursor) }

    /// VSCode 是否已安装。
    static func isVSCodeInstalled() -> Bool { isInstalled(.vscode) }
}

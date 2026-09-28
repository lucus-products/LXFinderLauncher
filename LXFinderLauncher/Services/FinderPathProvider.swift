//
//  FinderPathProvider.swift
//  LXFinderLauncher
//
//  Created by 启业云03 on 2026/9/1.
//

import AppKit
import OSLog

private let logger = Logger(subsystem: "com.linx.LXFinderLauncher", category: "FinderPath")

/// 获取 Finder 目录时的错误。
enum FinderPathError: LocalizedError {
    /// 用户拒绝了「控制 Finder」的自动化授权（-1743）。
    case tccDenied
    /// Apple Event 超时 / Finder 忙（-609 / -608）。
    case finderBusy
    /// 其它错误。
    case unknown(Int)

    var errorDescription: String? {
        switch self {
        case .tccDenied:
            return "没有读取 Finder 目录的权限。请在「系统设置 → 隐私与安全性 → 自动化」中允许本 App 控制 Finder，然后重试。"
        case .finderBusy:
            return "Finder 没有响应，请稍后重试。"
        case .unknown(let code):
            return "获取 Finder 目录失败（错误码 \(code)）。"
        }
    }
}

/// 读取当前 Finder 窗口的目标目录；无窗口或 Finder 未运行时回退到桌面。
enum FinderPathProvider {

    /// 取 Finder 前窗目录；front window 取不到时枚举所有窗口兜底；
    /// 全失败才回退桌面。TCC 授权拒绝（-1743）会抛出，不吞掉。
    private static let script = """
    tell application "Finder"
        try
            return POSIX path of (target of front window as alias)
        on error errMsg number errNum
            if errNum is -1743 then error errMsg number errNum
            try
                repeat with w in windows
                    try
                        return POSIX path of (target of w as alias)
                    on error
                    end try
                end repeat
            end try
            return POSIX path of (path to desktop folder)
        end try
    end tell
    """

    /// 当前 Finder 前窗目录；无窗口 / Finder 未运行 → 桌面。
    static func currentDirectory() throws -> URL {
        // Finder 未运行时直接返回桌面，避免脚本自动拉起 Finder。
        guard isFinderRunning else {
            let desktop = desktopURL()
            logger.warning("Finder 未运行，回退桌面：\(desktop.path, privacy: .public)")
            return desktop
        }

        let path: String
        do {
            path = try OSAScriptRunner.run(Self.script)
        } catch let error as OSAScriptError {
            switch error {
            case .tccDenied: throw FinderPathError.tccDenied
            case .timeoutOrBusy: throw FinderPathError.finderBusy
            case .unknown(let code, let message):
                logger.error("osascript 错误 \(code)：\(message, privacy: .public)")
                throw FinderPathError.unknown(code)
            }
        } catch {
            throw FinderPathError.unknown(-1)
        }

        guard !path.isEmpty else { throw FinderPathError.unknown(-3) }
        logger.info("取到 Finder 目录：\(path, privacy: .public)")
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    private static var isFinderRunning: Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.apple.finder" }
    }

    private static func desktopURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop", isDirectory: true)
    }
}

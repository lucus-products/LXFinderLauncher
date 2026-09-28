//
//  OSAScriptRunner.swift
//  LXFinderLauncher
//
//  Created by 启业云03 on 2026/9/1.
//

import Foundation
import OSLog

private let runnerLogger = Logger(subsystem: "com.linx.LXFinderLauncher", category: "OSAScript")

/// 执行 AppleScript 时的错误。
enum OSAScriptError: LocalizedError {
    /// 用户拒绝了自动化授权（-1743）。
    case tccDenied
    /// 目标应用无响应 / 超时（-609 / -608）。
    case timeoutOrBusy
    /// 其它错误。
    case unknown(Int, String)

    var errorDescription: String? {
        switch self {
        case .tccDenied:
            return "没有自动化授权。请在「系统设置 → 隐私与安全性 → 自动化」中允许本 App 控制对应应用。"
        case .timeoutOrBusy:
            return "目标应用没有响应，请稍后重试。"
        case .unknown(let code, let message):
            return "AppleScript 执行失败（\(code)）：\(message)"
        }
    }
}

/// 通过 `osascript` 子进程同步执行 AppleScript。
///
/// 用子进程而非 NSAppleScript：LSUIElement 菜单栏 App 直接发 Apple Events 时，
/// 系统不会弹出 TCC 授权框而是静默拒绝；osascript 子进程能正常触发授权弹窗。
enum OSAScriptRunner {

    /// 同步执行脚本，返回 stdout（去首尾空白）。错误抛出 OSAScriptError。
    /// - Parameters:
    ///   - script: AppleScript 源码。若含 `on run argv`，可用 arguments 注入参数。
    ///   - arguments: 注入到 `argv` 的参数，避免把路径字符串拼进脚本导致转义问题。
    @discardableResult
    static func run(_ script: String, arguments: [String] = []) throws -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script] + arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = errPipe

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            runnerLogger.error("启动 osascript 失败：\(String(describing: error), privacy: .public)")
            throw OSAScriptError.unknown(-2, "无法启动 osascript")
        }

        let errText = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let outText = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        // 非 0 退出码：错误在 stderr，形如 "… (-1743)"。
        if task.terminationStatus != 0 {
            if errText.contains("-1743") || outText.contains("-1743") {
                throw OSAScriptError.tccDenied
            }
            if errText.contains("-609") || errText.contains("-608") {
                throw OSAScriptError.timeoutOrBusy
            }
            let message = (errText.isEmpty ? outText : errText)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            runnerLogger.error("osascript 错误：\(message, privacy: .public)")
            throw OSAScriptError.unknown(Int(task.terminationStatus), message)
        }

        return outText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

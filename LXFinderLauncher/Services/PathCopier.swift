//
//  PathCopier.swift
//  LXFinderLauncher
//
//  Created by 启业云03 on 2026/9/30.
//

import Foundation

/// 「复制路径」的几种输出格式。
///
/// 声明顺序即菜单顺序。`rawValue` 只用于 SwiftUI 的 `Identifiable`，不落盘，可以随便改。
enum PathCopyFormat: String, CaseIterable, Identifiable {

    case fullPath
    case fileName
    case cdCommand
    case markdownLink
    case fileURL

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fullPath: return "完整路径"
        case .fileName: return "文件名"
        case .cdCommand: return "cd 命令"
        case .markdownLink: return "Markdown 链接"
        case .fileURL: return "file:// URL"
        }
    }
}

/// 把目录 URL 渲染成要放进剪贴板的文本。
///
/// 单独抽成纯函数是为了能单测：转义规则（shell 引用、URL 编码）全在这里，
/// 错了用户拿到的是粘进终端跑不了、或者更糟——跑成另一条命令的文本。
enum PathCopier {

    static func text(for url: URL, format: PathCopyFormat) -> String {
        switch format {
        case .fullPath:
            return url.path
        case .fileName:
            return fileName(of: url)
        case .cdCommand:
            return "cd " + shellQuoted(url.path)
        case .markdownLink:
            return "[\(fileName(of: url))](\(url.absoluteString))"
        case .fileURL:
            return url.absoluteString
        }
    }

    /// 目录名。`lastPathComponent` 对根目录返回 `/`，不会为空；这里只是防御。
    static func fileName(of url: URL) -> String {
        let last = url.lastPathComponent
        return last.isEmpty ? url.path : last
    }

    /// shell 单引号引用。
    ///
    /// 路径里可能有空格、中文、`$`、`!`、反引号……单引号内的内容 shell 一律原样处理，
    /// 所以比双引号安全得多。唯一的例外是单引号本身：必须写成 `'\''`
    /// （结束当前引用 + 一个转义的单引号 + 重新开始引用）。
    static func shellQuoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

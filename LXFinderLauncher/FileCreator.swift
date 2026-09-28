//
//  FileCreator.swift
//  LXFinderLauncher
//
//  Created by 启业云03 on 2026/9/28.
//

import AppKit

// MARK: - 文件名

/// 把用户输入的名字整理成最终落盘的文件名。
///
/// 单独拆成一组纯函数，是为了不依赖 UI 就能单测（同 KeycodeTable 的做法）。
enum FileNameNormalizer {

    /// 用户输入 → 最终文件名。
    ///
    /// 规则：去首尾空白 → 去掉 `/` 和 `:` → 校验非法 → 按需补扩展名。
    ///
    ///   「报告」      → 报告.md
    ///   「报告.md」   → 报告.md      （不会变成 报告.md.md）
    ///   「v1.2 报告」 → v1.2 报告.md （`1.2` 里那个点不算扩展名）
    ///   「报告.txt」  → 报告.txt     （用户显式写了别的扩展名，尊重他）
    static func resolve(_ input: String, ext: String) throws -> String {
        let cleaned = input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            // `/` 会直接破坏路径；`:` 在 APFS 上其实合法，但 Finder 显示层会把 `:` 和 `/`
            // 互相转换，留着只会让用户在 Finder 里看到一个和输入不一样的名字。
            .replacingOccurrences(of: "/", with: "")
            .replacingOccurrences(of: ":", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleaned.isEmpty else { throw FileCreationError.emptyFileName }
        guard cleaned != "." && cleaned != ".." else {
            throw FileCreationError.invalidName(cleaned)
        }
        // 以点开头的按「点文件」处理（.gitignore、.env），不补扩展名——
        // 补成 .gitignore.md 只会让人莫名其妙。
        guard !cleaned.hasPrefix(".") else { return cleaned }
        guard !hasExtension(cleaned) else { return cleaned }

        let normalizedExt = FileTemplateStore.normalizeExtension(ext)
        return normalizedExt.isEmpty ? cleaned : "\(cleaned).\(normalizedExt)"
    }

    /// 判断名字末尾是否已经带了扩展名，形如 `.xxx`（1–10 位字母数字）。
    ///
    /// 限制「1–10 位字母数字」是为了不把「v1.2 报告」里那个 `1.2` 误判成扩展名。
    private static func hasExtension(_ name: String) -> Bool {
        guard let dot = name.lastIndex(of: ".") else { return false }
        let suffix = name[name.index(after: dot)...]
        return !suffix.isEmpty
            && suffix.count <= 10
            && suffix.allSatisfy { $0.isLetter || $0.isNumber }
    }
}

// MARK: - 错误

/// 创建文件时的错误。
enum FileCreationError: LocalizedError {
    /// 用户没填文件名，或填的全是会被清掉的字符。
    case emptyFileName
    /// 名字本身没法当文件名用。
    case invalidName(String)
    /// 同名文件已存在。
    case alreadyExists(String)
    /// 没有该目录的写入权限（多为「文件与文件夹」授权被拒）。
    case noPermission(URL)
    /// 其它写盘失败。
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .emptyFileName:
            return "文件名不能为空。"
        case .invalidName(let name):
            return "「\(name)」不能用作文件名。"
        case .alreadyExists(let name):
            return "「\(name)」已存在。"
        case .noPermission(let directory):
            return "没有向「\(directory.path)」写入的权限。请在「系统设置 → 隐私与安全性 → 文件与文件夹」中允许本 App 访问该位置，然后重试。"
        case .writeFailed(let message):
            return "创建文件失败：\(message)"
        }
    }
}

// MARK: - 创建

/// 在指定目录创建文件：写盘 + 输入弹窗 + 在 Finder 中显示。
enum FileCreator {

    /// 内置空白模板的资源名：bundle 里存在 `blank.<扩展名>` 就拷贝它。
    ///
    /// docx / xlsx / pptx 是 OOXML（zip 包），0 字节的空文件会被 Office 判定为损坏，
    /// 所以随包带了最小可用的空白文档（生成脚本见 scripts/make-blank-templates.sh）。
    /// 纯文本类格式空文件本身就是合法的，没有对应模板，走空文件分支。
    private static let blankTemplateName = "blank"

    // MARK: 写盘（无 UI，可单测）

    /// 在 `directory` 下创建名为 `fileName` 的文件。
    /// 已存在且 `overwrite` 为 false 时抛 `.alreadyExists`。
    static func create(named fileName: String,
                       template: FileTemplate,
                       in directory: URL,
                       overwrite: Bool = false) throws -> URL {
        let url = directory.appendingPathComponent(fileName)

        do {
            if FileManager.default.fileExists(atPath: url.path) {
                guard overwrite else { throw FileCreationError.alreadyExists(fileName) }
                try FileManager.default.removeItem(at: url)
            }

            if let blank = Bundle.main.url(forResource: blankTemplateName,
                                           withExtension: template.ext) {
                try FileManager.default.copyItem(at: blank, to: url)
            } else {
                // 用会抛错的写盘 API，而不是只返回 Bool 的 createFile(atPath:contents:)——
                // 后者在「文件与文件夹」授权被拒时拿不到失败原因，错误提示只能写成没用的「失败」。
                try Data().write(to: url, options: .withoutOverwriting)
            }
        } catch let error as FileCreationError {
            throw error   // 上面主动抛的 alreadyExists，别被下面的翻译吞掉
        } catch {
            throw translate(error, directory: directory)
        }

        return url
    }

    /// 把 Foundation 的写盘错误翻译成面向用户的错误。
    /// 权限单独成一类，因为它是唯一有明确补救动作（去系统设置里授权）的情况。
    private static func translate(_ error: Error, directory: URL) -> Error {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain,
           nsError.code == NSFileWriteNoPermissionError || nsError.code == NSFileReadNoPermissionError {
            return FileCreationError.noPermission(directory)
        }
        return FileCreationError.writeFailed(error.localizedDescription)
    }

    // MARK: 交互流程

    /// 问文件名 → 建文件 → 在 Finder 中选中。返回 nil 表示用户取消（不算错误）。
    ///
    /// 名字非法或用户不愿覆盖同名文件时回到输入框让他改，而不是直接失败——
    /// 走到这一步说明他本来就想建文件，只是名字需要调一下。
    static func promptAndCreate(template: FileTemplate, in directory: URL) throws -> URL? {
        let ext = FileTemplateStore.normalizeExtension(template.ext)

        while true {
            guard let input = askFileName(template: template, ext: ext, in: directory) else {
                return nil
            }

            let fileName: String
            do {
                fileName = try FileNameNormalizer.resolve(input, ext: ext)
            } catch {
                presentNamingError(error)
                continue
            }

            do {
                return try create(named: fileName, template: template, in: directory)
            } catch FileCreationError.alreadyExists {
                switch askOverwrite(fileName: fileName) {
                case .overwrite:
                    return try create(named: fileName, template: template,
                                      in: directory, overwrite: true)
                case .rename:
                    continue
                case .cancel:
                    return nil
                }
            }
        }
    }

    /// 在 Finder 里选中刚创建的文件。
    ///
    /// 走 Launch Services，**不需要**「控制 Finder」的自动化授权——
    /// 和 FinderPathProvider 那条 osascript 路线是两回事。Finder 没在运行时会被自动拉起。
    static func reveal(_ url: URL, in directory: URL) {
        // 没有任何 Finder 窗口时，activateFileViewerSelecting 可能只把 Finder 唤到前台却不给窗口；
        // 先在已知目录上开窗选中，失败才退回前者。
        if !NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: directory.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    // MARK: 弹窗

    /// 收集文件名的输入框。返回 nil 表示用户取消。
    ///
    /// 每个 NSAlert 前都要先激活本 App：LSUIElement 菜单栏 App 不激活的话弹窗会落在
    /// 其它窗口后面（同 AppCommands.presentError 里记录的那个坑）。
    private static func askFileName(template: FileTemplate,
                                    ext: String,
                                    in directory: URL) -> String? {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "新建\(template.name)"
        alert.informativeText = ext.isEmpty
            ? "创建在「\(directory.lastPathComponent)」"
            : "创建在「\(directory.lastPathComponent)」，可以不写扩展名，会自动补 .\(ext)"
        alert.addButton(withTitle: "创建")   // 第一个按钮即默认按钮，输入框里按回车直接触发
        alert.addButton(withTitle: "取消")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = availableDefaultName(ext: ext, in: directory)
        alert.accessoryView = field
        // 必须在 runModal 之前设，输入框才会一上来就有键盘焦点（这行也会提前创建 alert.window）。
        alert.window.initialFirstResponder = field
        // 全选要等输入框真正成为 first responder 之后才生效，所以丢到下一个 runloop 周期。
        DispatchQueue.main.async { field.selectText(nil) }

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return field.stringValue
    }

    /// 从「未命名.<ext>」开始找一个当前目录还没被占用的名字：
    /// 未命名.md → 未命名 2.md → 未命名 3.md …
    ///
    /// 预填一个可用名字，避免用户一按回车就先撞上覆盖确认。
    private static func availableDefaultName(ext: String, in directory: URL) -> String {
        let base = "未命名"
        let suffix = ext.isEmpty ? "" : ".\(ext)"
        var candidate = "\(base)\(suffix)"
        var n = 2
        while FileManager.default.fileExists(atPath: directory.appendingPathComponent(candidate).path) {
            candidate = "\(base) \(n)\(suffix)"
            n += 1
        }
        return candidate
    }

    /// 同名文件时用户的处理选择。
    private enum OverwriteChoice {
        case overwrite, rename, cancel
    }

    private static func askOverwrite(fileName: String) -> OverwriteChoice {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "「\(fileName)」已存在"
        alert.informativeText = "覆盖会清空原文件的内容，且不可撤销。"
        alert.addButton(withTitle: "覆盖")
        alert.addButton(withTitle: "重新命名")
        alert.addButton(withTitle: "取消")

        switch alert.runModal() {
        case .alertFirstButtonReturn: return .overwrite
        case .alertSecondButtonReturn: return .rename
        default: return .cancel
        }
    }

    /// 文件名不合法时就地提示，让用户改一个再来，而不是让整个动作失败。
    private static func presentNamingError(_ error: Error) {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "LXFinderLauncher"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}

//
//  LXFinderLauncherTests.swift
//  LXFinderLauncherTests
//
//  Created by 启业云03 on 2026/9/1.
//

import Testing
import Foundation
import Carbon.HIToolbox
@testable import LXFinderLauncher

struct LXFinderLauncherTests {

    @Test func keyNameForLetter() {
        #expect(KeycodeTable.keyName(for: UInt32(kVK_ANSI_A)) == "A")
        #expect(KeycodeTable.keyName(for: UInt32(kVK_ANSI_T)) == "T")
    }

    @Test func keyNameForDigitAndFunction() {
        #expect(KeycodeTable.keyName(for: UInt32(kVK_ANSI_1)) == "1")
        #expect(KeycodeTable.keyName(for: UInt32(kVK_F5)) == "F5")
    }

    @Test func modifierString() {
        #expect(KeycodeTable.modifierString(carbon: UInt32(cmdKey | shiftKey)) == "⇧⌘")
        #expect(KeycodeTable.modifierString(carbon: UInt32(optionKey | controlKey)) == "⌃⌥")
        #expect(KeycodeTable.modifierString(carbon: 0) == "")
    }

    @Test func displayString() {
        #expect(KeycodeTable.displayString(keyCode: UInt32(kVK_ANSI_T),
                                           modifiers: UInt32(cmdKey | shiftKey)) == "⇧⌘T")
    }
}

// MARK: - 版本比较

struct UpdateCheckerTests {

    @Test func newer() {
        #expect(UpdateChecker.isNewer("1.1.0", than: "1.0.0"))
        #expect(UpdateChecker.isNewer("1.10.0", than: "1.9.9"))
        #expect(UpdateChecker.isNewer("2.0", than: "1.99.9"))
        #expect(UpdateChecker.isNewer("v1.2.0", than: "1.1.5"))
    }

    @Test func notNewer() {
        #expect(!UpdateChecker.isNewer("1.0.0", than: "1.1.0"))
        #expect(!UpdateChecker.isNewer("1.0.0", than: "1.0.0"))
        #expect(!UpdateChecker.isNewer("0.9", than: "1.0"))
    }
}

// MARK: - 创建文件：类型列表

struct FileTemplateStoreTests {

    @Test func emptyJSONFallsBackToDefaults() {
        // 首次运行时 @AppStorage 读到的是默认值 ""，要拿到内置列表。
        let templates = FileTemplateStore.templates(from: "")
        #expect(templates.count == 8)
        #expect(templates.map(\.ext) == ["md", "txt", "docx", "xlsx", "pptx", "json", "yml", "html"])
    }

    @Test func defaultTemplateIDsAreStableAndUnique() {
        // id 必须跨进程稳定（否则 SwiftUI 列表身份抖动），且不能重复。
        let first = FileTemplateStore.defaultTemplates.map(\.id)
        let second = FileTemplateStore.defaultTemplates.map(\.id)
        #expect(first == second)
        #expect(Set(first).count == first.count)
    }

    @Test func roundTripPreservesOrder() {
        let list = [
            FileTemplate(name: "乙", ext: "yyy"),
            FileTemplate(name: "甲", ext: "xxx"),
        ]
        #expect(FileTemplateStore.templates(from: FileTemplateStore.encode(list)) == list)
    }

    @Test func emptyArrayStaysEmpty() {
        // 用户主动把类型删光，不能拿默认列表盖回去。
        #expect(FileTemplateStore.templates(from: "[]").isEmpty)
    }

    @Test func brokenJSONFallsBackToDefaults() {
        #expect(FileTemplateStore.templates(from: "{不是合法 JSON").count == 8)
    }

    @Test func decodesEntryMissingFields() {
        // 用户手改 UserDefaults、或将来给 FileTemplate 加字段时，
        // 单条缺字段不该让整份配置解析失败（那会静默丢掉用户配好的整个列表）。
        let json = #"[{"name":"TOML","ext":"toml"}]"#
        let templates = FileTemplateStore.templates(from: json)
        #expect(templates.count == 1)
        #expect(templates.first?.name == "TOML")
        #expect(templates.first?.enabled == true)   // enabled 缺失时默认启用
    }

    @Test func normalizeCleansNameAndExtension() {
        let clean = FileTemplateStore.normalize(FileTemplate(name: "  Markdown  ", ext: ".MD"))
        #expect(clean.name == "Markdown")
        #expect(clean.ext == "md")
    }

    @Test func menuTemplatesSkipDisabledAndEmptyExtension() {
        let list = [
            FileTemplate(name: "开", ext: "on"),
            FileTemplate(name: "关", ext: "off", enabled: false),
            FileTemplate(name: "草稿", ext: ""),          // 扩展名还没填的新增项
        ]
        let menu = FileTemplateStore.menuTemplates(from: FileTemplateStore.encode(list))
        #expect(menu.map(\.ext) == ["on"])
    }
}

// MARK: - 创建文件：文件名归一化

struct FileNameNormalizerTests {

    @Test func appendsMissingExtension() throws {
        #expect(try FileNameNormalizer.resolve("报告", ext: "md") == "报告.md")
    }

    @Test func doesNotDuplicateExtension() throws {
        #expect(try FileNameNormalizer.resolve("报告.md", ext: "md") == "报告.md")
    }

    @Test func keepsUserChosenExtension() throws {
        // 选了 Markdown 却显式写了 .txt，尊重用户的输入。
        #expect(try FileNameNormalizer.resolve("报告.txt", ext: "md") == "报告.txt")
    }

    @Test func dotInsideNameIsNotAnExtension() throws {
        // 「v1.2 报告」里那个点后面不是 1–10 位字母数字，不算扩展名。
        #expect(try FileNameNormalizer.resolve("v1.2 报告", ext: "md") == "v1.2 报告.md")
    }

    @Test func stripsPathSeparators() throws {
        #expect(try FileNameNormalizer.resolve("a/b:c", ext: "md") == "abc.md")
    }

    @Test func dotFileLeftAlone() throws {
        // 点文件不补扩展名，否则 .gitignore 会变成 .gitignore.md。
        #expect(try FileNameNormalizer.resolve(".gitignore", ext: "md") == ".gitignore")
    }

    @Test func normalizesExtensionCase() throws {
        #expect(try FileNameNormalizer.resolve("笔记", ext: ".MD") == "笔记.md")
    }

    @Test func trimsSurroundingWhitespace() throws {
        #expect(try FileNameNormalizer.resolve("  笔记  ", ext: "md") == "笔记.md")
    }

    @Test func rejectsEmptyName() {
        #expect(throws: FileCreationError.self) { try FileNameNormalizer.resolve("   ", ext: "md") }
        // 「///」被清掉后什么都不剩，同样算空名。
        #expect(throws: FileCreationError.self) { try FileNameNormalizer.resolve("///", ext: "md") }
    }

    @Test func rejectsDotAndDotDot() {
        #expect(throws: FileCreationError.self) { try FileNameNormalizer.resolve(".", ext: "md") }
        #expect(throws: FileCreationError.self) { try FileNameNormalizer.resolve("..", ext: "md") }
    }
}

// MARK: - 创建文件：写盘

struct FileCreatorTests {

    /// 每个用例一个独立临时目录，互不干扰。
    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("LXFinderLauncherTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func writesEmptyFileForPlainTextFormat() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = try FileCreator.create(named: "笔记.md",
                                         template: FileTemplate(name: "Markdown", ext: "md"),
                                         in: dir)

        #expect(url.lastPathComponent == "笔记.md")
        #expect(FileManager.default.fileExists(atPath: url.path))
        // 纯文本类没有内置模板，落一个 0 字节空文件。
        #expect(try Data(contentsOf: url).isEmpty)
    }

    @Test func copiesBundledBlankTemplateForOfficeFormat() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = try FileCreator.create(named: "文档.docx",
                                         template: FileTemplate(name: "Word 文档", ext: "docx"),
                                         in: dir)

        // docx 是 OOXML（zip 包），必须来自随包的空白模板而不是 0 字节空文件——
        // 空文件会被 Word 判为损坏。这里只校验是合法 zip；模板本身能不能被
        // Office 打开由 scripts/make-blank-templates.sh 的产出保证。
        let data = try Data(contentsOf: url)
        #expect(!data.isEmpty)
        #expect(data.starts(with: [0x50, 0x4B] as [UInt8]))   // "PK"：zip 魔数
    }

    @Test func refusesToOverwriteByDefault() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let template = FileTemplate(name: "Markdown", ext: "md")
        _ = try FileCreator.create(named: "笔记.md", template: template, in: dir)

        #expect(throws: FileCreationError.self) {
            try FileCreator.create(named: "笔记.md", template: template, in: dir)
        }
    }

    @Test func overwriteReplacesExistingContent() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("笔记.md")
        try Data("旧内容".utf8).write(to: url)

        _ = try FileCreator.create(named: "笔记.md",
                                   template: FileTemplate(name: "Markdown", ext: "md"),
                                   in: dir, overwrite: true)

        // 覆盖是「先删再建」，旧内容必须没了——不然就成了静默保留旧文件。
        #expect(try Data(contentsOf: url).isEmpty)
    }

    @Test func createsUntitledFile() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = try FileCreator.createUntitled(
            template: FileTemplate(name: "Markdown", ext: "md"), in: dir)

        #expect(url.lastPathComponent == "未命名.md")
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test func createUntitledNeverOverwritesExistingFile() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let template = FileTemplate(name: "Markdown", ext: "md")
        let first = try FileCreator.createUntitled(template: template, in: dir)
        try Data("别动我".utf8).write(to: first)

        let second = try FileCreator.createUntitled(template: template, in: dir)

        #expect(second.lastPathComponent == "未命名 2.md")
        // 关键：无弹窗直建没有任何确认机会，绝不能覆盖已有文件。
        #expect(try Data(contentsOf: first) == Data("别动我".utf8))
    }

    @Test func createUntitledNormalizesExtension() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = try FileCreator.createUntitled(
            template: FileTemplate(name: "X", ext: ".MD"), in: dir)

        #expect(url.lastPathComponent == "未命名.md")
    }
}

// MARK: - 全局热键

struct GlobalHotkeyTests {

    @Test func keyPrefixesAreDistinct() {
        // 前缀撞车会让两个热键共用同一套 UserDefaults 键，改一个等于改另一个。
        let prefixes = GlobalHotkey.allCases.map(\.keyPrefix)
        #expect(Set(prefixes).count == prefixes.count)
    }

    @Test func defaultCombosAreDistinct() {
        // 出厂默认值若撞车，开箱就会有一个热键注册失败。
        let combos = GlobalHotkey.allCases.map {
            KeyCombo(keyCode: $0.defaultKeyCode, modifiers: $0.defaultModifiers)
        }
        #expect(Set(combos).count == combos.count)
    }

    @Test func createFileDefaultDoesNotStealFinderNewSmartFolder() {
        // ⌥⌘N 是 Finder 的「新建智能文件夹」，而 Finder 正是这个功能唯一的使用场景：
        // 要么让用户用不了 Finder 的新建智能文件夹，要么恰好在 Finder 前台时热键不触发。
        // 所以默认值必须比它多一个 ⌃。
        let createFile = GlobalHotkey.createFile
        #expect(createFile.defaultModifiers & cmdKey != 0)
        #expect(createFile.defaultModifiers & controlKey != 0)
        #expect(createFile.defaultModifiers & optionKey != 0)
    }

    @Test func openTerminalKeepsLegacyKeyPrefix() {
        // 老用户已经录好的组合键存在 "hotkey*" 这套键里，前缀改了等于配置丢失。
        #expect(GlobalHotkey.openTerminal.keyPrefix == "hotkey")
    }

    @Test func optionOnlyDetection() {
        #expect(GlobalHotkey.isOptionOnly(modifiers: optionKey))
        #expect(GlobalHotkey.isOptionOnly(modifiers: optionKey | shiftKey))
        // 只含 ⇧ 不算「只含 ⌥」——那条失效报告针对的是 ⌥。
        #expect(!GlobalHotkey.isOptionOnly(modifiers: shiftKey))
        #expect(!GlobalHotkey.isOptionOnly(modifiers: optionKey | cmdKey))
        // 用户当前用的 ⌥Space 正落在这个可疑区间里。
        #expect(GlobalHotkey.isOptionOnly(modifiers: optionKey | 0))
    }
}

// MARK: - 热键直建选哪个类型

struct QuickCreateTemplateTests {

    /// 一份「Markdown 可用 / Excel 被禁用 / JSON 可用 / 草稿未填扩展名」的列表。
    private let json = FileTemplateStore.encode([
        FileTemplate(name: "Markdown", ext: "md"),
        FileTemplate(name: "Excel", ext: "xlsx", enabled: false),
        FileTemplate(name: "JSON", ext: "json"),
        FileTemplate(name: "草稿", ext: ""),
    ])

    @Test func prefersLastUsedExtension() {
        #expect(FileTemplateStore.quickCreateTemplate(from: json, lastUsedExt: "json")?.ext == "json")
    }

    @Test func normalizesLastUsedExtension() {
        #expect(FileTemplateStore.quickCreateTemplate(from: json, lastUsedExt: " .JSON ")?.ext == "json")
    }

    @Test func fallsBackToFirstEnabled() {
        // 从没记录过、或上次用的类型已被删掉 → 回退菜单里的第一个可用项。
        #expect(FileTemplateStore.quickCreateTemplate(from: json, lastUsedExt: "toml")?.ext == "md")
        #expect(FileTemplateStore.quickCreateTemplate(from: json, lastUsedExt: "")?.ext == "md")
    }

    @Test func skipsDisabledAndEmptyExtension() {
        // 被禁用的 xlsx 与没填扩展名的草稿都不该被选中。
        #expect(FileTemplateStore.quickCreateTemplate(from: json, lastUsedExt: "xlsx")?.ext == "md")
    }

    @Test func returnsNilWhenNothingAvailable() {
        let allDisabled = FileTemplateStore.encode([FileTemplate(name: "X", ext: "x", enabled: false)])
        #expect(FileTemplateStore.quickCreateTemplate(from: allDisabled, lastUsedExt: "x") == nil)
        #expect(FileTemplateStore.quickCreateTemplate(from: "[]", lastUsedExt: "") == nil)
    }
}

// MARK: - 编辑器列表

struct EditorStoreTests {

    @Test func emptyJSONWithLegacyOffIsEmpty() {
        // 旧配置的「关闭」是 kind 0，不是某个种类——派生结果就该是空列表。
        #expect(EditorStore.editors(from: "", legacyKind: 0, legacyPath: "").isEmpty)
    }

    @Test func derivesSingleEditorFromLegacyKind() {
        let cursor = EditorStore.editors(from: "", legacyKind: 1, legacyPath: "")
        #expect(cursor.count == 1)
        #expect(cursor.first?.kind == .cursor)
        #expect(cursor.first?.name == "Cursor")

        let vscode = EditorStore.editors(from: "", legacyKind: 2, legacyPath: "")
        #expect(vscode.first?.kind == .vscode)
        #expect(vscode.first?.name == "Visual Studio Code")
    }

    @Test func derivesCustomEditorNameFromPath() {
        let list = EditorStore.editors(from: "", legacyKind: 3,
                                       legacyPath: "/Applications/Nova.app")
        #expect(list.count == 1)
        #expect(list.first?.kind == .custom)
        #expect(list.first?.path == "/Applications/Nova.app")
        // 显示名取路径末段并去掉 .app 后缀。
        #expect(list.first?.name == "Nova")
    }

    @Test func customWithoutPathIsNotDerived() {
        // 旧配置选了「自定义」却把路径留空，等于没配。
        #expect(EditorStore.editors(from: "", legacyKind: 3, legacyPath: "   ").isEmpty)
    }

    @Test func derivedIDsAreStable() {
        // 派生结果会被反复解码做 ForEach 身份比对；id 每次现生成会让列表身份抖动、绑定串行。
        let first = EditorStore.editors(from: "", legacyKind: 1, legacyPath: "").map(\.id)
        let second = EditorStore.editors(from: "", legacyKind: 1, legacyPath: "").map(\.id)
        #expect(first == second)
    }

    @Test func explicitEmptyListWinsOverLegacy() {
        // 键一旦被写过（哪怕是 `[]`）就再也不看旧键——否则用户把编辑器全删掉之后，
        // 旧配置里的 Cursor 会被一次次捞回来。
        #expect(EditorStore.editors(from: "[]", legacyKind: 1, legacyPath: "").isEmpty)
    }

    @Test func explicitListWinsOverLegacy() {
        let list = [EditorEntry(kind: .custom, name: "Nova", path: "/Applications/Nova.app")]
        let json = EditorStore.encode(list)
        #expect(EditorStore.editors(from: json, legacyKind: 1, legacyPath: "") == list)
    }

    @Test func roundTripPreservesOrder() {
        let list = [
            EditorEntry(kind: .vscode, name: "乙"),
            EditorEntry(kind: .cursor, name: "甲"),
        ]
        #expect(EditorStore.editors(from: EditorStore.encode(list),
                                    legacyKind: 1, legacyPath: "") == list)
    }

    @Test func menuEditorsKeepsOnlyEnabled() {
        let json = EditorStore.encode([
            EditorEntry(kind: .cursor, name: "Cursor"),
            EditorEntry(kind: .vscode, name: "VSCode", enabled: false),
        ])
        #expect(EditorStore.menuEditors(from: json, legacyKind: 0, legacyPath: "").map(\.name)
                == ["Cursor"])
    }

    @Test func menuEditorsSkipsCustomWithoutPath() {
        // 「添加编辑器 → 自定义…」会先插一条路径为空的草稿。它不该进菜单——
        // 进去就变成一个点了必然报「找不到」的菜单项。
        let json = EditorStore.encode([
            EditorEntry(kind: .cursor, name: "Cursor"),
            EditorEntry(kind: .custom, name: "自定义编辑器", path: ""),
            EditorEntry(kind: .custom, name: "只有空白", path: "   "),
            EditorEntry(kind: .custom, name: "填好了", path: "/Applications/Nova.app"),
        ])
        let menu = EditorStore.menuEditors(from: json, legacyKind: 0, legacyPath: "")
        #expect(menu.map(\.name) == ["Cursor", "填好了"])
    }

    @Test func builtInEditorsNeedNoPathToBeConfigured() {
        // 内置编辑器的路径是运行时按 bundle id 解析的，不该因为 path 为空就被当成草稿。
        #expect(EditorStore.isConfigured(EditorEntry(kind: .cursor, name: "Cursor", path: "")))
        #expect(EditorStore.isConfigured(EditorEntry(kind: .vscode, name: "VSCode", path: "")))
        // 自定义则必须有路径。
        #expect(!EditorStore.isConfigured(EditorEntry(kind: .custom, name: "x", path: "")))
    }

    @Test func decodesEntryWithMissingFields() {
        // 手改 UserDefaults、或以后给 EditorEntry 加字段时，单条残缺不该让整份配置解码失败。
        let list = EditorStore.editors(from: #"[{"kind": 1}]"#, legacyKind: 0, legacyPath: "")
        #expect(list.count == 1)
        #expect(list.first?.kind == .cursor)
        #expect(list.first?.name == "")
    }
}

// MARK: - 自定义动作

struct CustomActionStoreTests {

    @Test func emptyJSONIsEmptyList() {
        // 刻意不预置任何示例：这个列表里每一条都会被真的拿去执行，
        // 默认塞一条等于替用户决定在他自己目录里跑什么。
        #expect(CustomActionStore.actions(from: "").isEmpty)
        #expect(CustomActionStore.defaultActions.isEmpty)
    }

    @Test func roundTripPreservesOrder() {
        let list = [
            CustomAction(name: "乙", command: "echo 2"),
            CustomAction(name: "甲", command: "echo 1"),
        ]
        #expect(CustomActionStore.actions(from: CustomActionStore.encode(list)) == list)
    }

    @Test func menuActionsSkipsDisabledAndDrafts() {
        let json = CustomActionStore.encode([
            CustomAction(name: "可用", command: "echo ok"),
            CustomAction(name: "关掉的", command: "echo off", enabled: false),
            CustomAction(name: "", command: "echo 没名字"),
            CustomAction(name: "没命令", command: ""),
            CustomAction(name: "只有空白", command: "   "),
        ])
        #expect(CustomActionStore.menuActions(from: json).map(\.name) == ["可用"])
    }

    @Test func menuActionsSkipsOverlongCommand() {
        // 超长命令可能在终端那边被截断成另一条命令，宁可不显示。
        let long = String(repeating: "a", count: CustomActionStore.maxCommandLength + 1)
        let json = CustomActionStore.encode([CustomAction(name: "太长", command: long)])
        #expect(CustomActionStore.menuActions(from: json).isEmpty)
    }

    @Test func normalizeTrimsName() {
        #expect(CustomActionStore.normalize(CustomAction(name: "  部署  ", command: "x")).name == "部署")
    }

    @Test func normalizeFlattensNewlines() {
        // 换行会在终端里变成多次回车，等于把一条命令拆成几条依次执行，语义完全变了。
        let normalized = CustomActionStore.normalize(
            CustomAction(name: "部署", command: "git pull\nnpm run build"))
        #expect(!normalized.command.contains("\n"))
        #expect(normalized.command.contains("git pull"))
        #expect(normalized.command.contains("npm run build"))
    }

    @Test func normalizePreservesInnerShellSyntax() {
        // 命令中间的引号、管道、$、反斜杠一个字符都不能动——任何「清洗」都是在破坏命令。
        let command = #"cd . && grep "x y" $HOME/f | head -1"#
        #expect(CustomActionStore.normalize(CustomAction(name: "n", command: command)).command == command)
    }
}

// MARK: - 执行命令的 AppleScript 源码

struct TerminalCommandScriptTests {

    /// 四种组合，用来逐个过不变量。
    private var allScripts: [(String, String)] {
        [("Terminal 新窗口", TerminalCommandScript.terminal(mode: .newWindow)),
         ("Terminal 新标签页", TerminalCommandScript.terminal(mode: .newTab)),
         ("iTerm2 新窗口", TerminalCommandScript.iTerm(mode: .newWindow)),
         ("iTerm2 新标签页", TerminalCommandScript.iTerm(mode: .newTab))]
    }

    @Test func commandArrivesThroughArgv() {
        // 命令只能从 argv 拿。脚本里出现 item 2 of argv 才说明调用方是把命令当参数传的，
        // 而不是拼进了源码。拼进去的话，命令里的引号 / $ / 反斜杠会被 AppleScript
        // 的转义规则改写，轻则语法错，重则执行了另一条命令。
        for (name, script) in allScripts {
            #expect(script.contains("item 1 of argv"), "\(name) 少了目录参数")
            #expect(script.contains("item 2 of argv"), "\(name) 少了命令参数")
        }
    }

    @Test func runsAfterChangingDirectory() {
        // 先 cd 到 Finder 当前目录再执行，命令里才能用 `.` 指代那个目录。
        let expected = #""cd " & quoted form of thePath & " && " & theCommand"#
        for (name, script) in allScripts {
            #expect(script.contains(expected), "\(name) 没有先 cd 再执行")
        }
    }

    @Test func pathIsShellQuoted() {
        // 目录可能含空格或中文，必须走 AppleScript 的 quoted form 让 shell 正确解析。
        for (name, script) in allScripts {
            #expect(script.contains("quoted form of thePath"), "\(name) 没有对路径做 shell 引用")
        }
    }

    @Test func iTermNewTabDoesNotWriteIntoCurrentSession() {
        // 往「front window 的 current session」写会把命令直接敲进用户正在跑的 vim / npm 里。
        // 必须先 create tab，再写那个新会话。
        let script = TerminalCommandScript.iTerm(mode: .newTab)
        #expect(script.contains("create tab with default profile"))
        #expect(script.contains("current session of current window"))
    }

    @Test func everyHandlerClosesWithEndRun() {
        // 只写 `on run argv` 不收尾会报 -2741 语法错。
        for (name, script) in allScripts {
            #expect(script.hasSuffix("end run"), "\(name) 少了 end run")
        }
    }
}

// MARK: - 生成的 AppleScript 能否通过编译

/// 用 `osacompile` 把生成的脚本真编译一遍。
///
/// 光比字符串是抓不到语法错的——项目里踩过「`on run argv` 少了 `end run` 报 -2741」
/// 这种只有编译器才看得出来的问题。这里只**编译不执行**，不会打开任何终端窗口。
struct AppleScriptSyntaxTests {

    @Test func generatedScriptsCompile() throws {
        let scripts: [(String, String)] = [
            ("Terminal 新窗口", TerminalCommandScript.terminal(mode: .newWindow)),
            ("Terminal 新标签页", TerminalCommandScript.terminal(mode: .newTab)),
            ("iTerm2 新窗口", TerminalCommandScript.iTerm(mode: .newWindow)),
            ("iTerm2 新标签页", TerminalCommandScript.iTerm(mode: .newTab)),
        ]

        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("LXFinderLauncherSyntaxTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        for (name, script) in scripts {
            let source = dir.appendingPathComponent("script.applescript")
            let compiled = dir.appendingPathComponent("script.scpt")
            try script.write(to: source, atomically: true, encoding: .utf8)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osacompile")
            process.arguments = ["-o", compiled.path, source.path]
            let errors = Pipe()
            process.standardError = errors
            try process.run()
            process.waitUntilExit()

            let message = String(data: errors.fileHandleForReading.readDataToEndOfFile(),
                                 encoding: .utf8) ?? ""
            #expect(process.terminationStatus == 0, "\(name) 编译失败：\(message)")
        }
    }
}

// MARK: - osascript 参数传递

/// 覆盖 `OSAScriptRunner` 的 argv 传递。这些用例只用纯计算脚本，
/// **不会**往 Terminal 发 Apple Event，所以跑测试不会弹出任何终端窗口。
struct OSAScriptRunnerArgumentTests {

    /// 回显第二个参数，用来验证参数是原样送达的。
    private let echoSecond = """
    on run argv
        return item 2 of argv
    end run
    """

    @Test func passesArgumentsVerbatim() throws {
        let command = "npm run dev -- --port 3000"
        #expect(try OSAScriptRunner.run(echoSecond, arguments: ["/tmp", command]) == command)
    }

    @Test func passesCommandsStartingWithDash() throws {
        // 命令可能是 `--help` / `-la` 这种形式。osascript 用自己的 getopt 解析命令行，
        // 不加 `--` 终止符会被当成它自己的选项而直接失败（"illegal option -- f"）。
        #expect(try OSAScriptRunner.run(echoSecond, arguments: ["/tmp", "--help"]) == "--help")
        #expect(try OSAScriptRunner.run(echoSecond, arguments: ["/tmp", "-la"]) == "-la")
    }

    @Test func passesQuotesAndDollarsVerbatim() throws {
        // 命令里带引号、$、反斜杠时不能被 AppleScript 的转义规则改写。
        let command = #"echo "a b" $HOME \n 'x'"#
        #expect(try OSAScriptRunner.run(echoSecond, arguments: ["/tmp", command]) == command)
    }
}

// MARK: - 授权失败的呈现

/// 「自动化授权被拒」必须能被翻译成一条带「打开授权设置」按钮的弹窗。
///
/// 这条路径出问题的症状正是「点了没反应、也没有提示」的两种成因：
/// 错误在途中被吞掉，或者虽然弹了却没给直达设置的入口——两者都让用户无从下手。
@MainActor
struct PrivacySettingsURLTests {

    @Test func tccDeniedFromFinderPointsAtAutomation() {
        let url = AppCommands.privacySettingsURL(for: FinderPathError.tccDenied)
        #expect(url?.absoluteString.contains("Privacy_Automation") == true)
    }

    @Test func tccDeniedFromAppleScriptPointsAtAutomation() {
        // 「打开终端」「自定义动作」走的是 OSAScriptRunner，抛的是 OSAScriptError，
        // 不是 FinderPathError。这条分支漏掉的话，控制终端被拒时用户只会看到一句
        // 「没有自动化授权」，拿不到直达设置的按钮。
        let url = AppCommands.privacySettingsURL(for: OSAScriptError.tccDenied)
        #expect(url?.absoluteString.contains("Privacy_Automation") == true)
    }

    @Test func filePermissionPointsAtFilesAndFolders() {
        let error = FileCreationError.noPermission(URL(fileURLWithPath: "/tmp"))
        let url = AppCommands.privacySettingsURL(for: error)
        #expect(url?.absoluteString.contains("Privacy_FilesAndFolders") == true)
    }

    @Test func unrelatedErrorHasNoSettingsShortcut() {
        // 不是授权问题就别给「打开授权设置」按钮，那会把用户引到无关的面板。
        #expect(AppCommands.privacySettingsURL(for: OSAScriptError.timeoutOrBusy) == nil)
    }
}

// MARK: - 终端 App 不在原位

@MainActor
struct TerminalLauncherErrorTests {

    @Test func customTerminalThrowsWhenAppIsMissing() {
        // 之前这里是 print + return，Release 构建里用户看到的就是「点了没反应」。
        let launcher = CustomTerminalLauncher(
            appURL: URL(fileURLWithPath: "/Applications/不存在的终端-\(UUID().uuidString).app"))
        #expect(throws: TerminalError.self) {
            try launcher.openTerminal(at: URL(fileURLWithPath: "/tmp"), mode: .newWindow)
        }
    }

    @Test func customTerminalRefusesToRunCommands() {
        // 自定义终端只能被 NSWorkspace 打开目录，没有注入命令的手段。
        let launcher = CustomTerminalLauncher(appURL: URL(fileURLWithPath: "/Applications/X.app"))
        #expect(throws: TerminalError.self) {
            try launcher.run("echo hi", at: URL(fileURLWithPath: "/tmp"), mode: .newWindow)
        }
    }
}

// MARK: - 复制路径的格式

/// 每种格式都是一段「会被粘到别处去执行 / 打开」的文本。
/// 转义错了，用户拿到的就是跑不了、或者更糟——跑成另一条命令的东西。
struct PathCopierTests {

    private func dir(_ path: String) -> URL {
        URL(fileURLWithPath: path, isDirectory: true)
    }

    @Test func fullPathIsPlainPOSIXPath() {
        // 不带尾斜杠。这是老版本「复制当前目录路径」的既有行为，不能悄悄改掉。
        #expect(PathCopier.text(for: dir("/Users/me/Projects/foo"), format: .fullPath)
                == "/Users/me/Projects/foo")
    }

    @Test func fileNameIsLastComponent() {
        #expect(PathCopier.text(for: dir("/Users/me/Projects/foo"), format: .fileName) == "foo")
        // 根目录没有「最后一段」，不能复制出空字符串。
        #expect(PathCopier.text(for: dir("/"), format: .fileName) == "/")
    }

    @Test func cdCommandQuotesThePath() {
        #expect(PathCopier.text(for: dir("/Users/me/Projects/foo"), format: .cdCommand)
                == "cd '/Users/me/Projects/foo'")
    }

    @Test func cdCommandHandlesSpacesAndNonASCII() {
        // 空格会让 cd 断成两个参数，中文也不是所有地方都安全——都要靠单引号兜住。
        #expect(PathCopier.text(for: dir("/Users/me/My Documents/项目 A"), format: .cdCommand)
                == "cd '/Users/me/My Documents/项目 A'")
    }

    @Test func cdCommandEscapesSingleQuote() {
        // 单引号是单引号引用里唯一需要特殊处理的字符：必须写成 '\'' 才能表达字面量。
        #expect(PathCopier.text(for: dir("/Users/me/it's here"), format: .cdCommand)
                == #"cd '/Users/me/it'\''s here'"#)
    }

    @Test func fileURLIsPercentEncoded() {
        // 手拼一个含空格的 file URL 会得到打不开的链接，必须走 URL 自己的编码。
        #expect(PathCopier.text(for: dir("/Users/me/My Documents"), format: .fileURL)
                == "file:///Users/me/My%20Documents/")
    }

    @Test func markdownLinkUsesFileNameAsLabel() {
        #expect(PathCopier.text(for: dir("/Users/me/Projects/foo"), format: .markdownLink)
                == "[foo](file:///Users/me/Projects/foo/)")
    }

    @Test func shellQuotingMatchesShellRules() {
        #expect(PathCopier.shellQuoted("plain") == "'plain'")
        #expect(PathCopier.shellQuoted("") == "''")
        #expect(PathCopier.shellQuoted("a'b") == #"'a'\''b'"#)
        // 双引号里会被解释的字符（`$`、反引号、`!`）在单引号里都是字面量，这正是用单引号的理由。
        #expect(PathCopier.shellQuoted("$HOME `x`!") == "'$HOME `x`!'")
    }

    @Test func everyFormatIsListedInMenuOrder() {
        // 声明顺序即菜单顺序；漏一个 case 会让格式悄悄从菜单里消失。
        #expect(PathCopyFormat.allCases.map(\.title)
                == ["完整路径", "文件名", "cd 命令", "Markdown 链接", "file:// URL"])
    }

    @Test func readmeExampleMatchesActualOutput() {
        // README「复制路径的五种格式」那张表用的就是这条路径。在这里钉住它：
        // 以后改了实现却没同步文档，这条会红——文档写了具体值，就必须是真的。
        let url = dir("/Users/me/My Documents")
        #expect(PathCopier.text(for: url, format: .fullPath) == "/Users/me/My Documents")
        #expect(PathCopier.text(for: url, format: .fileName) == "My Documents")
        #expect(PathCopier.text(for: url, format: .cdCommand) == "cd '/Users/me/My Documents'")
        #expect(PathCopier.text(for: url, format: .markdownLink)
                == "[My Documents](file:///Users/me/My%20Documents/)")
        #expect(PathCopier.text(for: url, format: .fileURL) == "file:///Users/me/My%20Documents/")
    }
}

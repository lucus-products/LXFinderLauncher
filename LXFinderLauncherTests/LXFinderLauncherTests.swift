//
//  LXFinderLauncherTests.swift
//  LXFinderLauncherTests
//
//  Created by 启业云03 on 2026/9/1.
//

import Testing
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

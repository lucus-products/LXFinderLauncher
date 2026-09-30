//
//  EditorEntry.swift
//  LXFinderLauncher
//
//  Created by 启业云03 on 2026/9/30.
//

import Foundation

// MARK: - 编辑器种类

/// 编辑器种类。rawValue 沿用设置里 `editorKind` 的历史取值，迁移时直接对应。
///
/// 没有 `0`：旧配置里 `0` 表示「关闭」，不是一个种类——关闭对应的是一份**空的列表**。
enum EditorKind: Int, Codable {
    case cursor = 1
    case vscode = 2
    case custom = 3

    /// 显示名。自定义编辑器取路径末段（去掉 `.app`），取不到才退回泛称。
    func displayName(path: String = "") -> String {
        switch self {
        case .cursor: return "Cursor"
        case .vscode: return "Visual Studio Code"
        case .custom:
            let last = (path as NSString).lastPathComponent
            let trimmed = last.hasSuffix(".app") ? String(last.dropLast(4)) : last
            return trimmed.isEmpty ? "自定义编辑器" : trimmed
        }
    }

    /// 内置编辑器的 bundle id；自定义没有。
    var bundleID: String? {
        switch self {
        case .cursor: return "com.todesktop.230313mzl4w4u92"
        case .vscode: return "com.microsoft.VSCode"
        case .custom: return nil
        }
    }

    /// 内置编辑器装在默认位置时的路径；自定义没有。
    var fallbackPath: String? {
        switch self {
        case .cursor: return "/Applications/Cursor.app"
        case .vscode: return "/Applications/Visual Studio Code.app"
        case .custom: return nil
        }
    }
}

// MARK: - 一项配置

/// 「用编辑器打开」列表里的一项。
struct EditorEntry: Codable, Identifiable, Hashable {

    /// 稳定标识：SwiftUI 列表身份、上下移动与删除都靠它。
    let id: UUID
    /// 编辑器种类。
    var kind: EditorKind
    /// 菜单与设置页里显示的名字。
    var name: String
    /// 仅 `.custom` 使用：编辑器 App 的完整路径。
    var path: String
    /// 是否出现在菜单里。
    var enabled: Bool

    private enum CodingKeys: String, CodingKey {
        case id, kind, name, path, enabled
    }

    init(id: UUID = UUID(), kind: EditorKind, name: String, path: String = "", enabled: Bool = true) {
        self.id = id
        self.kind = kind
        self.name = name
        self.path = path
        self.enabled = enabled
    }

    /// 宽容解码：单个字段缺失或类型不对时退回默认值，而不是让整份配置解码失败。
    /// 同 `FileTemplate`——硬失败会把用户配了半天的编辑器全丢。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        kind = (try? container.decode(EditorKind.self, forKey: .kind)) ?? .custom
        name = (try? container.decode(String.self, forKey: .name)) ?? ""
        path = (try? container.decode(String.self, forKey: .path)) ?? ""
        enabled = (try? container.decode(Bool.self, forKey: .enabled)) ?? true
    }
}

// MARK: - 读写

/// 「用编辑器打开」列表的读写。
///
/// 存成 `@AppStorage("editors")` 里的一个 JSON 字符串。菜单和设置页读写**同一个 key**，
/// 改动才能双向同步——`.menuBarExtraStyle(.menu)` 下打开菜单不会触发菜单内容视图重算，
/// 只有让 SwiftUI 观察到这个依赖才拿得到最新值（详见 MenuContentView）。
enum EditorStore {

    /// UserDefaults / @AppStorage 键。
    static let defaultsKey = "editors"

    /// 单选时代的旧键。**不要删、不要改名**：老版本写下的值要靠它们派生列表。
    ///
    /// `editorKind`：0=关闭 1=Cursor 2=VSCode 3=自定义；`customEditorPath`：自定义编辑器的路径。
    static let legacyKindKey = "editorKind"
    static let legacyPathKey = "customEditorPath"

    /// 派生出来的那一项的固定 id。
    ///
    /// 不能写成 `UUID()`：派生结果会被反复解码去做 SwiftUI 的 ForEach 身份比对，
    /// 每次现生成新 id 会让列表身份抖动、绑定串行（同 `FileTemplateStore.defaultID` 的坑）。
    /// 前缀换成了 `2F`，与创建文件的 `1F` 区分开，便于 `defaults read` 时辨认。
    private static let derivedEntryID = UUID(uuidString: "2F000000-0000-4000-8000-000000000001")!

    /// 解析列表。
    ///
    /// - 非空且能解码 → 直接用。`[]` 就是空列表，尊重用户把编辑器全删掉的选择。
    /// - 空串或解码失败 → 由旧的单选配置**就地派生**。
    ///
    /// 之所以用「派生」而不是「启动时写一次迁移」：写一次会让从没碰过编辑器的用户
    /// 也被写进一个 `"[]"`，从此再也享受不到将来版本的默认值；更糟的是
    /// 「升级 → 降级改 editorKind → 再升级」这条序列里，旧值会被永久回滚成迁移当时的快照。
    /// 派生则是无状态的：只要用户没在新列表里动过手，旧键始终是权威。
    static func editors(from json: String,
                        legacyKind: Int,
                        legacyPath: String) -> [EditorEntry] {
        if !json.isEmpty,
           let data = json.data(using: .utf8),
           let list = try? JSONDecoder().decode([EditorEntry].self, from: data) {
            return list
        }
        return derived(fromLegacyKind: legacyKind, path: legacyPath)
    }

    /// 序列化回 @AppStorage。编码失败返回空串让读取端退回派生，
    /// 而不是在 UserDefaults 里留半截 JSON（同 `FileTemplateStore.encode`）。
    static func encode(_ editors: [EditorEntry]) -> String {
        guard let data = try? JSONEncoder().encode(editors),
              let json = String(data: data, encoding: .utf8)
        else { return "" }
        return json
    }

    /// 菜单里实际要显示的编辑器：勾选的、且配置完整的。
    ///
    /// 刻意**不查文件系统**——可用性校验放到真正打开时做。菜单栏每次打开都会重算 body，
    /// 在这里塞 LaunchServices 查询会让菜单变卡；而「App 被卸载了」这种情况，
    /// 给出明确报错比把菜单项悄悄藏起来更利于用户发现配置坏了。
    /// 但「路径还是空的」不同：那是用户自己还没填完，不该变成一个点了就报错的菜单项。
    static func menuEditors(from json: String,
                            legacyKind: Int,
                            legacyPath: String) -> [EditorEntry] {
        editors(from: json, legacyKind: legacyKind, legacyPath: legacyPath)
            .filter { $0.enabled && isConfigured($0) }
    }

    /// 配置是否完整到可以出现在菜单里。
    ///
    /// 只有自定义编辑器需要用户填东西：路径空着就是「添加编辑器 → 自定义…」之后还没填的草稿。
    /// 内置编辑器的路径是运行时按 bundle id 解析的，不需要用户填。
    static func isConfigured(_ entry: EditorEntry) -> Bool {
        guard entry.kind == .custom else { return true }
        return !entry.path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 由旧的单选配置派生列表。`kind` 解不出（0=关闭）或自定义却没填路径，都视为「没配」。
    private static func derived(fromLegacyKind kind: Int, path: String) -> [EditorEntry] {
        guard let legacy = EditorKind(rawValue: kind) else { return [] }

        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if legacy == .custom && trimmedPath.isEmpty { return [] }

        return [EditorEntry(id: derivedEntryID,
                            kind: legacy,
                            name: legacy.displayName(path: trimmedPath),
                            path: trimmedPath)]
    }
}

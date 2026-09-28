//
//  FileTemplate.swift
//  LXFinderLauncher
//
//  Created by 启业云03 on 2026/9/28.
//

import Foundation

/// 「创建文件」里的一种文件类型（菜单里的一项）。
struct FileTemplate: Codable, Identifiable, Hashable {

    /// 稳定标识：SwiftUI 列表身份、上下移动与删除都靠它。
    let id: UUID
    /// 菜单与设置页里显示的名字，如「Word 文档」。
    var name: String
    /// 扩展名，不含点，如 "docx"。
    var ext: String
    /// 是否出现在菜单里。
    var enabled: Bool

    private enum CodingKeys: String, CodingKey {
        case id, name, ext, enabled
    }

    init(id: UUID = UUID(), name: String, ext: String, enabled: Bool = true) {
        self.id = id
        self.name = name
        self.ext = ext
        self.enabled = enabled
    }

    /// 宽容解码：单个字段缺失或类型不对时退回默认值，而不是让整份配置解码失败。
    /// 两个场景会用到：以后给 FileTemplate 加字段（老 JSON 里没有），
    /// 以及用户手改 UserDefaults 里的 JSON。硬失败会让整个列表被静默重置成默认值，
    /// 用户配了半天的类型全丢。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        name = (try? container.decode(String.self, forKey: .name)) ?? ""
        ext = (try? container.decode(String.self, forKey: .ext)) ?? ""
        enabled = (try? container.decode(Bool.self, forKey: .enabled)) ?? true
    }
}

// MARK: - 读写

/// 「创建文件」类型列表的读写。
///
/// 存成 `@AppStorage("fileTemplates")` 里的一个 JSON 字符串。菜单和设置页读写
/// **同一个 key**，改动才能双向同步——`.menuBarExtraStyle(.menu)` 下打开菜单
/// 不会触发菜单内容视图重算，只有让 SwiftUI 观察到这个依赖才拿得到最新值
/// （详见 MenuContentView）。
enum FileTemplateStore {

    /// UserDefaults / @AppStorage 键。
    static let defaultsKey = "fileTemplates"

    /// 「上次使用的文件类型」的扩展名。
    ///
    /// 存扩展名而不是类型的 id：类型列表本身是可编辑的，用户删掉再重加会换一个 id，
    /// 而扩展名更耐用；`defaults read` 时也一眼看得懂。
    static let lastUsedExtKey = "lastUsedFileTemplateExt"

    /// 内置默认列表，顺序即菜单顺序。
    ///
    /// 不含 `.doc` / `.xls` / `.ppt`：这几个是 OLE2 二进制格式，没法合成出最小可用的
    /// 空白文件，留在默认列表里只会得到一个双击报损坏的菜单项。用户想要可以自己加。
    static let defaultTemplates: [FileTemplate] = [
        FileTemplate(id: defaultID(1), name: "Markdown", ext: "md"),
        FileTemplate(id: defaultID(2), name: "文本文件", ext: "txt"),
        FileTemplate(id: defaultID(3), name: "Word 文档", ext: "docx"),
        FileTemplate(id: defaultID(4), name: "Excel 工作簿", ext: "xlsx"),
        FileTemplate(id: defaultID(5), name: "PowerPoint 演示文稿", ext: "pptx"),
        FileTemplate(id: defaultID(6), name: "JSON", ext: "json"),
        FileTemplate(id: defaultID(7), name: "YAML", ext: "yml"),
        FileTemplate(id: defaultID(8), name: "HTML", ext: "html"),
    ]

    /// 生成内置类型的固定 id。
    ///
    /// 不能写成 `UUID()`：默认列表会被反复解码去做 SwiftUI 的 ForEach 身份比对，
    /// 每次现生成新 id 会让列表身份抖动，导致绑定串行、动画错乱。
    /// 这里用固定前缀 + 序号拼出跨进程稳定的值。
    private static func defaultID(_ n: Int) -> UUID {
        // 强制解包安全：格式串固定，n 落在 %012d 范围内时一定是合法 UUID 字面量。
        UUID(uuidString: String(format: "1F000000-0000-4000-8000-%012d", n))!
    }

    /// 解析存在 @AppStorage 里的 JSON。
    ///
    /// 空串和解码失败都退回默认列表。空串代表「首次运行」——@AppStorage 的默认值
    /// 不会写进 UserDefaults，所以键不存在时读到的就是 `""`，而 `""` 不是合法 JSON，
    /// 两种「没有配置」的情况天然落在同一个分支。
    /// 能解出空数组 `[]` 则返回空：那是用户主动把类型删光了，要尊重，不能拿默认值盖回去。
    static func templates(from json: String) -> [FileTemplate] {
        guard !json.isEmpty,
              let data = json.data(using: .utf8),
              let list = try? JSONDecoder().decode([FileTemplate].self, from: data)
        else { return defaultTemplates }
        return list
    }

    /// 序列化回 @AppStorage。
    /// 编码失败理论上不会发生（纯值类型），真失败时返回空串让读取端退回默认列表，
    /// 而不是在 UserDefaults 里留半截 JSON。
    static func encode(_ templates: [FileTemplate]) -> String {
        guard let data = try? JSONEncoder().encode(templates),
              let json = String(data: data, encoding: .utf8)
        else { return "" }
        return json
    }

    /// 菜单里实际要显示的类型：规范化后，保留「启用」且「扩展名非空」的项。
    ///
    /// 扩展名为空的是用户在设置页点了「添加类型」还没填完的草稿，
    /// 拿去建文件会得到一个没有扩展名的文件，不该出现在菜单里。
    static func menuTemplates(from json: String) -> [FileTemplate] {
        templates(from: json)
            // 写成闭包而不是 `.map(normalize)`：把 MainActor 隔离的方法当函数值传递会丢失
            // 隔离信息（编译警告），闭包则在当前 actor 内求值，没有这个问题。
            .map { normalize($0) }
            .filter { $0.enabled && !$0.ext.isEmpty }
    }

    /// 全局热键直建时该用哪个类型：优先「上次用过的扩展名」，否则取菜单里的第一个。
    ///
    /// 传进来的扩展名可能已经被用户删掉、禁用或改掉了，所以找不到就回退而不是失败。
    /// 一个可用类型都没有才返回 nil（调用方据此提示用户去设置里加）。
    static func quickCreateTemplate(from json: String, lastUsedExt: String) -> FileTemplate? {
        let available = menuTemplates(from: json)
        let wanted = normalizeExtension(lastUsedExt)
        if !wanted.isEmpty, let matched = available.first(where: { $0.ext == wanted }) {
            return matched
        }
        return available.first
    }

    /// 规范化一条类型：显示名去首尾空白；扩展名去空白、去首尾的点和转小写。
    ///
    /// 只在保存与建文件时调用，**不要**放进输入框的 binding setter——中文输入法
    /// 有拼音候选的 marked text 阶段，在 setter 里改写字符串会打断输入法合成、光标乱跳。
    static func normalize(_ template: FileTemplate) -> FileTemplate {
        var result = template
        result.name = template.name.trimmingCharacters(in: .whitespacesAndNewlines)
        result.ext = normalizeExtension(template.ext)
        return result
    }

    /// 规范化扩展名：去空白、去首尾的点和转小写。
    /// 用户在设置页很容易填成「.MD」「 md 」，统一在这里收干净，调用方不必各自处理。
    static func normalizeExtension(_ ext: String) -> String {
        ext.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
    }
}

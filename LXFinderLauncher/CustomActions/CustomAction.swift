//
//  CustomAction.swift
//  LXFinderLauncher
//
//  Created by 启业云03 on 2026/9/30.
//

import Foundation

/// 一条「自定义动作」：在 Finder 当前目录的终端里执行一条命令。
///
/// 命令**不是 App 执行的**，而是被送进用户配置的终端由他的 shell 执行。这样既不新增
/// 任何 TCC 授权，也把「跑什么」的责任留在用户和终端那边（App 不 fork 任何 shell）。
struct CustomAction: Codable, Identifiable, Hashable {

    /// 稳定标识：SwiftUI 列表身份、上下移动与删除都靠它。
    let id: UUID
    /// 菜单与设置页里显示的名字。
    var name: String
    /// 要执行的命令，如 `npm run dev`。执行前会先 cd 到目录，所以命令里用 `.` 就够。
    var command: String
    /// 是否出现在菜单里。
    var enabled: Bool

    private enum CodingKeys: String, CodingKey {
        case id, name, command, enabled
    }

    init(id: UUID = UUID(), name: String, command: String, enabled: Bool = true) {
        self.id = id
        self.name = name
        self.command = command
        self.enabled = enabled
    }

    /// 宽容解码：单个字段缺失或类型不对时退回默认值，而不是让整份配置解码失败。
    /// 同 `FileTemplate`——硬失败会把用户配了半天的动作全丢。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        name = (try? container.decode(String.self, forKey: .name)) ?? ""
        command = (try? container.decode(String.self, forKey: .command)) ?? ""
        enabled = (try? container.decode(Bool.self, forKey: .enabled)) ?? true
    }
}

// MARK: - 读写

/// 自定义动作列表的读写。
///
/// 存成 `@AppStorage("customActions")` 里的一个 JSON 字符串。菜单和设置页读写**同一个 key**。
enum CustomActionStore {

    /// UserDefaults / @AppStorage 键。
    static let defaultsKey = "customActions"

    /// 命令长度上限。
    ///
    /// Terminal 的 `do script` 与 iTerm 的 `write text` 对超长文本没有明确的行为保证，
    /// 而一条真有用的命令通常也就几十个字符。给个宽松上限，在设置页就拦住并提示，
    /// 而不是等它变成终端里一条莫名其妙的半截命令。
    static let maxCommandLength = 1024

    /// 出厂默认：**空的**。
    ///
    /// 刻意不预置任何示例命令——这个列表里每一条都是会被真的拿去执行的，
    /// 默认塞一条 `git pull` 之类的东西，等于替用户决定在他自己的目录里跑什么。
    static let defaultActions: [CustomAction] = []

    /// 解析存在 @AppStorage 里的 JSON。
    ///
    /// 空串和解码失败都退回默认（空）列表；能解出 `[]` 也返回空——两者语义一致，
    /// 不像 FileTemplate 那样需要区分「首次运行」和「用户删光」。
    static func actions(from json: String) -> [CustomAction] {
        guard !json.isEmpty,
              let data = json.data(using: .utf8),
              let list = try? JSONDecoder().decode([CustomAction].self, from: data)
        else { return defaultActions }
        return list
    }

    /// 序列化回 @AppStorage。编码失败返回空串（同 FileTemplateStore.encode）。
    static func encode(_ actions: [CustomAction]) -> String {
        guard let data = try? JSONEncoder().encode(actions),
              let json = String(data: data, encoding: .utf8)
        else { return "" }
        return json
    }

    /// 菜单里实际要显示的动作：勾选的、名字和命令都填了的、且命令没超长的。
    ///
    /// 名字或命令为空，就是用户在设置页点了「添加动作」还没填完的草稿：名字空着菜单项没法认，
    /// 命令空着点了等于什么都没发生。超长的则可能在终端那边被截断成另一条命令，宁可不显示。
    static func menuActions(from json: String) -> [CustomAction] {
        actions(from: json)
            .map { normalize($0) }
            .filter {
                $0.enabled
                    && !$0.name.isEmpty
                    && !$0.command.isEmpty
                    && $0.command.count <= maxCommandLength
            }
    }

    /// 规范化一条动作。
    ///
    /// 名字去首尾空白。命令只去首尾空白、并把换行压成空格，**中间一个字符都不动**——
    /// 命令里可能有 `&&`、引号、管道、`$`，任何「清洗」都是在破坏它。
    /// 换行必须处理：它会变成终端里的多次回车，等于把一条命令拆成几条依次执行，语义完全变了。
    static func normalize(_ action: CustomAction) -> CustomAction {
        var result = action
        result.name = action.name.trimmingCharacters(in: .whitespacesAndNewlines)
        result.command = action.command
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        return result
    }
}

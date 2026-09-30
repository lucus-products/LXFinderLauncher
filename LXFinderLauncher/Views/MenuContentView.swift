//
//  MenuContentView.swift
//  LXFinderLauncher
//
//  Created by 启业云03 on 2026/9/1.
//

import SwiftUI

/// 菜单栏菜单内容。
///
/// `.menuBarExtraStyle(.menu)` 下直接把菜单项视图放进来即可，
/// 不要包 VStack，否则菜单布局异常。
///
/// 该样式下还有一条关键限制：**打开菜单不会触发 body 重算**（SwiftUI 只追踪状态依赖，
/// 「打开菜单」不是状态变化，见 feedback FB13683957）。所以菜单项依赖的设置必须用
/// `@AppStorage` 读——它会被 SwiftUI 观察到，改完设置再打开菜单就是新值；
/// 用 `UserDefaults.standard` 静态读则要重启 App 才生效。
struct MenuContentView: View {
    /// 打开 SwiftUI 的 Settings 场景（macOS 14+）。
    @Environment(\.openSettings) private var openSettings

    /// 编辑器列表（JSON）。与设置页读写**同一个键**，改动才能双向同步。
    /// 必须用 @AppStorage 而不是静态读 UserDefaults：`.menu` 样式下打开菜单不重算 body，
    /// 只有 SwiftUI 观察得到的依赖改了才会刷新（原因见上面）。
    @AppStorage(EditorStore.defaultsKey) private var editorsJSON = ""

    /// 单选时代的旧键。列表还没被写过时，由它们派生——所以这里也得是 @AppStorage，
    /// 否则老版本改过的值不会被观察到。
    @AppStorage(EditorStore.legacyKindKey) private var legacyEditorKind = 0
    @AppStorage(EditorStore.legacyPathKey) private var legacyEditorPath = ""

    /// 当前启用的编辑器，顺序即配置顺序。
    private var editors: [EditorEntry] {
        EditorStore.menuEditors(from: editorsJSON,
                                legacyKind: legacyEditorKind,
                                legacyPath: legacyEditorPath)
    }

    /// 「用编辑器打开」菜单项。
    ///
    /// 启用 1 个时保持原来的单按钮形态（绝大多数用户的配置，点一下就到）；
    /// 启用多个时收进子菜单，免得菜单被编辑器撑长。
    /// 一个都没启用时整项不出现（与改造前的 `editorKind != 0` 一致）。
    @ViewBuilder
    private var editorMenu: some View {
        if editors.count == 1, let only = editors.first {
            Button("用 \(only.name) 打开") { openEditor(only) }
        } else if editors.count > 1 {
            Menu("用编辑器打开") {
                ForEach(editors) { entry in
                    Button(entry.name) { openEditor(entry) }
                }
                Divider()
                Button("管理编辑器…") {
                    DispatchQueue.main.async {
                        SettingsOpener.open(pane: .editor) { openSettings() }
                    }
                }
            }
        }
    }

    /// 打开编辑器。与「创建文件」同一条理由：弹窗会在菜单的 tracking session 结束前
    /// 就弹出来、抢不到键盘焦点，所以丢到下一个 runloop 周期等菜单先关掉。
    /// 这里确实可能弹窗——编辑器 App 找不到时报错（见 EditorOpenerFactory.resolve）。
    private func openEditor(_ entry: EditorEntry) {
        DispatchQueue.main.async {
            AppCommands.shared.openInEditor(entry)
        }
    }

    /// 「创建文件」的类型列表（JSON）。与设置页读写**同一个键**，改动才能双向同步。
    @AppStorage(FileTemplateStore.defaultsKey) private var fileTemplatesJSON = ""

    /// 「自定义动作」列表（JSON）。同上。
    @AppStorage(CustomActionStore.defaultsKey) private var customActionsJSON = ""

    /// 当前终端。只用来判断「自定义终端不支持执行命令」——
    /// 取值含义见 `TerminalLauncherFactory.make`（0=Terminal 1=iTerm2 2=自定义）。
    @AppStorage("terminalKind") private var terminalKind = 0

    /// 「自定义终端」在设置里的取值。
    private static let customTerminalKind = 2

    var body: some View {
        Button("在此处打开终端") { AppCommands.shared.openTerminalHere() }
        editorMenu
        // 「复制路径」二级子菜单：同一份路径有好几种常用写法，收进子菜单给菜单栏省一行。
        // 全局热键 ⌃⌥⌘C 仍然固定复制「完整路径」——热键没有选格式的机会，而完整路径通用性最好。
        Menu("复制路径") {
            ForEach(PathCopyFormat.allCases) { format in
                Button(format.title) {
                    // 与「创建文件」同一条理由：读路径失败时要弹错误框，而弹窗必须等菜单的
                    // tracking session 结束，否则抢不到键盘焦点。
                    DispatchQueue.main.async {
                        AppCommands.shared.copyCurrentPath(format: format)
                    }
                }
            }
        }
        Button("打开 Finder 目录") { AppCommands.shared.revealInFinder() }

        // 「创建文件」二级子菜单。
        // 子菜单项只用 Button("文本")：`.menu` 样式下 Label 的 systemImage、各种 modifier
        // 和自定义视图都不会渲染（菜单里也不要用 Section 做标题，会多出一条分隔线）。
        Menu("创建文件") {
            let templates = FileTemplateStore.menuTemplates(from: fileTemplatesJSON)
            if templates.isEmpty {
                // 用户把类型全关掉时给个占位。否则子菜单空得只剩分隔线，看着像功能坏了。
                Button("（未启用任何类型，去设置里添加）") {}
                    .disabled(true)
            } else {
                ForEach(templates) { template in
                    Button("\(template.name)（.\(template.ext)）") {
                        // 直接调用的话，弹窗会在菜单的 tracking session 还没结束时就弹出来，
                        // 抢不到键盘焦点；丢到下一个 runloop 周期等菜单先关掉。
                        DispatchQueue.main.async {
                            AppCommands.shared.createFile(using: template)
                        }
                    }
                }
            }
            Divider()
            Button("管理文件类型…") {
                // 直达「创建文件」面板，省得用户开完设置还要自己再点一次。
                DispatchQueue.main.async {
                    SettingsOpener.open(pane: .newFile) { openSettings() }
                }
            }
        }

        Divider()

        // 「自定义动作」二级子菜单。与「创建文件」一样常驻显示——这是个新功能，
        // 藏起来等于没人知道它存在；空的时候给一行禁用占位，也顺便挂住「管理动作…」入口。
        Menu("自定义动作") {
            let actions = CustomActionStore.menuActions(from: customActionsJSON)
            if actions.isEmpty {
                Button("（还没有配置动作，去设置里添加）") {}
                    .disabled(true)
            } else if terminalKind == Self.customTerminalKind {
                // 自定义终端只能被 NSWorkspace 打开目录，没有注入命令的手段。
                // 整段置灰而不是点了再报错——后者等于每次点击都是一次惊吓。
                Button("（当前终端不支持执行命令，请在设置里改用 Terminal 或 iTerm2）") {}
                    .disabled(true)
            } else {
                ForEach(actions) { action in
                    Button(action.name) {
                        DispatchQueue.main.async {
                            AppCommands.shared.runAction(action)
                        }
                    }
                }
            }
            Divider()
            Button("管理动作…") {
                DispatchQueue.main.async {
                    SettingsOpener.open(pane: .actions) { openSettings() }
                }
            }
        }

        Divider()

        Button("检查更新…") { AppCommands.shared.checkForUpdates() }
        Button("设置…") {
            // 不用 SettingsLink：菜单栏 App 需要先激活自身，否则设置窗口被遮挡。
            SettingsOpener.open { openSettings() }
        }
        Divider()
        Button("退出 LXFinderLauncher") { NSApp.terminate(nil) }
    }
}

#Preview {
    MenuContentView()
}

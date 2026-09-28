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

    /// 编辑器类型，0 = 关闭。这里用 @AppStorage 而不是 EditorOpenerFactory.isEnabled()：
    /// 后者内部静态读 UserDefaults，改完设置菜单项不刷新（原因见上面）。
    @AppStorage("editorKind") private var editorKind = 0

    /// 「创建文件」的类型列表（JSON）。与设置页读写**同一个键**，改动才能双向同步。
    @AppStorage(FileTemplateStore.defaultsKey) private var fileTemplatesJSON = ""

    var body: some View {
        Button("在此处打开终端") { AppCommands.shared.openTerminalHere() }
        if editorKind != 0 {
            Button("用 \(EditorOpenerFactory.displayName()) 打开") { AppCommands.shared.openInEditor() }
        }
        Button("复制当前目录路径") { AppCommands.shared.copyCurrentPath() }
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

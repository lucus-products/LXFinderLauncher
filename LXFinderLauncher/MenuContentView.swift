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
struct MenuContentView: View {
    /// 打开 SwiftUI 的 Settings 场景（macOS 14+）。
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("在此处打开终端") { AppCommands.shared.openTerminalHere() }
        if EditorOpenerFactory.isEnabled() {
            Button("用 \(EditorOpenerFactory.displayName()) 打开") { AppCommands.shared.openInEditor() }
        }
        Button("复制当前目录路径") { AppCommands.shared.copyCurrentPath() }
        Button("打开 Finder 目录") { AppCommands.shared.revealInFinder() }
        Button("检查更新…") { AppCommands.shared.checkForUpdates() }
        Divider()
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

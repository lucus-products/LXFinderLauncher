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

    var body: some View {
        Button("在此处打开终端") { AppCommands.shared.openTerminalHere() }
        if EditorOpenerFactory.isEnabled() {
            Button("用 \(EditorOpenerFactory.displayName()) 打开") { AppCommands.shared.openInEditor() }
        }
        Button("复制当前目录路径") { AppCommands.shared.copyCurrentPath() }
        Button("打开 Finder 目录") { AppCommands.shared.revealInFinder() }
        Button("检查更新…") { AppCommands.shared.checkForUpdates() }
        Divider()
        SettingsLink { Text("设置…") }
        Divider()
        Button("退出 LXFinderLauncher") { NSApp.terminate(nil) }
    }
}

#Preview {
    MenuContentView()
}

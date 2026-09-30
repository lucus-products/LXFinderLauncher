//
//  LXFinderLauncherApp.swift
//  LXFinderLauncher
//
//  Created by 启业云03 on 2026/9/1.
//

import SwiftUI
import AppKit

@main
struct LXFinderLauncherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
        } label: {
            MenuBarIconView()
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
        }
    }
}

/// 菜单栏图标：默认显示 App 图标，可在设置中切换回终端图标（保留，方便自定义）。
///
/// 还负责显示**瞬时反馈**：复制路径这类成功后屏幕上什么都没变的操作，会让图标闪一下勾
/// （见 `MenuBarFeedback`）。
struct MenuBarIconView: View {
    /// 0 = App 图标（默认），1 = 终端图标。
    @AppStorage("menuBarIconStyle") private var style = 0

    /// 必须用 @ObservedObject 而不是直接读 `MenuBarFeedback.shared`，否则闪烁不会刷新图标。
    @ObservedObject private var feedback = MenuBarFeedback.shared

    var body: some View {
        if let symbol = feedback.flashSymbol {
            Image(systemName: symbol)
        } else if style == 1 {
            Image(systemName: "terminal")
        } else {
            Image(nsImage: AppIconImage.menuBar())
        }
    }
}

/// App 图标缩放到菜单栏尺寸。
enum AppIconImage {
    static func menuBar() -> NSImage {
        let icon = (NSApp.applicationIconImage?.copy() as? NSImage) ?? NSImage()
        icon.size = NSSize(width: 18, height: 18)
        return icon
    }
}

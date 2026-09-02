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
struct MenuBarIconView: View {
    /// 0 = App 图标（默认），1 = 终端图标。
    @AppStorage("menuBarIconStyle") private var style = 0

    var body: some View {
        if style == 1 {
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

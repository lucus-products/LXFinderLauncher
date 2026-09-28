//
//  SettingsOpener.swift
//  LXFinderLauncher
//
//  Created by 启业云03 on 2026/9/1.
//

import AppKit
import SwiftUI

/// 打开「设置」窗口时保证其显示在最前面。
///
/// 本 App 是菜单栏应用（Info.plist 里 LSUIElement = true，activationPolicy 为
/// `.accessory`），平时不会成为前台 App。SwiftUI 的 SettingsLink / Settings 场景
/// 只负责把设置窗口显示出来、并不会激活本 App，所以在其它 App 处于前台时，
/// 设置窗口会落在后面、被遮挡——项目里其它 NSAlert 弹窗在 show 前手动
/// `NSApp.activate` 的原因相同，这里把设置窗口这条路径补上。
///
/// 做法：先缓存 Settings 场景的窗口引用；打开时手动
/// `NSApp.activate(ignoringOtherApps: true)` + `makeKeyAndOrderFront`，
/// 把本 App 激活并把设置窗口提到最前。
enum SettingsOpener {
    private static weak var settingsWindow: NSWindow?

    /// 打开设置窗口并确保置前，可指定落到哪个面板。
    ///
    /// - Parameters:
    ///   - pane: 要定位到的面板；传 nil 则保持上次停留的面板（与系统设置的惯例一致）。
    ///   - showSettings: 首次打开时触发 SwiftUI Settings 场景显示的闭包
    ///     （即 `@Environment(\.openSettings)`）。
    @MainActor
    static func open(pane: SettingsPane? = nil, showSettings: @MainActor () -> Void) {
        // 先把目标面板写进 UserDefaults，再开窗。SettingsView 用 @AppStorage 读同一个键，
        // 所以窗口**已经开着**时也能立刻切过去；没开时首次挂载读到的就是这个值。
        // 关键：不要用「一次性标记」，那样只在首次打开生效，窗口已开的情况下点了没反应。
        if let pane {
            UserDefaults.standard.set(pane.rawValue, forKey: SettingsPane.defaultsKey)
        }

        // 关键：先把本 App 激活为前台 App，否则设置窗口会被其它应用遮挡。
        NSApp.activate(ignoringOtherApps: true)

        if let window = settingsWindow {
            // 窗口已存在（含被关闭后复显的场景）：直接显示并置顶。
            window.makeKeyAndOrderFront(nil)
        } else {
            // 首次打开：SettingsView 挂载后会通过 capture(_:) 拿到窗口并置前。
            showSettings()
        }
    }

    /// SettingsView 挂载后回调：缓存窗口引用并把它带到最前。
    @MainActor
    static func capture(_ window: NSWindow) {
        settingsWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

/// 嵌入 SettingsView 根部，用于在设置窗口出现时捕获其 NSWindow 引用。
///
/// SwiftUI 没有公开获取 Settings 场景窗口的 API，用一个不可见的
/// NSViewRepresentable 在视图挂载后反查所属窗口，是最稳妥的方式。
struct SettingsWindowCapture: NSViewRepresentable {

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        // 等视图真正挂载进窗口后再取 window，否则此刻可能还是 nil。
        DispatchQueue.main.async { [weak view] in
            guard let window = view?.window else { return }
            SettingsOpener.capture(window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

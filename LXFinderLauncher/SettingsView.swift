//
//  SettingsView.swift
//  LXFinderLauncher
//
//  Created by 启业云03 on 2026/9/1.
//

import SwiftUI
import Carbon.HIToolbox
import ServiceManagement

/// 设置窗口：全局快捷键、终端（打开方式/位置/自定义）、编辑器、开机自启、权限。
struct SettingsView: View {

    @AppStorage("hotkeyEnabled") private var hotkeyEnabled = true
    /// 存 Int（AppStorage 不支持 UInt32），使用时转 UInt32。
    @AppStorage("hotkeyKeyCode") private var hotkeyKeyCode = Int(kVK_ANSI_T)
    @AppStorage("hotkeyModifiers") private var hotkeyModifiers = Int(cmdKey | shiftKey)

    @AppStorage("terminalKind") private var terminalKind = 0
    @AppStorage("customTerminalPath") private var customTerminalPath = ""
    @AppStorage("terminalOpenMode") private var terminalOpenMode = 0

    @AppStorage("editorKind") private var editorKind = 0
    @AppStorage("customEditorPath") private var customEditorPath = ""

    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("autoCheckUpdates") private var autoCheckUpdates = true
    @AppStorage("menuBarIconStyle") private var menuBarIconStyle = 0

    @State private var isITermInstalled = TerminalLauncherFactory.isITermInstalled()
    @State private var isCursorInstalled = EditorOpenerFactory.isCursorInstalled()
    @State private var isVSCodeInstalled = EditorOpenerFactory.isVSCodeInstalled()
    @StateObject private var recorder = HotkeyRecorder()
    /// 观察热键注册结果（共享单例，注册失败时显示红字提示）。
    @ObservedObject private var hotkeyManager = HotkeyManager.shared

    var body: some View {
        Form {
            Section("快捷键") {
                Toggle("启用全局快捷键", isOn: $hotkeyEnabled)
                    .onChange(of: hotkeyEnabled) { _, _ in
                        HotkeyManager.shared.applySettings()
                    }

                if hotkeyEnabled {
                    HStack {
                        Text("快捷键")
                        Spacer()
                        Button(recorder.isRecording
                               ? "请按下组合键…"
                               : KeycodeTable.displayString(
                                   keyCode: UInt32(hotkeyKeyCode),
                                   modifiers: UInt32(hotkeyModifiers))) {
                            recorder.begin()
                        }
                    }

                    if hotkeyManager.registerFailed {
                        Label("注册失败：该组合键可能已被其它应用占用，请更换一个组合键。",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Text("作用：在 Finder 当前窗口所在的目录打开终端（等同菜单「在此处打开终端」）。首次触发需在「系统设置 → 隐私与安全性 → 自动化」允许本 App 控制 Finder。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("菜单栏图标") {
                Picker("图标", selection: $menuBarIconStyle) {
                    Text("应用图标").tag(0)
                    Text("终端图标").tag(1)
                }
                Text("菜单栏显示的图标；默认应用图标，可切换回终端图标。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("终端") {
                Picker("打开方式", selection: $terminalKind) {
                    Text("Terminal（系统）").tag(0)
                    if isITermInstalled {
                        Text("iTerm2").tag(1)
                    }
                    Text("自定义…").tag(2)
                }
                .onChange(of: terminalKind) { _, newValue in
                    if newValue == 1 && !isITermInstalled {
                        terminalKind = 0   // iTerm2 未安装则回退
                    }
                }

                if terminalKind == 2 {
                    TextField("终端 App 路径，如 /Applications/kitty.app",
                              text: $customTerminalPath)
                }

                Picker("打开位置", selection: $terminalOpenMode) {
                    Text("新窗口").tag(0)
                    Text("新建标签页").tag(1)
                }

                if terminalKind == 2 {
                    if terminalOpenMode == 1 {
                        Text("自定义终端暂不支持新建标签页，将始终使用新窗口。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    // 说明两种模式的语义，避免用户误以为「新建标签页」不会开新窗口。
                    Text(terminalOpenMode == 0
                         ? "总是新建一个终端窗口。"
                         : "没有已打开的终端时新建窗口，已有窗口则在其中新建标签页。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("编辑器") {
                Picker("用编辑器打开 Finder 目录", selection: $editorKind) {
                    Text("关闭").tag(0)
                    if isCursorInstalled {
                        Text("Cursor").tag(1)
                    }
                    if isVSCodeInstalled {
                        Text("Visual Studio Code").tag(2)
                    }
                    Text("自定义…").tag(3)
                }
                .onChange(of: editorKind) { _, newValue in
                    if (newValue == 1 && !isCursorInstalled) || (newValue == 2 && !isVSCodeInstalled) {
                        editorKind = 0
                    }
                }

                if editorKind == 3 {
                    TextField("编辑器 App 路径，如 /Applications/Nova.app",
                              text: $customEditorPath)
                }

                if editorKind != 0 {
                    Text("菜单栏将出现「用 \(EditorOpenerFactory.displayName()) 打开」项。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("启动") {
                Toggle("开机自动启动", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        setLaunchAtLogin(enabled)
                    }
            }

            Section("更新") {
                Toggle("自动检查更新", isOn: $autoCheckUpdates)
                Button("立即检查更新") { AppCommands.shared.checkForUpdates() }
                Text("发现新版本时提示下载。更新源需在发布前替换为自己托管的 JSON（UpdateChecker.feedURL）。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("权限") {
                Button("打开系统「自动化」授权设置…") {
                    let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!
                    NSWorkspace.shared.open(url)
                }
                Text("首次使用需授权本 App 控制 Finder，以便读取当前目录。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        // 捕获设置窗口引用，保证它总是显示在最前面（详见 SettingsOpener）。
        .background(SettingsWindowCapture())
        .formStyle(.grouped)
        .frame(width: 400)
        .padding(20)
        .onAppear {
            // 同步开机自启状态（用户可能在系统设置里手动改过）。
            launchAtLogin = SMAppService.mainApp.status == .enabled
            recorder.onRecorded = { keyCode, modifiers in
                hotkeyKeyCode = Int(keyCode)
                hotkeyModifiers = Int(modifiers)
                HotkeyManager.shared.applySettings()
            }
        }
    }

    // MARK: - 开机自启

    /// 注册 / 注销登录项。需要 App 位于 /Applications 且签名有效。
    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("[LXFinderLauncher] 设置开机自启失败：\(error)")
        }
    }
}

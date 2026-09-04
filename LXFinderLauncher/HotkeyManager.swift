//
//  HotkeyManager.swift
//  LXFinderLauncher
//
//  Created by 启业云03 on 2026/9/1.
//

import AppKit
import Carbon.HIToolbox
import Combine

/// 全局快捷键管理：基于 Carbon RegisterEventHotKey，系统级独占注册。
///
/// - 无需任何 TCC 授权；
/// - `EventHotKeyRef` / `EventHandlerRef` 必须强持有，丢失引用会导致热键静默失效；
/// - C 回调不能捕获 self，通过 userData（Unmanaged）传入对象；
/// - 回调在主线程 Carbon 事件循环触发，内部再派发到 MainActor。
@MainActor
final class HotkeyManager: ObservableObject {

    static let shared = HotkeyManager()

    /// 热键触发回调（统一转发到 AppCommands）。
    var onTrigger: (() -> Void)?

    /// 最近一次注册结果，供设置页提示「组合键被占用 / 注册失败」。
    @Published private(set) var registerFailed = false

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private static let signature: OSType = 0x464C5448 // 'FLTH'

    private init() {}

    /// 注册全局热键。keyCode / modifiers 为 Carbon 值（见 KeycodeTable / HotkeyRecorder）。
    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32, id: UInt32 = 1) -> Bool {
        unregister()
        let target = GetApplicationEventTarget()

        // 事件处理器只安装一次。
        if handlerRef == nil {
            var spec = EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: OSType(kEventHotKeyPressed)
            )
            InstallEventHandler(target, { _, event, userData in
                guard let event, let userData else { return noErr }
                // 读回热键 ID（v1 单热键，此处仅保留机制）。
                var hotKeyID = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                  EventParamType(typeEventHotKeyID), nil,
                                  MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                Task { @MainActor in
                    manager.onTrigger?()
                }
                return noErr
            }, 1, &spec,
            Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
        }

        var hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, target, 0, &hotKeyRef)
        let ok = status == noErr
        // 记录结果供设置页提示（失败通常是组合键被其它 App 占用）。
        registerFailed = !ok
        return ok
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    /// 从 UserDefaults 读取热键配置并（重）注册。
    func applySettings() {
        guard UserDefaults.standard.bool(forKey: "hotkeyEnabled") else {
            unregister()
            return
        }
        let keyCode = UInt32(UserDefaults.standard.integer(forKey: "hotkeyKeyCode"))
        let modifiers = UInt32(UserDefaults.standard.integer(forKey: "hotkeyModifiers"))
        let ok = register(keyCode: keyCode, modifiers: modifiers)
        if !ok {
            print("[LXFinderLauncher] 热键注册失败：组合键可能被其他 App 占用。")
        }
    }
}

//
//  HotkeyRecorder.swift
//  LXFinderLauncher
//
//  Created by 启业云03 on 2026/9/1.
//

import AppKit
import Combine
import Carbon.HIToolbox

/// 录制一个新的组合键：监听本地键盘事件，映射为 (keyCode, carbonModifiers)。
@MainActor
final class HotkeyRecorder: ObservableObject {

    /// 当前正在录哪个热键；nil 表示没在录。
    @Published private(set) var recordingTarget: GlobalHotkey?

    /// 录制完成回调：(哪个热键, keyCode, carbonModifiers)，后两者为 Carbon 值。
    var onRecorded: ((GlobalHotkey, UInt32, UInt32) -> Void)?

    private var monitor: Any?

    var isRecording: Bool { recordingTarget != nil }

    /// 开始录制指定热键。
    ///
    /// 只注销**正在录的那一个**，另一个热键保持可用。取舍：录制 A 时用户若按下 B 的组合键，
    /// 不会被录进去（Carbon 已经把它变成 hot key 事件，本地 NSEvent 监听器看不到），
    /// 而是真的执行 B 的动作——对「创建文件」热键意味着录制中可能凭空多出一个文件。
    /// 这是有意选的：另一种做法是录制期间全注销，代价是录制中途崩溃会让两个热键都静默失效。
    func begin(_ hotkey: GlobalHotkey) {
        guard recordingTarget == nil else { return }
        recordingTarget = hotkey
        HotkeyManager.shared.unregister(hotkey)

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else {
                // self 已释放（录制中设置窗口被关掉）。这里没法再去清 monitor，
                // 但必须把事件**放行**：本地监听器返回 nil 在 AppKit 里等于吞掉这个按键，
                // 返回 nil 会变成一个吞掉全 App 所有按键的孤儿监听器。
                return event
            }
            let keyCode = UInt32(event.keyCode)
            // 纯修饰键按下无意义，忽略。
            if Self.isModifierKeyCode(keyCode) { return nil }

            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let carbon = Self.carbonModifiers(from: flags)
            guard carbon != 0 else { return nil }   // 拒绝无修饰键的裸按键

            self.finish(hotkey: hotkey, keyCode: keyCode, carbonModifiers: carbon)
            return nil                              // 吞掉该按键
        }
    }

    /// 放弃录制：移除监听，并把录制开始时注销掉的全局热键按当前设置注册回来。
    ///
    /// 必须有这条路径：`begin(_:)` 会先注销那个热键，而收尾只靠 `finish(...)`（录制成功才调）。
    /// 少了它，用户点了录制又直接关掉设置窗口，热键就再也不会被注册回来——快捷键静默失效。
    func cancel() {
        removeMonitor()
        guard recordingTarget != nil else { return }
        recordingTarget = nil
        HotkeyManager.shared.applySettings()
    }

    private func finish(hotkey: GlobalHotkey, keyCode: UInt32, carbonModifiers: UInt32) {
        removeMonitor()
        recordingTarget = nil
        onRecorded?(hotkey, keyCode, carbonModifiers)
    }

    private func removeMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    deinit {
        // 兜底：正常路径由 finish(...) / cancel() 收尾，这里防的是两者都没走到的漏网情况。
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    // MARK: - 辅助

    private static func isModifierKeyCode(_ keyCode: UInt32) -> Bool {
        switch keyCode {
        case UInt32(kVK_Command), UInt32(kVK_Shift), UInt32(kVK_Option),
             UInt32(kVK_Control), UInt32(kVK_RightCommand), UInt32(kVK_RightShift),
             UInt32(kVK_RightOption), UInt32(kVK_RightControl),
             UInt32(kVK_CapsLock), UInt32(kVK_Function):
            return true
        default:
            return false
        }
    }

    /// NSEvent.ModifierFlags → Carbon 位（cmdKey/shiftKey/optionKey/controlKey）。
    private static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var carbon: UInt32 = 0
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        return carbon
    }
}

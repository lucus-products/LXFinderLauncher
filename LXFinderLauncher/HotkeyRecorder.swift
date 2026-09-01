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

    @Published var isRecording = false

    /// 录制完成回调：(keyCode, carbonModifiers)，均为 Carbon 值。
    var onRecorded: ((UInt32, UInt32) -> Void)?

    private var monitor: Any?

    /// 开始录制。录制期间临时注销现有热键，避免自触发。
    func begin() {
        guard !isRecording else { return }
        isRecording = true
        HotkeyManager.shared.unregister()

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return nil }
            let keyCode = UInt32(event.keyCode)
            // 纯修饰键按下无意义，忽略。
            if Self.isModifierKeyCode(keyCode) { return nil }

            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let carbon = Self.carbonModifiers(from: flags)
            guard carbon != 0 else { return nil }   // 拒绝无修饰键的裸按键

            self.finish(keyCode: keyCode, carbonModifiers: carbon)
            return nil                              // 吞掉该按键
        }
    }

    private func finish(keyCode: UInt32, carbonModifiers: UInt32) {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        isRecording = false
        onRecorded?(keyCode, carbonModifiers)
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

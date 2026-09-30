//
//  HotkeyManager.swift
//  LXFinderLauncher
//
//  Created by 启业云03 on 2026/9/1.
//

import AppKit
import Carbon.HIToolbox
import Combine

// MARK: - 热键标识

/// Carbon 热键的签名，用来把本 App 注册的热键和同一个 target 上别人注册的热键区分开。
///
/// 放在文件级而不是 `HotkeyManager` 里：Carbon 的事件回调是 nonisolated 的 C 闭包，
/// 访问 MainActor 隔离的 static 属性编译不过。
private let hotkeySignature: OSType = 0x464C5448 // 'FLTH'

/// Carbon 事件回调的返回值。
///
/// 这两个常量在 Swift 里被导入成 `Int`，而 `InstallEventHandler` 的回调要求返回 `OSStatus`，
/// 必须显式转换。语义上：**返回任何不是 `notHandled` 的值都会终止事件传递**，
/// 所以「不是本 App 的热键」必须返回 `notHandled` 放行。
private let hotkeyHandled = OSStatus(noErr)
private let hotkeyNotHandled = OSStatus(eventNotHandledErr)

/// 一个组合键，用于检测两个热键被配成了同一个。
struct KeyCombo: Hashable {
    let keyCode: Int
    let modifiers: Int
}

/// 一个可配置的全局热键。
enum GlobalHotkey: UInt32, CaseIterable, Identifiable {

    case openTerminal = 1
    case createFile = 2

    /// 追加在末尾而不是插在中间：`allCases` 的顺序就是撞车时的优先级
    /// （见 `HotkeyManager.applySettings`），插到前面会改变现有两个热键的归属。
    case openEditor = 3
    case copyPath = 4

    var id: UInt32 { rawValue }

    var title: String {
        switch self {
        case .openTerminal: return "打开终端"
        case .createFile: return "创建文件"
        case .openEditor: return "用编辑器打开"
        case .copyPath: return "复制当前目录路径"
        }
    }

    /// UserDefaults 键前缀。
    ///
    /// `openTerminal` 必须沿用 "hotkey" 这个旧前缀，**不要**改成对称的 "openTerminalHotkey"——
    /// 改了等于让老用户已经录好的组合键丢失。
    var keyPrefix: String {
        switch self {
        case .openTerminal: return "hotkey"
        case .createFile: return "createFileHotkey"
        case .openEditor: return "openEditorHotkey"
        case .copyPath: return "copyPathHotkey"
        }
    }

    /// 出厂默认组合键。
    var defaultKeyCode: Int {
        switch self {
        case .openTerminal: return kVK_ANSI_T
        case .createFile: return kVK_ANSI_N
        case .openEditor: return kVK_ANSI_E
        case .copyPath: return kVK_ANSI_C
        }
    }

    /// 创建文件用 ⌃⌥⌘N 而**不是** ⌥⌘N：后者是 Finder 的「新建智能文件夹」，
    /// 而 Finder 恰好是这个功能唯一的使用场景——绑上去要么让用户从此用不了 Finder 的
    /// 新建智能文件夹，要么在 Finder 前台时热键不触发（菜单快捷键被前台 App 先消费），
    /// 两边都不划算。三修饰键组合也基本没有 App 会占用。
    ///
    /// 后加的「用编辑器打开」「复制路径」沿用同一套 ⌃⌥⌘ + 字母，理由相同：
    /// 这两个动作同样只在 Finder 前台时才有人按，两修饰键的组合很容易撞上 Finder 自己的菜单快捷键。
    var defaultModifiers: Int {
        switch self {
        case .openTerminal: return cmdKey | shiftKey
        case .createFile: return controlKey | optionKey | cmdKey
        case .openEditor: return controlKey | optionKey | cmdKey
        case .copyPath: return controlKey | optionKey | cmdKey
        }
    }

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: keyPrefix + "Enabled") }
        nonmutating set { UserDefaults.standard.set(newValue, forKey: keyPrefix + "Enabled") }
    }

    var keyCode: Int {
        get { UserDefaults.standard.integer(forKey: keyPrefix + "KeyCode") }
        nonmutating set { UserDefaults.standard.set(newValue, forKey: keyPrefix + "KeyCode") }
    }

    var modifiers: Int {
        get { UserDefaults.standard.integer(forKey: keyPrefix + "Modifiers") }
        nonmutating set { UserDefaults.standard.set(newValue, forKey: keyPrefix + "Modifiers") }
    }

    var combo: KeyCombo { KeyCombo(keyCode: keyCode, modifiers: modifiers) }

    /// 组合键是否只含 ⌥（含 ⌥⇧、以及光秃秃的 ⌥）。
    var isOptionOnly: Bool { Self.isOptionOnly(modifiers: modifiers) }

    /// 见 `isOptionOnly`。拆成静态纯函数是为了能脱离 UserDefaults 单测。
    ///
    /// 有报告称 macOS 15 上这类全局热键会整体失效（FB15168205）。只用来给设置页加一句提示，
    /// 不据此禁用——用户能用的配置不该被静默改掉。
    static func isOptionOnly(modifiers: Int) -> Bool {
        let optionAndShiftOnly = optionKey | shiftKey
        return modifiers & optionKey != 0 && modifiers & ~optionAndShiftOnly == 0
    }

    /// 注册全部热键的出厂默认值。**必须在读取任何热键配置之前调用**（App 启动时）。
    ///
    /// 不注册会出两类问题，都是因为 `@AppStorage` 只把默认值写在自己的属性包装器里、
    /// **不会写进 UserDefaults**（本机 plist 里 `autoCheckUpdates` 就不存在），
    /// 而 `HotkeyManager` 是直接读 UserDefaults 的：
    ///
    /// - `bool(forKey:)` 读到 `false` → 默认热键根本注册不上，但设置页的开关因为
    ///   `@AppStorage` 自带的默认参数而显示「已启用」，用户看到的是「开了却没反应」；
    /// - `integer(forKey:)` 读到 `0` → `0` 是 `kVK_ANSI_A`，一旦 enabled 判成 true
    ///   就会**全局劫持字母 A**。
    static func registerDefaults() {
        var defaults: [String: Any] = [:]
        for hotkey in GlobalHotkey.allCases {
            defaults[hotkey.keyPrefix + "Enabled"] = true
            defaults[hotkey.keyPrefix + "KeyCode"] = hotkey.defaultKeyCode
            defaults[hotkey.keyPrefix + "Modifiers"] = hotkey.defaultModifiers
        }
        UserDefaults.standard.register(defaults: defaults)
    }
}

/// 某个热键最近一次的注册结果。
enum GlobalHotkeyStatus: Equatable {
    /// 用户在设置里关掉了。
    case disabled
    /// 注册成功。
    case ok
    /// 与本 App 的另一个热键配成了同一组合。
    case duplicate(of: GlobalHotkey)
    /// 真·注册失败（系统保留，或被某个以独占方式注册的 App 占着）。
    case failed
}

// MARK: - 管理

/// 全局快捷键管理：基于 Carbon `RegisterEventHotKey`。
///
/// - 无需任何 TCC 授权，也是免授权方案里唯一能「吞掉」按键的（NSEvent 全局监听只能旁观、
///   CGEventTap 要辅助功能权限）；
/// - **不是系统级独占**：跨进程重复注册不会失败，两边都会收到通知，所以「注册成功」
///   并不等于「别的 App 收不到」。真正会注册失败的是同进程内重复注册
///   （`eventHotKeyExistsErr`）与系统保留组合键；
/// - `EventHotKeyRef` / `EventHandlerRef` 必须强持有，丢失引用会导致热键静默失效；
/// - C 回调不能捕获 self，通过 userData（Unmanaged）传入对象；
/// - 回调在主线程 Carbon 事件循环触发，内部再派发到 MainActor。
@MainActor
final class HotkeyManager: ObservableObject {

    static let shared = HotkeyManager()

    /// 热键触发回调（统一转发到 AppCommands），参数是触发的那个热键。
    var onTrigger: ((GlobalHotkey) -> Void)?

    /// 每个热键最近一次的注册结果，供设置页逐行提示。
    @Published private(set) var status: [GlobalHotkey: GlobalHotkeyStatus] = [:]

    private var hotKeyRefs: [GlobalHotkey: EventHotKeyRef] = [:]
    private var handlerRef: EventHandlerRef?

    private init() {}

    /// 取某个热键的注册结果（没有记录时按「已关闭」处理）。
    func status(of hotkey: GlobalHotkey) -> GlobalHotkeyStatus {
        status[hotkey] ?? .disabled
    }

    /// 安装 Carbon 事件处理器。**全程只装一次**——装两次会让一次按键触发两次回调。
    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return hotkeyNotHandled }

            var hotKeyID = EventHotKeyID()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                    EventParamType(typeEventHotKeyID), nil,
                                    MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID) == noErr,
                  // signature 也要校验：否则同一 target 上别人注册的 id == 1 的热键
                  // 会被当成 openTerminal。
                  hotKeyID.signature == hotkeySignature,
                  let hotkey = GlobalHotkey(rawValue: hotKeyID.id)
            else {
                // 不是本 App 的热键，必须放行——无条件 return hotkeyHandled 会把同一个
                // target 上 AppKit/SwiftUI 内部注册的热键事件一并吞掉（见 hotkeyNotHandled 的说明）。
                return hotkeyNotHandled
            }

            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            Task { @MainActor in
                manager.onTrigger?(hotkey)
            }
            return hotkeyHandled
        }, 1, &spec,
        Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
    }

    /// 注册单个热键。keyCode / modifiers 为 Carbon 值（见 KeycodeTable / HotkeyRecorder）。
    @discardableResult
    func register(_ hotkey: GlobalHotkey, keyCode: UInt32, modifiers: UInt32) -> Bool {
        // 同一个组合键再注册一次会返回 eventHotKeyExistsErr(-9878)，所以先注销这个热键的旧注册。
        unregister(hotkey)
        installHandlerIfNeeded()

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: hotkeySignature, id: hotkey.rawValue)
        let ok = RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                                     GetApplicationEventTarget(), 0, &ref) == noErr

        // 失败时不要把旧的 ref 留在字典里，否则 unregister 会去注销一个已失效的引用。
        guard ok, let ref else { return false }
        hotKeyRefs[hotkey] = ref
        return true
    }

    /// 注销单个热键。
    func unregister(_ hotkey: GlobalHotkey) {
        if let ref = hotKeyRefs.removeValue(forKey: hotkey) {
            UnregisterEventHotKey(ref)
        }
    }

    /// 注销全部热键。
    func unregisterAll() {
        for hotkey in GlobalHotkey.allCases { unregister(hotkey) }
    }

    /// 从 UserDefaults 读取全部热键配置并（重）注册。
    ///
    /// 撞车检测在这里集中做，而不是在录制器里：撞车不止「录制」一条路径——用户可能把
    /// 终端热键录成创建文件热键的默认值，也可能手改 defaults。
    func applySettings() {
        var claimed: [KeyCombo: GlobalHotkey] = [:]
        var next: [GlobalHotkey: GlobalHotkeyStatus] = [:]

        // allCases 的顺序即优先级：openTerminal 在前，所以用户自己录过的那个
        // 会赢过新热键的出厂默认值，符合直觉。
        for hotkey in GlobalHotkey.allCases {
            guard hotkey.isEnabled else {
                unregister(hotkey)
                next[hotkey] = .disabled
                continue
            }

            let combo = hotkey.combo
            if let winner = claimed[combo] {
                // 两个热键配成了同一组合。同进程重复注册必然失败，但这和「被其它应用占用」
                // 是两回事——提示必须分开，否则用户会跑去换组合键，而真正该改的是另一个热键。
                unregister(hotkey)
                next[hotkey] = .duplicate(of: winner)
                continue
            }

            claimed[combo] = hotkey
            next[hotkey] = register(hotkey,
                                    keyCode: UInt32(combo.keyCode),
                                    modifiers: UInt32(combo.modifiers)) ? .ok : .failed
        }

        status = next
    }
}

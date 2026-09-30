//
//  MenuBarFeedback.swift
//  LXFinderLauncher
//
//  Created by 启业云03 on 2026/9/30.
//

import Combine
import Foundation

/// 菜单栏图标的瞬时反馈。
///
/// 有些操作成功后**没有任何可见结果**——尤其是「复制路径」：热键按下去、剪贴板换了内容，
/// 但屏幕上什么都不变，用户会怀疑热键坏了。让菜单栏图标闪一下就够：它一直在视野的固定
/// 位置，不需要新开窗口，也不打断当前操作。
///
/// 与 `HotkeyManager` 一样是共享单例：触发方在 `AppCommands`，展示方在 `MenuBarIconView`，
/// 两者之间没有别的引用通路。
@MainActor
final class MenuBarFeedback: ObservableObject {

    static let shared = MenuBarFeedback()

    /// 非 nil 时菜单栏图标临时换成这个 SF Symbol。nil = 显示正常图标。
    @Published private(set) var flashSymbol: String?

    /// 重置计时器。连续触发时用它取消上一次的复位，而不是把闪烁排队。
    private var resetTask: Task<Void, Never>?

    /// 闪烁时长。太短看不见，太长会让图标看起来像被改变了。
    private static let duration = Duration.milliseconds(700)

    private init() {}

    /// 让菜单栏图标闪一下。
    ///
    /// 连续调用只会延长这一次闪烁（重置计时），不会叠成两段——快速连按两次热键时
    /// 用户看到的应该是一次持续的反馈，而不是闪两下。
    func flash(_ symbol: String = "checkmark.circle.fill") {
        flashSymbol = symbol
        resetTask?.cancel()
        resetTask = Task { [weak self] in
            try? await Task.sleep(for: Self.duration)
            guard !Task.isCancelled else { return }
            self?.flashSymbol = nil
        }
    }
}

//
//  LXFinderLauncherTests.swift
//  LXFinderLauncherTests
//
//  Created by 启业云03 on 2026/9/1.
//

import Testing
import Carbon.HIToolbox
@testable import LXFinderLauncher

struct LXFinderLauncherTests {

    @Test func keyNameForLetter() {
        #expect(KeycodeTable.keyName(for: UInt32(kVK_ANSI_A)) == "A")
        #expect(KeycodeTable.keyName(for: UInt32(kVK_ANSI_T)) == "T")
    }

    @Test func keyNameForDigitAndFunction() {
        #expect(KeycodeTable.keyName(for: UInt32(kVK_ANSI_1)) == "1")
        #expect(KeycodeTable.keyName(for: UInt32(kVK_F5)) == "F5")
    }

    @Test func modifierString() {
        #expect(KeycodeTable.modifierString(carbon: UInt32(cmdKey | shiftKey)) == "⇧⌘")
        #expect(KeycodeTable.modifierString(carbon: UInt32(optionKey | controlKey)) == "⌃⌥")
        #expect(KeycodeTable.modifierString(carbon: 0) == "")
    }

    @Test func displayString() {
        #expect(KeycodeTable.displayString(keyCode: UInt32(kVK_ANSI_T),
                                           modifiers: UInt32(cmdKey | shiftKey)) == "⇧⌘T")
    }
}

// MARK: - 版本比较

struct UpdateCheckerTests {

    @Test func newer() {
        #expect(UpdateChecker.isNewer("1.1.0", than: "1.0.0"))
        #expect(UpdateChecker.isNewer("1.10.0", than: "1.9.9"))
        #expect(UpdateChecker.isNewer("2.0", than: "1.99.9"))
        #expect(UpdateChecker.isNewer("v1.2.0", than: "1.1.5"))
    }

    @Test func notNewer() {
        #expect(!UpdateChecker.isNewer("1.0.0", than: "1.1.0"))
        #expect(!UpdateChecker.isNewer("1.0.0", than: "1.0.0"))
        #expect(!UpdateChecker.isNewer("0.9", than: "1.0"))
    }
}

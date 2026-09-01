//
//  LXFinderLauncherUITests.swift
//  LXFinderLauncherUITests
//
//  Created by 启业云03 on 2026/9/1.
//

import XCTest

final class LXFinderLauncherUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 菜单栏 App：启动后不崩溃，进程存活。
    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.state == .runningForeground || app.state == .runningBackground)
    }
}

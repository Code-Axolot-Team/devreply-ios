import XCTest

/// SDK 0.4.4 against the example's in-process fake API (`DEVREPLY_STUB=1`, see StubAPI.swift): no account
/// needed. `present(category:message:attributes:)` prefills the composer and sends the context, events
/// arrive in order, the dark theme, and the remote off switch.
/// Screenshots also go to `TEST_RUNNER_DEVREPLY_SHOTS=<folder>` when set.
final class V044UITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(_ appearance: String, _ env: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["DEVREPLY_STUB"] = "1"
        app.launchEnvironment["DEVREPLY_APPEARANCE"] = appearance
        for (key, value) in env { app.launchEnvironment[key] = value }
        app.launch()
        // The config (and its on/off switch) arrives right after configure.
        sleep(1)
        return app
    }

    @MainActor
    private func composer(_ app: XCUIApplication) -> XCUIElement {
        app.textViews["devreply.composer"].exists ? app.textViews["devreply.composer"] : app.textFields["devreply.composer"]
    }

    /// present(category: .bug, message: "Prefilled text", attributes: ["source": "paywall"]).
    @MainActor
    func testPrefilledBugReportSendsContext() throws {
        let app = launch("light", ["DEVREPLY_PREFILL": "Prefilled text"])
        app.buttons["reportBug"].tap()

        let field = composer(app)
        XCTAssertTrue(field.waitForExistence(timeout: 10), "straight into a new bug report")
        XCTAssertEqual(field.value as? String, "Prefilled text", "the composer shows the app's text, not sent")
        XCTAssertFalse(app.staticTexts["Context received: source=paywall"].exists)
        shot(app, "ios-044-prefilled-light")

        app.buttons["devreply.send"].tap()
        XCTAssertTrue(app.staticTexts["Context received: source=paywall"].waitForExistence(timeout: 15),
                      "the context went with POST /v1/conversations")
        shot(app, "ios-044-sent-with-context-light")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Close"].tap()
        let log = app.staticTexts["eventLog"]
        let expected = "opened · started(bug) · sent · closed"
        let seen = NSPredicate(format: "label == %@", expected)
        expectation(for: seen, evaluatedWith: log)
        waitForExpectations(timeout: 5)
    }

    @MainActor
    func testPrefilledComposerDark() throws {
        let app = launch("dark", ["DEVREPLY_PREFILL": "Prefilled text"])
        app.buttons["reportBug"].tap()
        let field = composer(app)
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        XCTAssertEqual(field.value as? String, "Prefilled text")
        shot(app, "ios-044-prefilled-dark")
    }

    /// Home and a chat, light and dark (DevReply.darkTheme = .dark in the example).
    @MainActor
    func testHomeAndChatLightAndDark() throws {
        for appearance in ["light", "dark"] {
            let app = launch(appearance)
            app.buttons["openMessenger"].tap()
            XCTAssertTrue(app.buttons["devreply.start.bug"].waitForExistence(timeout: 10))
            let row = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Settings → Export'")).firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 10))
            sleep(1)
            shot(app, "ios-044-home-\(appearance)")
            row.tap()
            XCTAssertTrue(app.staticTexts["It includes every entry since you started."].waitForExistence(timeout: 10))
            sleep(1)
            shot(app, "ios-044-chat-\(appearance)")
            app.terminate()
        }
    }

    /// Every overlay in the themes: attach menu, image-free chat, the in-app banner and the unread bubble.
    /// Dark preset (dark appearance) and a custom light theme (blue header, orange accent).
    @MainActor
    func testOverlaysInThemes() throws {
        for (appearance, theme) in [("dark", "default"), ("light", "custom")] {
            let name = theme == "custom" ? "custom" : appearance
            let app = launch(appearance, ["DEVREPLY_THEME": theme, "DEVREPLY_STUB_REPLY_AFTER": "40"])
            app.buttons["openMessenger"].tap()
            let row = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Settings → Export'")).firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 10))
            sleep(1)
            shot(app, "ios-theme-home-\(name)")
            row.tap()
            XCTAssertTrue(app.staticTexts["It includes every entry since you started."].waitForExistence(timeout: 10))
            sleep(1)
            shot(app, "ios-theme-chat-\(name)")
            app.buttons["devreply.attach"].tap()
            XCTAssertTrue(app.buttons["Photo"].waitForExistence(timeout: 5))
            sleep(1)
            shot(app, "ios-theme-attach-menu-\(name)")
            app.buttons["Photo"].tap()
            sleep(3)
            shot(app, "ios-theme-photo-picker-\(name)")
            app.swipeDown(velocity: .fast)
            sleep(1)
            if app.buttons["Cancel"].exists { app.buttons["Cancel"].tap() }
            sleep(1)
            app.navigationBars.buttons.element(boundBy: 0).tap()
            app.buttons["Close"].tap()
            // The reply arrives 40 s after launch; the watcher looks every 30 s.
            let banner = app.buttons["devreply.banner"]
            XCTAssertTrue(banner.waitForExistence(timeout: 80), "in-app banner for the new reply")
            shot(app, "ios-theme-banner-bubble-\(name)")
            app.terminate()
        }
    }

    /// The team switched the chat off: present shows nothing and returns false.
    @MainActor
    func testSwitchedOffShowsNothing() throws {
        let app = launch("light", ["DEVREPLY_STUB_OFF": "1"])
        app.buttons["reportBug"].tap()
        XCTAssertTrue(app.buttons["Chat is switched off"].waitForExistence(timeout: 5), "present returned false")
        XCTAssertFalse(app.buttons["devreply.start.bug"].exists)
        XCTAssertFalse(composer(app).exists)
        shot(app, "ios-044-switched-off")
        app.terminate()
        // Back on (and the cached "off" is replaced by the next config).
        let again = launch("light")
        again.buttons["reportBug"].tap()
        XCTAssertTrue(composer(again).waitForExistence(timeout: 10))
    }

    /// Hebrew and Arabic (next release): the chat lays out from the right, the user's bubbles on the left,
    /// the back button on the right; the name form too. Screenshots for review.
    @MainActor
    func testRightToLeft() throws {
        let texts = [
            "he": ("אפשר לייצא את הנתונים שלי לגיליון?", "זה כולל כל רשומה מאז שהתחלתם."),
            "ar": ("هل يمكنني تصدير بياناتي كجدول بيانات؟", "يتضمن كل إدخال منذ أن بدأت."),
        ]
        for (lang, (mine, theirs)) in texts.sorted(by: { $0.key > $1.key }) {
            let app = launch("light", ["DEVREPLY_LOCALE": lang])
            app.buttons["openMessenger"].tap()
            XCTAssertTrue(app.buttons["devreply.start.bug"].waitForExistence(timeout: 10))
            sleep(1)
            shot(app, "ios-rtl-\(lang)-home")
            let row = app.buttons.containing(NSPredicate(format: "label CONTAINS 'CSV'")).firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 10))
            row.tap()
            let user = app.staticTexts[mine], team = app.staticTexts[theirs]
            XCTAssertTrue(team.waitForExistence(timeout: 10))
            sleep(1)
            // Right to left: the team speaks from the right, the user answers from the left.
            XCTAssertLessThan(user.frame.minX, team.frame.minX)
            shot(app, "ios-rtl-\(lang)-chat")
            app.terminate()

            let fresh = launch("light", ["DEVREPLY_LOCALE": lang, "DEVREPLY_STUB_NO_NAME": "1"])
            fresh.buttons["reportBug"].tap()
            sleep(2)
            shot(fresh, "ios-rtl-\(lang)-name")
            fresh.terminate()
        }
    }

    @MainActor
    private func shot(_ app: XCUIApplication, _ name: String) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["DEVREPLY_SHOTS"] {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }
}

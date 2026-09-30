import XCTest

/// The next release against the example's in-process fake API (`DEVREPLY_STUB=1`, see StubAPI.swift):
/// scrolling a full chat moves the chat, never the sheet; team replies in Markdown.
/// Screenshots also go to `TEST_RUNNER_DEVREPLY_SHOTS=<folder>` when set.
final class V050UITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private static let demoConversation = URL(string: "devreplyexample://devreply?devreply=0196f3a2-1111-7000-8000-000000000001")!

    @MainActor
    private func launch(_ appearance: String, _ env: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["DEVREPLY_STUB"] = "1"
        app.launchEnvironment["DEVREPLY_APPEARANCE"] = appearance
        for (key, value) in env { app.launchEnvironment[key] = value }
        app.launch()
        sleep(1)
        return app
    }

    /// The chat as a UIKit page sheet (`DevReply.handle(url)` → `presentMessenger`), the way a push, a link or
    /// `DevReply.present` opens it; or the SwiftUI sheet (`devReplyMessenger`) and the conversation row.
    @MainActor
    private func openDemoConversation(_ app: XCUIApplication, uikit: Bool) {
        if uikit {
            app.open(Self.demoConversation)
        } else {
            app.buttons["openMessenger"].tap()
            let row = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Settings → Export'")).firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 10))
            row.tap()
        }
    }

    /// A chat longer than the screen, in the page sheet: the newest message is in view on open; dragging the
    /// history up and down scrolls it, and the sheet (its bar) stays where it is, both ways.
    @MainActor
    func testScrollingAFullChatMovesTheChatNotTheSheet() throws {
        for uikit in [true, false] {
            let app = launch("light", ["DEVREPLY_STUB_LONG": "1", "DEVREPLY_SHEET_PROBE": "1"])
            openDemoConversation(app, uikit: uikit)
            let newest = app.staticTexts["It includes every entry since you started."]
            XCTAssertTrue(newest.waitForExistence(timeout: 10))
            sleep(2)
            let composer = app.buttons["devreply.send"]
            let bar = app.navigationBars.firstMatch
            let barFrame = bar.frame
            let window = app.windows.firstMatch.frame
            // Newest message in view on open, above the composer.
            XCTAssertTrue(newest.isHittable, "the newest message is in view on open")
            XCTAssertLessThan(newest.frame.maxY, composer.frame.minY)
            XCTAssertGreaterThan(newest.frame.minY, barFrame.maxY)
            shot(app, "ios-scroll-open-\(uikit ? "uikit" : "swiftui")")

            // The probe (StubAPI's SheetProbe) records how far the sheet moved during the drag: it springs back
            // when the finger lifts, so its frame afterwards proves nothing on its own.
            let probe = app.buttons["sheetProbe"]
            XCTAssertTrue(probe.waitForExistence(timeout: 5))
            XCTAssertEqual(probe.label, "sheet down 0 up 0", "the probe measures the settled sheet")
            let chat = app.windows.firstMatch
            func drag(_ from: CGFloat, _ to: CGFloat, _ file: StaticString = #filePath, _ line: UInt = #line) {
                let start = chat.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: from))
                let end = chat.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: to))
                start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .default, thenHoldForDuration: 0.3)
                sleep(1)
                XCTAssertEqual(probe.label, "sheet down 0 up 0", "the sheet stayed put during the drag", file: file, line: line)
            }

            // Finger up at the newest message: nothing newer, the sheet must not move or close.
            drag(0.7, 0.35)
            XCTAssertTrue(composer.exists, "the sheet is still open after dragging up at the newest message")
            XCTAssertEqual(bar.frame, barFrame, "the sheet didn't move")
            XCTAssertTrue(newest.isHittable)

            // Finger down: back through the history. The chat scrolls, the sheet stays.
            let before = newest.frame.minY
            drag(0.4, 0.75)
            XCTAssertTrue(composer.exists, "the sheet is still open after scrolling the history")
            XCTAssertEqual(bar.frame, barFrame, "the sheet didn't move")
            XCTAssertTrue(!newest.exists || newest.frame.minY > before + 100 || newest.frame.minY > window.maxY,
                          "the history scrolled down under the finger")
            shot(app, "ios-scroll-history-\(uikit ? "uikit" : "swiftui")")

            // Finger up again: towards the newest message. The chat scrolls, the sheet stays.
            let history = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'History message'")).allElementsBoundByIndex
                .filter(\.isHittable)
            let marker = try XCTUnwrap(history.last, "some of the history is in view")
            let markerLabel = marker.label
            let markerY = marker.frame.minY
            drag(0.7, 0.4)
            XCTAssertTrue(composer.exists)
            XCTAssertEqual(bar.frame, barFrame, "the sheet didn't move")
            let moved = app.staticTexts[markerLabel]
            XCTAssertTrue(!moved.exists || moved.frame.minY < markerY - 100, "the history scrolled up under the finger")
            app.terminate()
        }
    }

    /// A team reply in Markdown (the stub's reply and a longer one with every block), light, dark and Hebrew.
    /// The conversation list shows the reply's plain text, never `**`.
    @MainActor
    func testMarkdownReply() throws {
        let runs: [(appearance: String, lang: String?, preview: String, heading: String, bold: String)] = [
            ("dark", nil, "Yes: Settings → Export, then pick CSV.", "Export to a spreadsheet", "Yes: Settings → Export, then pick CSV."),
            ("light", "he", "כן: הגדרות ← ייצוא, ואז לבחור CSV.", "ייצוא לגיליון", "כן: הגדרות ← ייצוא, ואז לבחור CSV."),
            ("light", nil, "Yes: Settings → Export, then pick CSV.", "Export to a spreadsheet", "Yes: Settings → Export, then pick CSV."),
        ]
        for run in runs {
            var env = ["DEVREPLY_STUB_MARKDOWN": "1"]
            if let lang = run.lang { env["DEVREPLY_LOCALE"] = lang }
            let name = run.lang.map { "rtl-\($0)" } ?? run.appearance
            let app = launch(run.appearance, env)
            app.buttons["openMessenger"].tap()
            let row = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", run.preview)).firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 10), "the list's preview is the plain text")
            XCTAssertFalse(row.label.contains("**"))
            row.tap()
            XCTAssertTrue(app.staticTexts[run.bold].waitForExistence(timeout: 10), "the Markdown reply, formatted")
            let heading = app.staticTexts[run.heading]
            XCTAssertTrue(heading.waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS '**'")).count == 0, "no raw markers")
            sleep(1)
            shot(app, "ios-markdown-\(name)")
            if run.lang == "he" {
                // Right to left: the team's bubble (and the quote's bar) sit on the right.
                let window = app.windows.firstMatch.frame
                XCTAssertGreaterThan(heading.frame.midX, window.midX)
            }
            if run.appearance == "light", run.lang == nil {
                // Only the link opens the browser (last: Safari's back chip would show in later screenshots).
                let link = app.links["the guide"]
                XCTAssertTrue(link.waitForExistence(timeout: 5))
                link.tap()
                let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
                XCTAssertTrue(safari.wait(for: .runningForeground, timeout: 15), "the link opened in the browser")
            }
            app.terminate()
        }
    }

    /// A team question with answers as buttons, light, dark and Hebrew: the list previews its plain text; a tap
    /// sends the label with `answer` (the fake team echoes the question and option it got), the chosen button
    /// stays selected, the others go quiet and can't be tapped, and the composer stays.
    @MainActor
    func testButtonReplies() throws {
        let question = "0196f3a2-1111-7000-8000-0000000000b1"
        let runs: [(appearance: String, lang: String?, preview: String, chosen: String)] = [
            ("light", nil, "Did that solve it?", "Not quite"),
            ("dark", nil, "Did that solve it?", "Not quite"),
            ("light", "he", "זה פתר את זה?", "לא לגמרי"),
        ]
        for run in runs {
            var env = ["DEVREPLY_STUB_BUTTONS": "1"]
            if let lang = run.lang { env["DEVREPLY_LOCALE"] = lang }
            let name = run.lang.map { "rtl-\($0)" } ?? run.appearance
            let app = launch(run.appearance, env)
            app.buttons["openMessenger"].tap()
            let row = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", run.preview)).firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 10), "the list's preview is the question's plain text")
            XCTAssertFalse(row.label.contains("**"))
            row.tap()

            let options = ["o1", "o2", "o3"].map { app.buttons["devreply.option.\($0)"] }
            XCTAssertTrue(options[1].waitForExistence(timeout: 10), "the question's buttons")
            XCTAssertTrue(options.allSatisfy { $0.isEnabled && !$0.isSelected }, "unanswered: all can be tapped")
            XCTAssertEqual(options[1].label, run.chosen)
            sleep(1)
            shot(app, "ios-buttons-\(name)-question")
            if run.lang == "he" {
                // Right to left: the team's question and its buttons sit on the right.
                XCTAssertGreaterThan(options[1].frame.midX, app.windows.firstMatch.frame.midX)
            }

            options[1].tap()
            // The fake team echoes the `answer` from the POST body: this question, this option.
            let echo = app.staticTexts["Answer received: o2 for \(question)"]
            XCTAssertTrue(echo.waitForExistence(timeout: 10), "the sent body carried the answer")
            XCTAssertTrue(app.staticTexts[run.chosen].waitForExistence(timeout: 5), "the label went as the user's message")
            XCTAssertTrue(options[1].isSelected, "the chosen button stays highlighted")
            XCTAssertFalse(options[0].isEnabled, "the others go quiet")
            XCTAssertFalse(options[2].isEnabled)
            XCTAssertFalse(options[0].isSelected || options[2].isSelected)
            // The composer stays: the user can always type instead.
            let composer = app.descendants(matching: .any)["devreply.composer"]
            XCTAssertTrue(composer.exists && composer.isEnabled)
            sleep(3) // one poll: the answer still shows after the thread reloads from the server
            XCTAssertTrue(options[1].isSelected)
            shot(app, "ios-buttons-\(name)-answered")
            app.terminate()
        }
    }

    /// Answered on another device first: the server answers 409, the chat reloads and shows that answer.
    @MainActor
    func testButtonAlreadyAnsweredReloads() throws {
        let app = launch("light", ["DEVREPLY_STUB_BUTTONS": "409"])
        app.open(Self.demoConversation)
        let tapped = app.buttons["devreply.option.o2"]
        XCTAssertTrue(tapped.waitForExistence(timeout: 10))
        tapped.tap()
        let other = app.buttons["devreply.option.o1"]
        XCTAssertTrue(other.wait(for: \.isSelected, toEqual: true, timeout: 10), "the answer from the other device")
        XCTAssertFalse(tapped.isSelected)
        XCTAssertFalse(tapped.isEnabled)
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'Answer received'")).firstMatch.exists)
        shot(app, "ios-buttons-409")
        app.terminate()
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

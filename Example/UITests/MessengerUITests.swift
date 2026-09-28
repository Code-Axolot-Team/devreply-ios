import XCTest

/// Drives the real messenger against the live API: open → start a bug report → send → see it delivered.
final class MessengerUITests: XCTestCase {
    @MainActor
    func testSendMessageFromNativeMessenger() throws {
        let app = XCUIApplication()
        app.launch()
        snapshot(app, "1-app")

        app.buttons["openMessenger"].tap()
        let tile = app.buttons["devreply.start.bug"]
        XCTAssertTrue(tile.waitForExistence(timeout: 15), "messenger home with start buttons")
        sleep(1)
        snapshot(app, "2-messenger-home")

        tile.tap()
        let composer = app.textFields["devreply.composer"].exists ? app.textFields["devreply.composer"] : app.textViews["devreply.composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        snapshot(app, "3-new-conversation")

        let text = "Test from the native iOS messenger (\(Date().formatted(date: .omitted, time: .standard)))"
        composer.typeText(text)
        app.buttons["devreply.send"].tap()
        XCTAssertTrue(app.staticTexts[text].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Not sent. Tap to retry."].waitForExistence(timeout: 3), "delivered")
        snapshot(app, "4-sent")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts[text].waitForExistence(timeout: 5), "listed under Your conversations")
        snapshot(app, "5-home-with-conversation")
    }

    /// Screens only, sends nothing: home, a new conversation, the attach button.
    @MainActor
    func testScreens() throws {
        let app = XCUIApplication()
        app.launch()
        snapshot(app, "s1-app")
        app.buttons["openMessenger"].tap()
        let tile = app.buttons["devreply.start.bug"]
        XCTAssertTrue(tile.waitForExistence(timeout: 15))
        snapshot(app, "s2-home")
        app.swipeUp()
        snapshot(app, "s3-home-scrolled")
        tile.tap()
        XCTAssertTrue(app.buttons["devreply.attach"].waitForExistence(timeout: 5))
        snapshot(app, "s4-new-conversation")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let existing = app.buttons.containing(NSPredicate(format: "label CONTAINS 'native iOS messenger'")).firstMatch
        if existing.waitForExistence(timeout: 5) {
            existing.tap()
            sleep(2)
            snapshot(app, "s5-conversation")
        }
    }

    /// Name first, then a message with a real photo through the system photo picker, delivered.
    /// Needs `TEST_RUNNER_DEVREPLY_TEST_PK` and at least one photo in the simulator's library.
    @MainActor
    func testNameThenPhotoMessage() throws {
        let env = ProcessInfo.processInfo.environment
        guard let pk = env["DEVREPLY_TEST_PK"] else { throw XCTSkip("DEVREPLY_TEST_PK not set") }
        let app = XCUIApplication()
        app.launchEnvironment["DEVREPLY_PK"] = pk
        app.launch()
        app.buttons["openMessenger"].tap()
        let tile = app.buttons["devreply.start.bug"]
        XCTAssertTrue(tile.waitForExistence(timeout: 15))
        tile.tap()

        // No composer until there's a name.
        let name = app.textFields["devreply.profile.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 10), "asks for a name first")
        XCTAssertFalse(app.textFields["devreply.composer"].exists || app.textViews["devreply.composer"].exists)
        snapshot(app, "n1-name-first")
        name.tap()
        name.typeText("Sim Tester")
        let email = app.textFields["devreply.profile.email"]
        email.tap()
        email.typeText("sim@example.com")
        app.buttons["devreply.profile.save"].tap()

        let composer = app.textFields["devreply.composer"].firstMatch.exists ? app.textFields["devreply.composer"] : app.textViews["devreply.composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 10), "composer after the name")
        composer.tap()
        composer.typeText("Screenshot of the crash")

        app.buttons["devreply.attach"].tap()
        let photoItem = app.buttons["Photo"]
        XCTAssertTrue(photoItem.waitForExistence(timeout: 5))
        photoItem.tap()
        // The system photo picker: pick the first photo, confirm.
        let firstPhoto = app.images.matching(identifier: "PXGGridLayout-Info").firstMatch
        XCTAssertTrue(firstPhoto.waitForExistence(timeout: 15), "photo picker shows the library")
        // The picker runs in another process: its cells aren't "hittable", so tap by coordinate.
        firstPhoto.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        sleep(1)
        for confirm in ["Done", "Add"] where app.buttons[confirm].exists && app.buttons[confirm].isEnabled {
            app.buttons[confirm].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            break
        }
        sleep(2)
        snapshot(app, "n2-photo-staged")

        app.buttons["devreply.send"].tap()
        XCTAssertTrue(app.staticTexts["Screenshot of the crash"].waitForExistence(timeout: 10))
        let failed = NSPredicate(format: "label CONTAINS 'Tap to retry'")
        let uploading = app.staticTexts["UPLOADING…"]
        XCTAssertTrue(uploading.waitForNonExistence(timeout: 30), "upload finishes")
        XCTAssertEqual(app.staticTexts.matching(failed).count, 0, "no send error")
        sleep(2)
        snapshot(app, "n3-photo-sent")
    }

    /// Part 1 of the pinned-to-bottom check: a conversation long enough to scroll.
    @MainActor
    func testSeedLongConversation() throws {
        let env = ProcessInfo.processInfo.environment
        guard let pk = env["DEVREPLY_TEST_PK"] else { throw XCTSkip("DEVREPLY_TEST_PK not set") }
        let app = XCUIApplication()
        app.launchEnvironment["DEVREPLY_PK"] = pk
        app.launch()
        app.buttons["openMessenger"].tap()
        let tile = app.buttons["devreply.start.question"]
        XCTAssertTrue(tile.waitForExistence(timeout: 15))
        tile.tap()
        let name = app.textFields["devreply.profile.name"]
        if name.waitForExistence(timeout: 5) {
            name.tap()
            name.typeText("Scroll Tester")
            app.buttons["devreply.profile.save"].tap()
        }
        let composer = app.textFields["devreply.composer"].exists ? app.textFields["devreply.composer"] : app.textViews["devreply.composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 10))
        for i in 1...12 {
            composer.tap()
            composer.typeText("Message number \(i) with enough words to take some room")
            app.buttons["devreply.send"].tap()
            XCTAssertTrue(app.staticTexts["Message number \(i) with enough words to take some room"].waitForExistence(timeout: 10))
        }
    }

    /// Part 2: after a pause (a time label appears above the new message), the new message is at the
    /// bottom and fully visible, with no scrolling by anyone.
    @MainActor
    func testNewMessageAfterPauseStaysAtTheBottom() throws {
        let env = ProcessInfo.processInfo.environment
        guard let pk = env["DEVREPLY_TEST_PK"] else { throw XCTSkip("DEVREPLY_TEST_PK not set") }
        let app = XCUIApplication()
        app.launchEnvironment["DEVREPLY_PK"] = pk
        app.launch()
        app.buttons["openMessenger"].tap()
        let existing = app.buttons.containing(
            NSPredicate(format: "label CONTAINS 'Message number 12' OR label CONTAINS 'Back after a break'")
        ).firstMatch
        XCTAssertTrue(existing.waitForExistence(timeout: 15))
        existing.tap()
        let twelve = app.staticTexts["Message number 12 with enough words to take some room"]
        XCTAssertTrue(twelve.waitForExistence(timeout: 10))
        snapshot(app, "p1-opened")

        let composer = app.textFields["devreply.composer"].exists ? app.textFields["devreply.composer"] : app.textViews["devreply.composer"]
        composer.tap()
        let text = "Back after a break \(Int(Date().timeIntervalSince1970) % 100_000)"
        composer.typeText(text)
        app.buttons["devreply.send"].tap()
        let fresh = app.staticTexts[text]
        XCTAssertTrue(fresh.waitForExistence(timeout: 10))
        sleep(2)
        XCTAssertTrue(fresh.isHittable, "the new message is on screen")
        let composerTop = composer.frame.minY
        XCTAssertLessThan(fresh.frame.maxY, composerTop, "and above the composer, not hidden under it")
        snapshot(app, "p2-after-pause")
    }

    /// Keyboard, like any good chat: with it up, the whole thread sits right above the composer (the
    /// newest message visible); a long drag down hides it. Uses the conversation seeded above.
    @MainActor
    func testKeyboardRaisesChatAndDragHidesIt() throws {
        let env = ProcessInfo.processInfo.environment
        guard let pk = env["DEVREPLY_TEST_PK"] else { throw XCTSkip("DEVREPLY_TEST_PK not set") }
        let app = XCUIApplication()
        app.launchEnvironment["DEVREPLY_PK"] = pk
        app.launch()
        app.buttons["openMessenger"].tap()
        let existing = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Message number'")).firstMatch
        XCTAssertTrue(existing.waitForExistence(timeout: 15))
        existing.tap()
        let last = app.staticTexts["Message number 12 with enough words to take some room"]
        XCTAssertTrue(last.waitForExistence(timeout: 10))
        let composer = app.textFields["devreply.composer"].exists ? app.textFields["devreply.composer"] : app.textViews["devreply.composer"]
        snapshot(app, "k1-closed")

        composer.tap()
        XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: 5), "keyboard up")
        sleep(1)
        let keyboardTop = app.keyboards.element.frame.minY
        XCTAssertLessThanOrEqual(composer.frame.maxY, keyboardTop + 1, "composer sits on the keyboard")
        XCTAssertTrue(last.isHittable, "newest message still visible")
        XCTAssertLessThan(last.frame.maxY, composer.frame.minY, "and right above the composer")
        XCTAssertGreaterThan(last.frame.maxY, composer.frame.minY - 120, "not left far up the screen")
        snapshot(app, "k2-keyboard")

        // A long drag down through the thread, as far as the keyboard: it goes away.
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95))
        from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.1)
        sleep(1)
        XCTAssertFalse(app.keyboards.element.exists, "a long drag down hides the keyboard")
        snapshot(app, "k3-dragged")

        // A short scroll up through the history keeps the keyboard.
        composer.tap()
        XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: 5))
        sleep(1)
        let up1 = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
        let up2 = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
        up1.press(forDuration: 0.05, thenDragTo: up2, withVelocity: .slow, thenHoldForDuration: 0.1)
        XCTAssertTrue(app.keyboards.element.exists, "a short drag that stops above the keyboard keeps it")
        snapshot(app, "k4-scrolled-history")
    }

    /// The same in a chat with little or nothing to scroll: an empty new conversation, then one message.
    @MainActor
    func testKeyboardHidesInShortChat() throws {
        let env = ProcessInfo.processInfo.environment
        guard let pk = env["DEVREPLY_TEST_PK"] else { throw XCTSkip("DEVREPLY_TEST_PK not set") }
        let app = XCUIApplication()
        app.launchEnvironment["DEVREPLY_PK"] = pk
        app.launch()
        app.buttons["openMessenger"].tap()
        let tile = app.buttons["devreply.start.idea"]
        XCTAssertTrue(tile.waitForExistence(timeout: 15))
        tile.tap()
        let composer = app.textFields["devreply.composer"].exists ? app.textFields["devreply.composer"] : app.textViews["devreply.composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 10))
        composer.tap()
        XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: 5), "keyboard up in an empty chat")
        sleep(1)
        snapshot(app, "ks1-empty-keyboard")
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95))
        from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.1)
        sleep(1)
        XCTAssertFalse(app.keyboards.element.exists, "drag hides it in an empty chat")

        composer.tap()
        let text = "One short idea \(Int(Date().timeIntervalSince1970) % 100_000)"
        composer.typeText(text)
        app.buttons["devreply.send"].tap()
        let sent = app.staticTexts[text]
        XCTAssertTrue(sent.waitForExistence(timeout: 10))
        sleep(1)
        XCTAssertTrue(app.keyboards.element.exists, "sending keeps the keyboard up")
        XCTAssertLessThan(sent.frame.maxY, composer.frame.minY, "the message sits right above the composer")
        XCTAssertGreaterThan(sent.frame.maxY, composer.frame.minY - 120)
        snapshot(app, "ks2-one-message")
        from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.1)
        sleep(1)
        XCTAssertFalse(app.keyboards.element.exists, "drag hides it with one message")
        XCTAssertTrue(sent.isHittable, "and the message is back at the bottom")
        snapshot(app, "ks3-one-message-dragged")
    }

    /// First message of a new request: "we got it" with the app's reply time under it, then the
    /// optional email card. Saving an email updates the notice; the next request doesn't ask again.
    @MainActor
    func testFirstMessageShowsReplyTimeAndAsksForEmail() throws {
        let env = ProcessInfo.processInfo.environment
        guard let pk = env["DEVREPLY_TEST_PK"] else { throw XCTSkip("DEVREPLY_TEST_PK not set") }
        let app = XCUIApplication()
        app.launchEnvironment["DEVREPLY_PK"] = pk
        app.launch()
        app.buttons["openMessenger"].tap()
        let tile = app.buttons["devreply.start.bug"]
        XCTAssertTrue(tile.waitForExistence(timeout: 15))
        tile.tap()
        let name = app.textFields["devreply.profile.name"]
        if name.waitForExistence(timeout: 5) {
            snapshot(app, "e0-name-form")
            name.tap()
            name.typeText("Ana")
            app.buttons["devreply.profile.save"].tap()
        }
        let composer = app.textFields["devreply.composer"].exists ? app.textFields["devreply.composer"] : app.textViews["devreply.composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 10))
        composer.tap()
        composer.typeText("The export button does nothing")
        app.buttons["devreply.send"].tap()

        let notice = app.descendants(matching: .any)["devreply.notice"]
        XCTAssertTrue(notice.waitForExistence(timeout: 10), "we got it, under the first message")
        XCTAssertTrue(notice.label.contains("Please allow up to 3 working days for a reply"), notice.label)
        let field = app.textFields["devreply.emailask.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "optional email card")
        sleep(1)
        snapshot(app, "e1-notice-and-email-ask")

        field.tap()
        field.typeText("not-an-email")
        app.buttons["devreply.emailask.save"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] 'email'")).firstMatch.waitForExistence(timeout: 5))
        field.clearAndType("ana@example.com")
        app.buttons["devreply.emailask.save"].tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 10), "card goes away once saved")
        let updated = NSPredicate(format: "label CONTAINS 'email you at ana@example.com'")
        XCTAssertTrue(app.descendants(matching: .any).matching(updated).firstMatch.waitForExistence(timeout: 5))
        snapshot(app, "e2-email-saved")

        // A second message and a new request: no more asking.
        composer.tap()
        composer.typeText("It happens on every export")
        app.buttons["devreply.send"].tap()
        XCTAssertFalse(field.waitForExistence(timeout: 3))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["devreply.start.question"].tap()
        composer.tap()
        composer.typeText("Another question")
        app.buttons["devreply.send"].tap()
        XCTAssertTrue(notice.waitForExistence(timeout: 10))
        XCTAssertFalse(field.waitForExistence(timeout: 3), "we have the email now")
        snapshot(app, "e3-next-request")
    }

    /// A reply while the app is open and the chat closed: the round DevReply button shows over the app
    /// with the count. A swipe hides it; after a relaunch it's back (the reply is still unread); a tap
    /// opens the reply, and once it's read the button is gone. A test script replies from the dashboard.
    @MainActor
    func testUnreadBubbleOpensTheReply() throws {
        let env = ProcessInfo.processInfo.environment
        guard let pk = env["DEVREPLY_TEST_PK"] else { throw XCTSkip("DEVREPLY_TEST_PK not set") }
        let nonce = env["DEVREPLY_TEST_NONCE"] ?? "0"
        let app = XCUIApplication()
        app.launchEnvironment["DEVREPLY_PK"] = pk
        app.launch()
        app.buttons["openMessenger"].tap()
        let tile = app.buttons["devreply.start.question"]
        XCTAssertTrue(tile.waitForExistence(timeout: 15))
        tile.tap()
        let name = app.textFields["devreply.profile.name"]
        if name.waitForExistence(timeout: 5) {
            name.tap()
            name.typeText("Bubble Tester")
            app.buttons["devreply.profile.save"].tap()
        }
        let composer = app.textFields["devreply.composer"].exists ? app.textFields["devreply.composer"] : app.textViews["devreply.composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 10))
        composer.tap()
        composer.typeText("Bubble test \(nonce)")
        app.buttons["devreply.send"].tap()
        XCTAssertTrue(app.staticTexts["Bubble test \(nonce)"].waitForExistence(timeout: 10))
        if app.buttons["devreply.emailask.skip"].exists { app.buttons["devreply.emailask.skip"].tap() }
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["Sheet Grabber"].waitForNonExistence(timeout: 5), "messenger closed")
        XCTAssertFalse(app.buttons["devreply.bubble"].exists, "nothing unread yet")

        let bubble = app.buttons["devreply.bubble"]
        XCTAssertTrue(bubble.waitForExistence(timeout: 90), "the reply shows up as the bubble")
        sleep(1)
        XCTAssertEqual(bubble.label, "New reply from \(env["DEVREPLY_TEST_TEAM"] ?? "Knee Coach")")
        XCTAssertGreaterThan(bubble.frame.midX, app.frame.width * 0.75, "bottom right")
        XCTAssertGreaterThan(bubble.frame.midY, app.frame.height * 0.6)
        XCTAssertTrue(app.buttons["openMessenger"].isHittable, "the app underneath still works")
        snapshot(app, "b1-bubble")

        let rowY = bubble.frame.midY / app.frame.height
        bubble.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: rowY)))
        XCTAssertTrue(bubble.waitForNonExistence(timeout: 3), "a swipe hides it")
        snapshot(app, "b2-swiped")

        app.terminate()
        app.launch()
        XCTAssertTrue(bubble.waitForExistence(timeout: 20), "still unread after a relaunch: back")
        bubble.tap()
        XCTAssertTrue(app.staticTexts["Founder reply \(nonce)"].waitForExistence(timeout: 15), "opens the reply")
        XCTAssertFalse(bubble.exists, "hidden while the chat is open")
        snapshot(app, "b3-opened")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["Sheet Grabber"].waitForNonExistence(timeout: 5), "messenger closed")
        sleep(2)
        XCTAssertFalse(bubble.exists, "read: gone")
        snapshot(app, "b4-read")
    }

    /// Push, allowed: soft ask after the first message → Apple's prompt → Allow → card gone. Then, with the
    /// chat closed, a push for this conversation (sent by the test script) shows DevReply's banner; tapping
    /// it opens the conversation. Needs `TEST_RUNNER_DEVREPLY_TEST_PK` and a fresh install.
    @MainActor
    func testPushAllowedThenBannerOpensConversation() throws {
        let app = try launchFresh()
        try startConversation(app, text: "Please notify me")
        let enable = app.buttons["devreply.push.enable"]
        XCTAssertTrue(enable.waitForExistence(timeout: 10), "asks after the first message")
        snapshot(app, "push1-ask")
        enable.tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons["Allow"]
        XCTAssertTrue(allow.waitForExistence(timeout: 10), "Apple's prompt")
        allow.tap()
        XCTAssertTrue(enable.waitForNonExistence(timeout: 10), "card goes once allowed")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Close"].tap()
        let banner = app.buttons["devreply.banner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 120), "in-app banner for the push")
        snapshot(app, "push2-banner")
        banner.tap()
        XCTAssertTrue(app.staticTexts["Please notify me"].waitForExistence(timeout: 10), "opens the conversation")
        snapshot(app, "push3-opened")
    }

    /// Push, denied: the card turns into "Open Settings".
    @MainActor
    func testPushDeniedOffersSettings() throws {
        let app = try launchFresh()
        try startConversation(app, text: "No notifications please")
        let enable = app.buttons["devreply.push.enable"]
        XCTAssertTrue(enable.waitForExistence(timeout: 10))
        enable.tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let deny = springboard.buttons["Don’t Allow"].exists ? springboard.buttons["Don’t Allow"] : springboard.buttons["Don't Allow"]
        XCTAssertTrue(deny.waitForExistence(timeout: 10))
        deny.tap()
        let settings = app.buttons["devreply.push.enable"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Notifications are off"].waitForExistence(timeout: 5))
        XCTAssertEqual(settings.label, "Open Settings")
        snapshot(app, "push4-denied")
        app.buttons["devreply.push.notnow"].tap()
        XCTAssertTrue(settings.waitForNonExistence(timeout: 5), "Not now hides it")
    }

    @MainActor
    private func launchFresh() throws -> XCUIApplication {
        guard let pk = ProcessInfo.processInfo.environment["DEVREPLY_TEST_PK"] else { throw XCTSkip("DEVREPLY_TEST_PK not set") }
        let app = XCUIApplication()
        app.launchEnvironment["DEVREPLY_PK"] = pk
        app.launch()
        return app
    }

    @MainActor
    private func startConversation(_ app: XCUIApplication, text: String) throws {
        app.buttons["openMessenger"].tap()
        let tile = app.buttons["devreply.start.bug"]
        XCTAssertTrue(tile.waitForExistence(timeout: 15))
        tile.tap()
        let name = app.textFields["devreply.profile.name"]
        if name.waitForExistence(timeout: 5) {
            name.tap()
            name.typeText("Push Tester")
            app.buttons["devreply.profile.save"].tap()
        }
        let composer = app.textFields["devreply.composer"].exists ? app.textFields["devreply.composer"] : app.textViews["devreply.composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 10))
        composer.tap()
        composer.typeText(text)
        app.buttons["devreply.send"].tap()
        XCTAssertTrue(app.staticTexts[text].waitForExistence(timeout: 10))
    }

    /// After the team resolved it: the conversation says "✓ Resolved" in the list and shows the line in the chat.
    @MainActor
    func testResolvedConversationInTheApp() throws {
        let app = try launchFresh()
        app.buttons["openMessenger"].tap()
        let chip = app.staticTexts["✓ Resolved"]
        XCTAssertTrue(chip.waitForExistence(timeout: 15), "resolved label in Your conversations")
        app.swipeUp()
        snapshot(app, "res1-list")
        app.buttons.containing(NSPredicate(format: "label CONTAINS 'Resolved'")).firstMatch.tap()
        let line = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH '✓ Marked as resolved'")).firstMatch
        XCTAssertTrue(line.waitForExistence(timeout: 10), "the resolved line in the chat")
        snapshot(app, "res2-chat")
    }

    /// Full loop with a person on the other end: needs `TEST_RUNNER_DEVREPLY_TEST_PK` and someone (or a script)
    /// replying "Founder reply <nonce>" from the dashboard within 90 seconds.
    @MainActor
    func testReceivesFounderReply() throws {
        let env = ProcessInfo.processInfo.environment
        guard let pk = env["DEVREPLY_TEST_PK"] else { throw XCTSkip("DEVREPLY_TEST_PK not set") }
        let app = XCUIApplication()
        app.launchEnvironment["DEVREPLY_PK"] = pk
        app.launch()
        app.buttons["openMessenger"].tap()
        let tile = app.buttons["devreply.start.question"]
        XCTAssertTrue(tile.waitForExistence(timeout: 15))
        tile.tap()
        let composer = app.textFields["devreply.composer"].exists ? app.textFields["devreply.composer"] : app.textViews["devreply.composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        let nonce = env["DEVREPLY_TEST_NONCE"] ?? "0"
        composer.typeText("Hello from the simulator \(nonce)")
        app.buttons["devreply.send"].tap()
        let reply = app.staticTexts["Founder reply \(nonce)"]
        XCTAssertTrue(reply.waitForExistence(timeout: 90), "founder reply arrives in the native chat")
        snapshot(app, "6-founder-reply")
    }

    @MainActor
    private func snapshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

extension XCUIElement {
    func clearAndType(_ text: String) {
        tap()
        if let value = value as? String, !value.isEmpty {
            typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count))
        }
        typeText(text)
    }
}

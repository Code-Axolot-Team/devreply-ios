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
        fillNameIfAsked(app)
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
        app.swipeDown() // with several conversations the tiles scroll out (and unload): back to the top
        XCTAssertTrue(tile.waitForExistence(timeout: 5))
        tile.tap()
        fillNameIfAsked(app)
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
        let existing = app.buttons.containing(
            NSPredicate(format: "label CONTAINS 'Message number' OR label CONTAINS 'Back after a break'")
        ).firstMatch
        XCTAssertTrue(app.buttons["devreply.start.bug"].waitForExistence(timeout: 15))
        for _ in 0..<5 where !(existing.exists && existing.isHittable) { app.swipeUp() }
        XCTAssertTrue(existing.waitForExistence(timeout: 5))
        existing.tap()
        // The newest message of the seeded chat (a later test may have added "Back after a break …").
        let seeded = NSPredicate(format: "label BEGINSWITH 'Message number' OR label BEGINSWITH 'Back after a break'")
        XCTAssertTrue(app.staticTexts.matching(seeded).firstMatch.waitForExistence(timeout: 10))
        sleep(1)
        let last = app.staticTexts.matching(seeded).allElementsBoundByIndex.max { $0.frame.maxY < $1.frame.maxY }!
        let composer = app.textFields["devreply.composer"].exists ? app.textFields["devreply.composer"] : app.textViews["devreply.composer"]
        snapshot(app, "k1-closed")

        closeAskCards(app)
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
        closeAskCards(app)
        if !app.keyboards.element.exists { composer.tap(); sleep(1) }
        // The first message, then the "we got it" notice under it, right above the composer.
        let notice = app.descendants(matching: .any)["devreply.notice"]
        XCTAssertLessThan(sent.frame.maxY, notice.frame.minY, "the message, then the notice")
        XCTAssertLessThan(notice.frame.maxY, composer.frame.minY, "the notice sits right above the composer")
        XCTAssertGreaterThan(notice.frame.maxY, composer.frame.minY - 60)
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

    /// Screenshots for devreply.com (not a check): one billing conversation from the user's side, while
    /// a script plays the developer in the dashboard. Runs only with DEVREPLY_TOUR=1 and a throwaway app's key.
    @MainActor
    func testWebsiteTour() throws {
        let env = ProcessInfo.processInfo.environment
        guard env["DEVREPLY_TOUR"] == "1", let pk = env["DEVREPLY_TEST_PK"] else { throw XCTSkip("DEVREPLY_TOUR not set") }
        let app = XCUIApplication()
        app.launchEnvironment["DEVREPLY_PK"] = pk
        app.launch()
        sleep(2)
        snapshot(app, "t1-app")

        app.buttons["openMessenger"].tap()
        let billing = app.buttons["devreply.start.billing"]
        XCTAssertTrue(billing.waitForExistence(timeout: 15))
        sleep(2)
        snapshot(app, "t2-home")

        billing.tap()
        let name = app.textFields["devreply.profile.name"]
        if name.waitForExistence(timeout: 5) {
            name.tap()
            name.typeText("Maya")
            app.buttons["devreply.profile.save"].tap()
        }
        let composer = app.textFields["devreply.composer"].exists ? app.textFields["devreply.composer"] : app.textViews["devreply.composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 10))
        composer.tap()
        composer.typeText("I paid for Pro but it's still locked. Can you help?")
        app.buttons["devreply.send"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["devreply.notice"].waitForExistence(timeout: 10))
        if app.buttons["devreply.emailask.skip"].waitForExistence(timeout: 3) { app.buttons["devreply.emailask.skip"].tap() }
        if app.buttons["devreply.push.notnow"].waitForExistence(timeout: 3) { app.buttons["devreply.push.notnow"].tap() }
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)))
        sleep(2)
        snapshot(app, "t3-sent")

        // Back to the app: the developer's reply shows up as the bubble (and the in-app banner).
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Close"].tap()
        let bubble = app.buttons["devreply.bubble"]
        XCTAssertTrue(bubble.waitForExistence(timeout: 180))
        sleep(1)
        snapshot(app, "t4-bubble")

        bubble.tap()
        let reply = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'So sorry'")).firstMatch
        XCTAssertTrue(reply.waitForExistence(timeout: 20))
        sleep(2)
        snapshot(app, "t5-reply")

        composer.tap()
        composer.typeText("It works now, thank you!")
        app.buttons["devreply.send"].tap()
        XCTAssertTrue(app.staticTexts["It works now, thank you!"].waitForExistence(timeout: 10))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)))
        let resolved = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH '✓ Marked as resolved'")).firstMatch
        XCTAssertTrue(resolved.waitForExistence(timeout: 180))
        sleep(2)
        snapshot(app, "t6-resolved")
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

    /// The cards that can sit between the thread and the composer on a fresh install (email ask,
    /// notifications ask): closed, so measurements are about the thread itself.
    @MainActor
    private func closeAskCards(_ app: XCUIApplication) {
        if app.buttons["devreply.emailask.skip"].exists { app.buttons["devreply.emailask.skip"].tap() }
        if app.buttons["devreply.push.notnow"].exists { app.buttons["devreply.push.notnow"].tap() }
        sleep(1)
    }

    // MARK: SDK 0.4: personas, app icon, team faces, deep links
    // A script plays the team: it waits for the conversation, replies as two personas ("Anna" twice,
    // then "Sergei"), and then runs part 2 with the conversation's id. Throwaway app only.

    /// Part 1: who replied shows once per group, and the home screen shows the team's faces.
    @MainActor
    func testPersonasPart1() throws {
        let env = ProcessInfo.processInfo.environment
        guard env["DEVREPLY_PERSONAS"] == "1", let pk = env["DEVREPLY_TEST_PK"] else { throw XCTSkip("DEVREPLY_PERSONAS not set") }
        let app = XCUIApplication()
        app.launchEnvironment["DEVREPLY_PK"] = pk
        app.launch()
        app.buttons["openMessenger"].tap()
        let tile = app.buttons["devreply.start.question"]
        XCTAssertTrue(tile.waitForExistence(timeout: 20))
        tile.tap()
        let name = app.textFields["devreply.profile.name"]
        if name.waitForExistence(timeout: 5) {
            name.tap()
            name.typeText("Mia")
            app.buttons["devreply.profile.save"].tap()
        }
        let composer = app.textFields["devreply.composer"].firstMatch.exists ? app.textFields["devreply.composer"] : app.textViews["devreply.composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 10))
        composer.tap()
        composer.typeText("How do I export my notes?")
        app.buttons["devreply.send"].tap()
        XCTAssertTrue(app.staticTexts["How do I export my notes?"].waitForExistence(timeout: 10))

        // The team answers: Anna twice, then Sergei. Two labels, not three.
        XCTAssertTrue(app.staticTexts["Sergei"].waitForExistence(timeout: 150), "the replies arrive")
        sleep(2)
        let labels = app.descendants(matching: .any).matching(identifier: "devreply.persona")
        XCTAssertEqual(labels.count, 2, "one label per group")
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label == 'Anna'")).count, 1, "Anna once for her two replies")
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label == 'Sergei'")).count, 1)
        // The email card and the keyboard away, to see the thread.
        if app.buttons["No thanks"].exists { app.buttons["No thanks"].tap() }
        app.staticTexts["How do I export my notes?"].swipeDown(velocity: .slow)
        sleep(2)
        snapshot(app, "ios04-thread")

        app.navigationBars.buttons.firstMatch.tap()
        let team = app.descendants(matching: .any)["devreply.team"]
        XCTAssertTrue(team.waitForExistence(timeout: 15), "the team's faces on the home screen")
        XCTAssertTrue(team.label.contains("Anna") && team.label.contains("Sergei"), team.label)
        sleep(2)
        snapshot(app, "ios04-home")
    }

    /// Part 2: the email button's deep link opens that conversation; an unknown one opens the home screen.
    @MainActor
    func testPersonasPart2DeepLink() throws {
        let env = ProcessInfo.processInfo.environment
        guard let pk = env["DEVREPLY_TEST_PK"], let cid = env["DEVREPLY_TEST_CID"] else { throw XCTSkip("DEVREPLY_TEST_CID not set") }
        let app = XCUIApplication()
        app.launchEnvironment["DEVREPLY_PK"] = pk
        app.launch()
        XCTAssertTrue(app.buttons["openMessenger"].waitForExistence(timeout: 10))

        XCUIDevice.shared.system.open(URL(string: "devreplyexample://devreply?devreply=\(UUID().uuidString.lowercased())")!)
        XCTAssertTrue(app.buttons["devreply.start.question"].waitForExistence(timeout: 20), "unknown conversation: the home screen")
        app.buttons["Close"].firstMatch.tap()
        sleep(2)

        XCUIDevice.shared.system.open(URL(string: "devreplyexample://devreply?devreply=\(cid)")!)
        XCTAssertTrue(app.staticTexts["How do I export my notes?"].waitForExistence(timeout: 20), "opens that conversation")
        XCTAssertTrue(app.staticTexts["Sergei"].waitForExistence(timeout: 10))
        sleep(2)
        snapshot(app, "ios04-deeplink")
    }

    /// A refused public key: with the messenger open (it refreshes every 10 s), registration is tried at
    /// 0 s and again after 1 min, not in a loop. The server log counts the attempts.
    @MainActor
    func testRefusedKeyBacksOff() throws {
        let env = ProcessInfo.processInfo.environment
        guard let pk = env["DEVREPLY_BACKOFF_PK"] else { throw XCTSkip("DEVREPLY_BACKOFF_PK not set") }
        let app = XCUIApplication()
        app.launchEnvironment["DEVREPLY_PK"] = pk
        app.launch()
        app.buttons["openMessenger"].tap()
        XCTAssertTrue(app.buttons["devreply.start.question"].waitForExistence(timeout: 15), "the messenger still opens")
        sleep(75)
        snapshot(app, "ios04-refused-key")
    }

    /// The chat asks for a name before the first message (spec 05) on a new install.
    @MainActor
    private func fillNameIfAsked(_ app: XCUIApplication) {
        let name = app.textFields["devreply.profile.name"]
        guard name.waitForExistence(timeout: 5) else { return }
        name.tap()
        name.typeText("Sim Tester")
        app.buttons["devreply.profile.save"].tap()
    }

    // MARK: Languages (spec 05): the chat in the app's chosen language, replies still arrive.

    /// Spanish: home, name form, composer, "we got it", and a team reply (a script answers as a persona,
    /// in Spanish, when it sees "Hola desde el simulador <nonce>"). Needs DEVREPLY_L10N=1.
    @MainActor
    func testChatInSpanish() throws {
        let env = ProcessInfo.processInfo.environment
        guard env["DEVREPLY_L10N"] == "1", let pk = env["DEVREPLY_TEST_PK"] else { throw XCTSkip("DEVREPLY_L10N not set") }
        let nonce = env["DEVREPLY_TEST_NONCE"] ?? "0"
        let app = XCUIApplication()
        app.launchEnvironment["DEVREPLY_PK"] = pk
        app.launchEnvironment["DEVREPLY_LOCALE"] = "es"
        app.launch()
        app.buttons["openMessenger"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '¡Hola!'")).firstMatch.waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["Inicia una conversación"].exists)
        XCTAssertTrue(app.staticTexts["Suele responder en 3 días hábiles"].exists, "the reply time, translated")
        XCTAssertTrue(app.buttons["devreply.start.bug"].label.contains("Algo no funciona"), app.buttons["devreply.start.bug"].label)
        sleep(2)
        snapshot(app, "ios-l10n-es-home")

        app.buttons["devreply.start.question"].tap()
        let name = app.textFields["devreply.profile.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label ==[c] 'Antes de empezar'")).firstMatch.exists)
        XCTAssertEqual(name.placeholderValue, "Tu nombre")
        name.tap()
        name.typeText("Mia")
        app.buttons["devreply.profile.save"].tap()
        let composer = app.textFields["devreply.composer"].firstMatch.exists ? app.textFields["devreply.composer"] : app.textViews["devreply.composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 10))
        XCTAssertEqual(composer.placeholderValue, "Mensaje…")
        composer.tap()
        composer.typeText("Hola desde el simulador \(nonce)")
        app.buttons["devreply.send"].tap()
        XCTAssertTrue(app.staticTexts["¡Gracias, lo recibimos!"].waitForExistence(timeout: 15))

        // The team answers (in Spanish, as a persona): it arrives under the persona's label.
        XCTAssertTrue(app.staticTexts["Te respondo en español \(nonce)"].waitForExistence(timeout: 150), "the reply arrives")
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "devreply.persona").count, 1)
        if app.buttons["No, gracias"].exists { app.buttons["No, gracias"].tap() }
        app.staticTexts["Hola desde el simulador \(nonce)"].swipeDown(velocity: .slow)
        sleep(2)
        snapshot(app, "ios-l10n-es-chat")
    }

    /// Japanese: the home screen and the chat's first screen, from the same launch setting.
    @MainActor
    func testHomeInJapanese() throws {
        let env = ProcessInfo.processInfo.environment
        guard env["DEVREPLY_L10N"] == "1", let pk = env["DEVREPLY_TEST_PK"] else { throw XCTSkip("DEVREPLY_L10N not set") }
        let app = XCUIApplication()
        app.launchEnvironment["DEVREPLY_PK"] = pk
        app.launchEnvironment["DEVREPLY_LOCALE"] = "ja"
        app.launch()
        app.buttons["openMessenger"].tap()
        XCTAssertTrue(app.staticTexts["会話を始める"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["あなたの会話"].waitForExistence(timeout: 20), "the Spanish run's conversation is listed")
        XCTAssertTrue(app.staticTexts["通常3営業日以内に返信します"].exists)
        sleep(2)
        snapshot(app, "ios-l10n-ja-home")
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

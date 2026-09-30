import XCTest

/// Live updates end to end (spec 05, "Live updates over WebSocket") against a real local server. Skipped
/// unless the runner gets (as `TEST_RUNNER_…` variables to xcodebuild):
///
/// - `DEVREPLY_LIVE_API`: the server, e.g. `http://127.0.0.1:8191`
/// - `DEVREPLY_LIVE_PK`: the project's iOS public key
/// - `DEVREPLY_LIVE_DASH_TOKEN`, `DEVREPLY_LIVE_PROJECT`: a dashboard token and the project id (team replies)
/// - `DEVREPLY_LIVE_MARKERS`: a folder shared with the script that stops and restarts the server: the test
///   writes `kill` and waits for `restarted` (the script sends a team reply while the app reconnects).
/// - `DEVREPLY_SHOTS`: where the screenshots go.
final class LiveUITests: XCTestCase {
    private var env: [String: String] { ProcessInfo.processInfo.environment }

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testTeamRepliesArriveLiveAndAfterAServerRestart() throws {
        guard let api = env["DEVREPLY_LIVE_API"], let pk = env["DEVREPLY_LIVE_PK"],
              let dash = env["DEVREPLY_LIVE_DASH_TOKEN"], let project = env["DEVREPLY_LIVE_PROJECT"],
              let markers = env["DEVREPLY_LIVE_MARKERS"] else {
            throw XCTSkip("needs a local server (DEVREPLY_LIVE_API …)")
        }
        let app = XCUIApplication()
        app.launchEnvironment["DEVREPLY_PK"] = pk
        app.launchEnvironment["DEVREPLY_API_URL"] = api
        app.launchEnvironment["DEVREPLY_APPEARANCE"] = "light"
        app.launch()

        app.buttons["openMessenger"].tap()
        let tile = app.buttons["devreply.start.bug"]
        XCTAssertTrue(tile.waitForExistence(timeout: 15))
        tile.tap()
        let name = app.textFields["devreply.profile.name"]
        if name.waitForExistence(timeout: 5) {
            name.tap()
            name.typeText("Live Tester")
            app.buttons["devreply.profile.save"].tap()
        }
        let composer = app.textFields["devreply.composer"].exists ? app.textFields["devreply.composer"] : app.textViews["devreply.composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 10))
        composer.tap()
        composer.typeText("Export is broken")
        app.buttons["devreply.send"].tap()
        XCTAssertTrue(app.staticTexts["Export is broken"].waitForExistence(timeout: 10))
        // Keyboard down, so the thread has room.
        app.swipeDown(velocity: .slow)
        shot(app, "live-0-conversation-open")

        let conversation = try latestConversation(api: api, dash: dash, project: project)

        // 1. A team reply shows up in the open chat within ~1 s (the 3 s poll is paused while the socket is live).
        sleep(2)
        let first = "Live reply \(Int(Date().timeIntervalSince1970) % 100_000)"
        let sentAt = Date()
        try teamReply(first, api: api, dash: dash, conversation: conversation)
        XCTAssertTrue(app.staticTexts[first].waitForExistence(timeout: 5))
        let latency = Date().timeIntervalSince(sentAt)
        shot(app, "live-1-reply-in-\(Int(latency * 1000))ms")
        XCTAssertLessThan(latency, 1.5, "arrived live, not by the 3 s poll")

        // 2. The server goes away and comes back; a reply sent while the app reconnects is delivered.
        try Data().write(to: URL(fileURLWithPath: markers).appendingPathComponent("kill"))
        let restarted = URL(fileURLWithPath: markers).appendingPathComponent("restarted")
        let deadline = Date().addingTimeInterval(90)
        while !FileManager.default.fileExists(atPath: restarted.path), Date() < deadline { usleep(200_000) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: restarted.path), "the script restarted the server")
        let meanwhile = (try? String(contentsOf: restarted, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        XCTAssertFalse(meanwhile.isEmpty)
        XCTAssertTrue(app.staticTexts[meanwhile].waitForExistence(timeout: 40), "the reply sent meanwhile")
        shot(app, "live-2-reply-sent-while-reconnecting")

        // 3. Live again after the reconnect: the next reply is instant too.
        sleep(20)
        let third = "Back live \(Int(Date().timeIntervalSince1970) % 100_000)"
        let thirdAt = Date()
        try teamReply(third, api: api, dash: dash, conversation: conversation)
        XCTAssertTrue(app.staticTexts[third].waitForExistence(timeout: 5))
        let latency3 = Date().timeIntervalSince(thirdAt)
        shot(app, "live-3-after-restart-reply-in-\(Int(latency3 * 1000))ms")
        XCTAssertLessThan(latency3, 1.5, "live again after the restart")
    }

    // MARK: Team side (the dashboard API)

    private func request(_ method: String, _ url: String, dash: String, body: [String: Any]? = nil) throws -> Any {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = method
        request.setValue("Bearer \(dash)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let done = expectation(description: url)
        nonisolated(unsafe) var result: (Data?, Int) = (nil, 0)
        URLSession.shared.dataTask(with: request) { data, response, _ in
            result = (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
            done.fulfill()
        }.resume()
        wait(for: [done], timeout: 10)
        XCTAssertTrue((200..<300).contains(result.1), "\(method) \(url): \(result.1)")
        return try JSONSerialization.jsonObject(with: result.0 ?? Data("null".utf8), options: .fragmentsAllowed)
    }

    private func latestConversation(api: String, dash: String, project: String) throws -> String {
        let list = try request("GET", "\(api)/dash/projects/\(project)/conversations", dash: dash) as? [[String: Any]] ?? []
        let id = list.first?["id"] as? String
        XCTAssertNotNil(id, "the conversation is in the inbox")
        return id ?? ""
    }

    private func teamReply(_ text: String, api: String, dash: String, conversation: String) throws {
        _ = try request("POST", "\(api)/dash/conversations/\(conversation)/messages", dash: dash, body: ["text": text])
    }

    @MainActor
    private func shot(_ app: XCUIApplication, _ name: String) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = env["DEVREPLY_SHOTS"] {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }
}

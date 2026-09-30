import Foundation

/// UI tests and screenshots without a DevReply account: with `DEVREPLY_STUB=1` in the launch environment the
/// example talks to this in-process fake of the public API instead of api.devreply.com. Never used otherwise.
/// `DEVREPLY_STUB_OFF=1` makes the fake answer as if the team switched the chat off.
/// `DEVREPLY_STUB_LONG=1` puts a long history before the demo conversation (more than a screen: scrolling).
/// `DEVREPLY_STUB_MARKDOWN=1` adds a longer team reply in Markdown (lists, code, a quote, a link) at the end.
/// `DEVREPLY_STUB_BUTTONS=1` ends the demo conversation with a team question with answers as buttons; the fake
/// team echoes the `answer` it got. `DEVREPLY_STUB_BUTTONS=409`: the question was already answered elsewhere
/// (the first answer gets 409, and the thread then shows the other answer).
final class StubAPI: URLProtocol, @unchecked Sendable {
    static let baseURL = URL(string: "https://stub.devreply.test")!

    static func install() {
        URLProtocol.registerClass(StubAPI.self)
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var started: [[String: Any]] = []
    /// Messages sent to the demo conversation, and the answers given (question id → option id).
    nonisolated(unsafe) private static var posted: [[String: Any]] = []
    nonisolated(unsafe) private static var answered: [String: String] = [:]

    private static let existingID = "0196f3a2-1111-7000-8000-000000000001"
    private static let newID = "0196f3a2-2222-7000-8000-000000000002"

    override class func canInit(with request: URLRequest) -> Bool { request.url?.host() == baseURL.host() }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let method = request.httpMethod ?? "GET"
        let path = request.url?.path() ?? ""
        let body = Self.body(of: request)
        let (status, json) = Self.answer(method, path, body)
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: json.map { try! JSONSerialization.data(withJSONObject: $0) } ?? Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    private static func body(of request: URLRequest) -> [String: Any] {
        var data = request.httpBody
        if data == nil, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var bytes = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let n = stream.read(&buffer, maxLength: buffer.count)
                if n <= 0 { break }
                bytes.append(buffer, count: n)
            }
            data = bytes
        }
        return data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
    }

    private static let now = Date()
    private static let launched = Date()

    private static func time(_ minutesAgo: Double) -> String {
        now.addingTimeInterval(-minutesAgo * 60).formatted(.iso8601)
    }

    private static func conversation(_ id: String, category: String, last: String, author: String, minutesAgo: Double) -> [String: Any] {
        ["id": id, "status": "open", "category": category, "last_text": last, "last_author": author, "unread": 0,
         "created_at": time(minutesAgo + 5), "last_message_at": time(minutesAgo)]
    }

    private static func message(_ id: String, _ author: String, _ text: String, minutesAgo: Double, persona: Bool = false) -> [String: Any] {
        message(id, author, blocks: [["type": "text", "text": text]], minutesAgo: minutesAgo, persona: persona)
    }

    private static func message(_ id: String, _ author: String, blocks: [[String: Any]], minutesAgo: Double, persona: Bool = false) -> [String: Any] {
        var m: [String: Any] = ["id": id, "author": author, "blocks": blocks, "created_at": time(minutesAgo)]
        if persona { m["persona"] = ["name": "Sergei", "title": "Developer"] }
        return m
    }

    /// A team reply in Markdown (spec 05, 0.5.0), as the server stores it. No `min_sdk` here, so this build
    /// shows it formatted (the real server sends `min_sdk: "0.5.0"`: until the release, the fallback).
    private static func markdown(_ text: String, fallback: String) -> [[String: Any]] {
        [["type": "markdown", "text": text, "fallback": fallback]]
    }

    /// `DEVREPLY_STUB_LONG=1`: a history longer than the screen, before the demo conversation.
    private static var history: [[String: Any]] {
        guard ProcessInfo.processInfo.environment["DEVREPLY_STUB_LONG"] == "1" else { return [] }
        return (1...30).map { n in
            let fromUser = n % 2 == 1
            let text = fromUser ? "History message \(n): the app crashed again when I opened the calendar."
                                : "History message \(n): thanks, we're looking at it."
            return message(String(format: "0196f3a2-1111-7000-8000-0000000010%02d", n), fromUser ? "user" : "admin", text,
                           minutesAgo: 400 - Double(n) * 2, persona: !fromUser)
        }
    }

    /// `DEVREPLY_STUB_MARKDOWN=1`: a longer reply with every Markdown block.
    private static var richReply: [[String: Any]] {
        guard ProcessInfo.processInfo.environment["DEVREPLY_STUB_MARKDOWN"] == "1" else { return [] }
        let hebrew = ProcessInfo.processInfo.environment["DEVREPLY_LOCALE"] == "he"
        let md = hebrew ? """
            ### ייצוא לגיליון
            שני צעדים, ~~חמישה~~ בלבד:

            1. פתחו את **הגדרות**
            2. הקישו על `ייצוא` ובחרו _CSV_

            - הקובץ נשמר ב-Files
            - אפשר גם לשתף אותו

            ```
            export --format csv
            ```

            > הייצוא כולל כל רשומה.

            עוד פרטים: [המדריך](https://devreply.com/docs)
            """ : """
            ### Export to a spreadsheet
            Two steps, not ~~five~~:

            1. Open **Settings**
            2. Tap `Export` and pick _CSV_

            - The file lands in Files
            - You can share it too

            ```
            export --format csv --since 2024-01-01 --include-archived-entries
            ```

            > It includes every entry since you started.

            More in [the guide](https://devreply.com/docs) or https://devreply.com/help.
            """
        let plain = hebrew ? "ייצוא לגיליון" : "Export to a spreadsheet"
        return [message("0196f3a2-1111-7000-8000-0000000000a4", "admin", blocks: markdown(md, fallback: plain), minutesAgo: 19, persona: true)]
    }

    private static let buttonsMode = ProcessInfo.processInfo.environment["DEVREPLY_STUB_BUTTONS"]
    static let questionID = "0196f3a2-1111-7000-8000-0000000000b1"

    /// `DEVREPLY_STUB_BUTTONS`: a team question with three answers, as the server stores it. No `min_sdk` here,
    /// so this build shows the buttons (the real server sends `min_sdk: "0.5.0"`: until the release, the fallback).
    private static var question: [[String: Any]] {
        guard buttonsMode != nil else { return [] }
        let options = [["id": "o1", "label": demo("Yes, all good")], ["id": "o2", "label": demo("Not quite")],
                       ["id": "o3", "label": demo("I need something else")]]
        let block: [String: Any] = ["type": "buttons", "text": demo("Did that **solve it**?"), "options": options,
                                    "fallback": demo("Did that solve it?")]
        return [message(questionID, "admin", blocks: [block], minutesAgo: 18, persona: true)]
    }

    /// The answer as the thread shows it: a user message whose block carries `answer`.
    private static func answerMessage(_ id: String, label: String, option: String, minutesAgo: Double) -> [String: Any] {
        message(id, "user", blocks: [["type": "text", "text": label, "answer": ["message_id": questionID, "option_id": option]]],
                minutesAgo: minutesAgo)
    }

    /// The demo conversation in the chat's language when `DEVREPLY_LOCALE` is he or ar (right-to-left screenshots).
    private static func demo(_ english: String) -> String {
        let texts: [String: [String: String]] = [
            "he": [
                "Can I export my data as a spreadsheet?": "אפשר לייצא את הנתונים שלי לגיליון?",
                "Yes: Settings → Export, then pick CSV.": "כן: הגדרות ← ייצוא, ואז לבחור CSV.",
                "Yes: **Settings → Export**, then pick `CSV`.": "כן: **הגדרות ← ייצוא**, ואז לבחור `CSV`.",
                "It includes every entry since you started.": "זה כולל כל רשומה מאז שהתחלתם.",
                "Found it: the export works again in 2.3.1.": "מצאנו: הייצוא עובד שוב בגרסה 2.3.1.",
                "Did that **solve it**?": "זה **פתר את זה**?",
                "Did that solve it?": "זה פתר את זה?",
                "Yes, all good": "כן, הכול טוב",
                "Not quite": "לא לגמרי",
                "I need something else": "אני צריך משהו אחר",
            ],
            "ar": [
                "Can I export my data as a spreadsheet?": "هل يمكنني تصدير بياناتي كجدول بيانات؟",
                "Yes: Settings → Export, then pick CSV.": "نعم: الإعدادات ← تصدير، ثم اختر CSV.",
                "Yes: **Settings → Export**, then pick `CSV`.": "نعم: **الإعدادات ← تصدير**، ثم اختر `CSV`.",
                "It includes every entry since you started.": "يتضمن كل إدخال منذ أن بدأت.",
                "Found it: the export works again in 2.3.1.": "وجدناها: التصدير يعمل مجددًا في الإصدار 2.3.1.",
            ],
        ]
        let lang = ProcessInfo.processInfo.environment["DEVREPLY_LOCALE"] ?? ""
        return texts[lang]?[english] ?? english
    }

    /// `DEVREPLY_STUB_BUTTONS=409`, after the refused tap: the answer given on another device.
    private static var answeredElsewhere: [[String: Any]] {
        guard buttonsMode == "409", lock.withLock({ answered[questionID] }) == "o1" else { return [] }
        return [answerMessage("0196f3a2-1111-7000-8000-0000000000b2", label: demo("Yes, all good"), option: "o1", minutesAgo: 1)]
    }

    private static func answer(_ method: String, _ path: String, _ body: [String: Any]) -> (Int, Any?) {
        let off = ProcessInfo.processInfo.environment["DEVREPLY_STUB_OFF"] == "1"
        var existing = buttonsMode == nil
            ? conversation(existingID, category: "question", last: demo("Yes: Settings → Export, then pick CSV."), author: "admin", minutesAgo: 20)
            // The list's preview of a question is its plain text, as the server writes it.
            : conversation(existingID, category: "question", last: demo("Did that solve it?"), author: "admin", minutesAgo: 18)
        // DEVREPLY_STUB_REPLY_AFTER=<seconds>: a new team reply arrives then (the in-app banner, the unread bubble).
        if let after = Double(ProcessInfo.processInfo.environment["DEVREPLY_STUB_REPLY_AFTER"] ?? ""), Date().timeIntervalSince(launched) > after {
            existing["unread"] = 1
            existing["last_text"] = demo("Found it: the export works again in 2.3.1.")
            existing["last_message_at"] = time(0)
        }
        switch (method, path) {
        case ("POST", "/v1/installs"):
            return (201, ["install_id": "0196f3a2-0000-7000-8000-00000000000a", "token": "it_stub"])
        case ("GET", "/v1/messenger/config"):
            return (200, [
                "app_name": "DevReply Demo", "team_name": "DevReply Demo", "greeting": "Hi there 👋",
                "intro": "Ask us anything, or tell us what's broken.",
                "reply_time": "Usually replies within a day", "reply_within": "a day", "reply_within_key": "day",
                "start_buttons": [["category": "bug", "emoji": "", "title": "Report a bug"],
                                  ["category": "billing", "emoji": "", "title": "Billing"],
                                  ["category": "idea", "emoji": "", "title": "Suggest an idea"],
                                  ["category": "question", "emoji": "", "title": "Ask a question"]],
                "localize": ["greeting", "intro", "start_buttons", "reply_time", "reply_within"],
                "enabled": !off,
            ])
        case ("GET", "/v1/conversations"):
            var list = [existing]
            if let first = lock.withLock({ started.first }) {
                list.insert(conversation(newID, category: first["category"] as? String ?? "other",
                                         last: first["text"] as? String ?? "", author: "user", minutesAgo: 0), at: 0)
            }
            return (200, list)
        case ("GET", "/v1/me"), ("PATCH", "/v1/me"):
            // DEVREPLY_STUB_NO_NAME=1: a user who hasn't given a name yet (the name form).
            if method == "GET", ProcessInfo.processInfo.environment["DEVREPLY_STUB_NO_NAME"] == "1" { return (200, ["email": NSNull()]) }
            return (200, ["name": "Sim Tester", "email": "sim@example.com"])
        case ("POST", "/v1/live"):
            // Live updates switched off: the chat polls, as against a server with LIVE_ENABLED=false.
            return (503, ["error": ["code": "unavailable", "message": "live updates are off right now: poll instead"]])
        case ("PATCH", "/v1/install"):
            return (200, ["push": false])
        case ("POST", "/v1/conversations"):
            lock.withLock { started.append(body) }
            let text = body["text"] as? String ?? ""
            return (201, [
                "conversation": conversation(newID, category: body["category"] as? String ?? "other", last: text, author: "user", minutesAgo: 0),
                "message": message("0196f3a2-2222-7000-8000-0000000000a1", "user", text, minutesAgo: 0),
            ])
        case ("GET", "/v1/conversations/\(existingID)/messages"):
            // The reply is Markdown (0.5.0); the list's preview is its plain text, as the server writes it.
            return (200, ["conversation": existing, "messages": history + [
                message("0196f3a2-1111-7000-8000-0000000000a1", "user", demo("Can I export my data as a spreadsheet?"), minutesAgo: 26),
                message("0196f3a2-1111-7000-8000-0000000000a2", "admin",
                        blocks: markdown(demo("Yes: **Settings → Export**, then pick `CSV`."), fallback: demo("Yes: Settings → Export, then pick CSV.")),
                        minutesAgo: 20, persona: true),
                message("0196f3a2-1111-7000-8000-0000000000a3", "admin", demo("It includes every entry since you started."), minutesAgo: 20, persona: true),
            ] + richReply + question + answeredElsewhere + lock.withLock { posted }])
        case ("GET", "/v1/conversations/\(newID)/messages"):
            let first = lock.withLock { started.first } ?? [:]
            let context = (first["context"] as? [String: Any] ?? [:]).map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ", ")
            return (200, ["conversation": conversation(newID, category: first["category"] as? String ?? "other",
                                                         last: first["text"] as? String ?? "", author: "user", minutesAgo: 0),
                          "messages": [
                              message("0196f3a2-2222-7000-8000-0000000000a1", "user", first["text"] as? String ?? "", minutesAgo: 0),
                              // The fake team echoes the context it got, so the UI test can see it arrived.
                              message("0196f3a2-2222-7000-8000-0000000000a2", "admin", "Context received: \(context.isEmpty ? "none" : context)", minutesAgo: 0),
                          ]])
        case ("POST", "/v1/conversations/\(existingID)/messages"):
            let text = body["text"] as? String ?? ""
            let id = UUID().uuidString.lowercased()
            guard let answer = body["answer"] as? [String: Any] else {
                let sent = message(id, "user", text, minutesAgo: 0)
                lock.withLock { posted.append(sent) }
                return (201, sent)
            }
            let question = answer["message_id"] as? String ?? ""
            let option = answer["option_id"] as? String ?? ""
            // One answer per question; in the 409 mode someone already answered on another device.
            let refused = lock.withLock { () -> Bool in
                if answered[question] != nil { return true }
                if buttonsMode == "409" { answered[question] = "o1"; return true }
                answered[question] = option
                return false
            }
            if refused { return (409, ["error": ["code": "already_answered", "message": "Already answered"]]) }
            let sent = answerMessage(id, label: text, option: option, minutesAgo: 0)
            lock.withLock {
                posted.append(sent)
                // The fake team echoes the answer it got, so the UI test can see it arrived.
                posted.append(message(UUID().uuidString.lowercased(), "admin", "Answer received: \(option) for \(question)", minutesAgo: 0))
            }
            return (201, sent)
        default:
            if method == "POST", path.hasSuffix("/messages") {
                return (201, message(UUID().uuidString.lowercased(), "user", body["text"] as? String ?? "", minutesAgo: 0))
            }
            return (204, nil)
        }
    }
}

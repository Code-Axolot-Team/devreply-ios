import Foundation

/// UI tests and screenshots without a DevReply account: with `DEVREPLY_STUB=1` in the launch environment the
/// example talks to this in-process fake of the public API instead of api.devreply.com. Never used otherwise.
/// `DEVREPLY_STUB_OFF=1` makes the fake answer as if the team switched the chat off.
final class StubAPI: URLProtocol, @unchecked Sendable {
    static let baseURL = URL(string: "https://stub.devreply.test")!

    static func install() {
        URLProtocol.registerClass(StubAPI.self)
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var started: [[String: Any]] = []

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
        var m: [String: Any] = ["id": id, "author": author, "blocks": [["type": "text", "text": text]], "created_at": time(minutesAgo)]
        if persona { m["persona"] = ["name": "Sergei", "title": "Developer"] }
        return m
    }

    private static func answer(_ method: String, _ path: String, _ body: [String: Any]) -> (Int, Any?) {
        let off = ProcessInfo.processInfo.environment["DEVREPLY_STUB_OFF"] == "1"
        var existing = conversation(existingID, category: "question", last: "Yes: Settings → Export, then pick CSV.", author: "admin", minutesAgo: 20)
        // DEVREPLY_STUB_REPLY_AFTER=<seconds>: a new team reply arrives then (the in-app banner, the unread bubble).
        if let after = Double(ProcessInfo.processInfo.environment["DEVREPLY_STUB_REPLY_AFTER"] ?? ""), Date().timeIntervalSince(launched) > after {
            existing["unread"] = 1
            existing["last_text"] = "Found it: the export works again in 2.3.1."
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
            return (200, ["name": "Sim Tester", "email": "sim@example.com"])
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
            return (200, ["conversation": existing, "messages": [
                message("0196f3a2-1111-7000-8000-0000000000a1", "user", "Can I export my data as a spreadsheet?", minutesAgo: 26),
                message("0196f3a2-1111-7000-8000-0000000000a2", "admin", "Yes: Settings → Export, then pick CSV.", minutesAgo: 20, persona: true),
                message("0196f3a2-1111-7000-8000-0000000000a3", "admin", "It includes every entry since you started.", minutesAgo: 20, persona: true),
            ]])
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
        default:
            if method == "POST", path.hasSuffix("/messages") {
                return (201, message(UUID().uuidString.lowercased(), "user", body["text"] as? String ?? "", minutesAgo: 0))
            }
            return (204, nil)
        }
    }
}

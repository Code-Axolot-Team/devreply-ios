import Foundation
import Testing
@testable import DevReply

// SDK 0.5.0: button replies (spec 05) and the device key (spec 03, "Same device after logout").

// MARK: - Button replies

@Suite struct ButtonRepliesTests {
    private func message(_ blocks: String, author: String = "admin", extra: String = "") throws -> Message {
        let json = """
        {"id":"01a0e892-b653-7191-9df9-c7e19fc68be7","author":"\(author)","created_at":"2026-09-30T10:00:00Z",\(extra)"blocks":[\(blocks)]}
        """
        return try APIClient.decoder.decode(Message.self, from: Data(json.utf8))
    }

    private let block = #"{"type":"buttons","text":"Why **cancel**?","options":[{"id":"o1","label":"Too expensive"},{"id":"o2","label":"Missing a feature"}],"fallback":"Why cancel?\n\n1. Too expensive\n2. Missing a feature\n\nReply with a number or in your own words."}"#

    /// Without `min_sdk` (the example's stub; any server once this SDK is 0.5.0): the question and its buttons.
    @Test func decodes() throws {
        let m = try message(block)
        guard case .buttons(let question, let plain, let options, let answered) = m.blocks.first else {
            Issue.record("\(m.blocks)")
            return
        }
        #expect(question == [.paragraph([MarkdownSpan(text: "Why "), MarkdownSpan(text: "cancel", bold: true), MarkdownSpan(text: "?")])])
        #expect(plain == "Why cancel?")
        #expect(options == [ButtonOption(id: "o1", label: "Too expensive"), ButtonOption(id: "o2", label: "Missing a feature")])
        #expect(answered == nil)
        #expect(m.plainText == "Why cancel?", "previews and banners use the question's plain text")
    }

    /// The real server marks it `min_sdk: "0.5.0"`: this build (0.4.4 until the release) shows the fallback.
    @Test func minSdkGatesTheBlock() throws {
        let gated = block.replacingOccurrences(of: #""type":"buttons","#, with: #""type":"buttons","min_sdk":"0.5.0","#)
        let m = try message(gated)
        if Block.isVersion(devReplySDKVersion, olderThan: "0.5.0") {
            guard case .unsupported(let fallback) = m.blocks.first else { Issue.record("\(m.blocks)"); return }
            #expect(fallback.hasPrefix("Why cancel?\n\n1. Too expensive"))
        } else {
            guard case .buttons = m.blocks.first else { Issue.record("\(m.blocks)"); return }
        }
    }

    @Test func badOptionsAreSkippedNoOptionsShowTheFallback() throws {
        let m = try message(#"{"type":"buttons","text":"Q","options":[{"id":"a","label":"A"},{"label":"no id"},{"id":"c","label":"  "},{"id":7,"label":"Seven"}],"fallback":"F"}"#)
        guard case .buttons(_, _, let options, _) = m.blocks.first else { Issue.record("\(m.blocks)"); return }
        #expect(options.map(\.id) == ["a", "7"])
        #expect(try message(#"{"type":"buttons","text":"Q","options":[],"fallback":"F"}"#).blocks == [.unsupported(fallback: "F")])
        #expect(try message(#"{"type":"buttons","options":[{"id":"a","label":"A"}],"fallback":"F"}"#).blocks == [.unsupported(fallback: "F")])
    }

    /// The server may say on the question itself which option was chosen.
    @Test func answeredOnTheBlock() throws {
        let answered = block.replacingOccurrences(of: #""fallback""#, with: #""answer":{"option_id":"o2","label":"Missing a feature"},"fallback""#)
        guard case .buttons(_, _, _, let chosen) = try message(answered).blocks.first else { Issue.record("not buttons"); return }
        #expect(chosen == "o2")
    }

    /// A user message that answered: `answer` on its block or on the message.
    @Test func answerOnTheUserMessage() throws {
        let onBlock = try message(
            #"{"type":"text","text":"Too expensive","answer":{"message_id":"0196f3a2-1111-7000-8000-0000000000b1","option_id":"o1"}}"#,
            author: "user"
        )
        #expect(onBlock.answer == ButtonAnswer(messageId: UUID(uuidString: "0196f3a2-1111-7000-8000-0000000000b1")!, optionId: "o1"))
        #expect(onBlock.blocks == [.text("Too expensive")])
        let onMessage = try message(
            #"{"type":"text","text":"Too expensive"}"#, author: "user",
            extra: #""answer":{"message_id":"0196f3a2-1111-7000-8000-0000000000b1","option_id":"o1"},"#
        )
        #expect(onMessage.answer == onBlock.answer)
        #expect(try message(#"{"type":"text","text":"Hi","answer":{"message_id":"nope"}}"#, author: "user").answer == nil)
    }

    /// `POST …/messages` carries `answer` as the server spells it, and only for a tap.
    @Test func sentBodyCarriesTheAnswer() throws {
        let id = UUID(uuidString: "0196F3A2-1111-7000-8000-0000000000B1")!
        let body = APIClient.MessageBody(text: "Too expensive", category: nil, attachmentIds: [], context: [:],
                                         answer: ButtonAnswer(messageId: id, optionId: "o1"))
        let object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(body)) as? [String: Any])
        let answer = try #require(object["answer"] as? [String: Any])
        #expect(answer["message_id"] as? String == "0196f3a2-1111-7000-8000-0000000000b1")
        #expect(answer["option_id"] as? String == "o1")
        #expect(object["text"] as? String == "Too expensive")
        let typed = try JSONSerialization.jsonObject(with: JSONEncoder().encode(
            APIClient.MessageBody(text: "Hi", category: nil, attachmentIds: [], context: [:])
        )) as? [String: Any]
        #expect(typed?["answer"] == nil)
    }
}

// MARK: - Device key

/// A fake public API per test (its own host), recording what the SDK sent.
final class InstallStub: URLProtocol, @unchecked Sendable {
    struct Seen { let method: String; let path: String; let body: [String: Any] }
    private static let lock = NSLock()
    nonisolated(unsafe) private static var seen: [String: [Seen]] = [:]
    /// Per host: what `PATCH /v1/me` answers.
    nonisolated(unsafe) private static var restored: [String: Bool] = [:]

    static func requests(_ host: String) -> [Seen] { lock.withLock { seen[host] ?? [] } }
    static func setRestored(_ value: Bool, for host: String) { lock.withLock { restored[host] = value } }

    static func client(host: String) -> APIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [InstallStub.self]
        return APIClient(baseURL: URL(string: "https://\(host)")!, session: URLSession(configuration: configuration))
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let host = request.url?.host() ?? ""
        let method = request.httpMethod ?? ""
        let path = request.url?.path() ?? ""
        var data = request.httpBody
        if data == nil, let stream = request.httpBodyStream {
            stream.open()
            var bytes = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let n = stream.read(&buffer, maxLength: buffer.count)
                if n <= 0 { break }
                bytes.append(buffer, count: n)
            }
            stream.close()
            data = bytes
        }
        let body = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        let restored = Self.lock.withLock {
            Self.seen[host, default: []].append(Seen(method: method, path: path, body: body))
            return Self.restored[host] ?? false
        }
        let (status, json): (Int, Any?) = switch (method, path) {
        case ("POST", "/v1/installs"): (201, ["install_id": UUID().uuidString, "token": "it_\(UUID().uuidString)"])
        case ("PATCH", "/v1/me"): (200, ["name": "Old Me", "restored": restored])
        case ("GET", "/v1/me"): (200, ["name": "Old Me"])
        case ("GET", "/v1/conversations"):
            (200, [["id": "0196f3a2-1111-7000-8000-000000000001", "status": "open", "last_text": "From before",
                    "last_author": "admin", "unread": 0, "last_message_at": "2026-09-30T10:00:00Z"]])
        case ("GET", "/v1/messenger/config"): (200, ["app_name": "Test"])
        default: (204, nil)
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: json.map { try! JSONSerialization.data(withJSONObject: $0) } ?? Data())
        client?.urlProtocolDidFinishLoading(self)
    }
}

@Suite @MainActor struct DeviceKeyTests {
    /// A messenger on its own fake server (its own Keychain account too).
    private func messenger() -> (Messenger, host: String, account: String) {
        let host = "\(UUID().uuidString.lowercased()).devreply.test"
        let publicKey = "pk_test_\(UUID().uuidString)"
        let messenger = Messenger()
        messenger.useForTesting(publicKey: publicKey, client: InstallStub.client(host: host))
        return (messenger, host, "\(host)|\(publicKey)")
    }

    private func installKeys(_ host: String) -> [String?] {
        InstallStub.requests(host).filter { $0.method == "POST" && $0.path == "/v1/installs" }.map { $0.body["device_key"] as? String }
    }

    @Test func newKeyIs256RandomBitsInBase64url() throws {
        let key = Keychain.newDeviceKey()
        #expect(key.count == 43)
        #expect(key.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") })
        var base64 = key.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += "="
        #expect(Data(base64Encoded: base64)?.count == 32)
        #expect(Keychain.newDeviceKey() != key)
    }

    @Test func createdOnceAndSentOnRegistration() async throws {
        let (messenger, host, account) = messenger()
        defer { Keychain.deleteDeviceKey(for: account); Keychain.deleteToken(for: account) }
        _ = try await messenger.token()
        let sent = try #require(installKeys(host).first ?? nil, "POST /v1/installs carries device_key")
        #expect(sent == Keychain.deviceKey(for: account))
        #expect(sent.count == 43)
    }

    /// Logout and deleteUser forget the install and the user, never the device key: the next install sends
    /// the same one.
    @Test func survivesLogoutAndDeleteUser() async throws {
        let (messenger, host, account) = messenger()
        defer { Keychain.deleteDeviceKey(for: account); Keychain.deleteToken(for: account) }
        _ = try await messenger.token()
        messenger.logout()
        #expect(Keychain.token(for: account) == nil, "logout forgot the install")
        _ = try await messenger.token()
        _ = await messenger.deleteUser()
        _ = try await messenger.token()
        let keys = installKeys(host)
        #expect(keys.count >= 3, "registered again after logout and after deleteUser")
        let first = try #require(keys.first ?? nil)
        #expect(keys.allSatisfy { $0 == first }, "the same device key every time: \(keys)")
    }

    /// The Keychain itself keeps it apart from the install: deleting the token and the user id leaves it.
    @Test func keychainKeepsItThroughTheInstallsDeletion() {
        let account = "test.devreply|pk_\(UUID().uuidString)"
        defer { Keychain.deleteDeviceKey(for: account) }
        let key = Keychain.deviceKey(for: account)
        Keychain.deleteToken(for: account)
        Keychain.deleteUserID(for: account)
        #expect(Keychain.deviceKey(for: account) == key)
        #expect(Keychain.deviceKey(for: "test.devreply|pk_other_\(UUID().uuidString)") != key, "one key per app")
    }

    /// `PATCH /v1/me` answers `restored: true`: the conversation list is loaded again (the old conversations),
    /// and open screens are told (`restores`).
    @Test func restoredReloadsTheList() async throws {
        let (messenger, host, account) = messenger()
        defer { Keychain.deleteDeviceKey(for: account); Keychain.deleteToken(for: account); Keychain.deleteUserID(for: account) }
        InstallStub.setRestored(true, for: host)
        #expect(messenger.conversations.isEmpty)
        await messenger.login(userID: "user-42")?.value
        let requests = InstallStub.requests(host).map { "\($0.method) \($0.path)" }
        let patch = try #require(requests.firstIndex(of: "PATCH /v1/me"))
        #expect(requests[patch...].contains("GET /v1/conversations"), "the list reloaded after the restore: \(requests)")
        #expect(messenger.conversations.map(\.lastText) == ["From before"])
        #expect(messenger.restores == 1)
    }

    @Test func notRestoredNoReload() async {
        let (messenger, host, account) = messenger()
        defer { Keychain.deleteDeviceKey(for: account); Keychain.deleteToken(for: account); Keychain.deleteUserID(for: account) }
        InstallStub.setRestored(false, for: host)
        await messenger.login(userID: "user-42")?.value
        let requests = InstallStub.requests(host).map { "\($0.method) \($0.path)" }
        #expect(requests.contains("PATCH /v1/me"))
        #expect(!requests.contains("GET /v1/conversations"))
        #expect(messenger.restores == 0)
    }
}

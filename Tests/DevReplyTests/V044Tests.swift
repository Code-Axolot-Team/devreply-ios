import Foundation
import SwiftUI
import Testing
import UIKit
@testable import DevReply

// SDK 0.4.4: present(message:attributes:) context, deleteUser's pending deletions, the remote on/off
// switch, events, dark mode.

// MARK: - Context with POST /v1/conversations

@Suite struct ContextTests {
    private func json(_ body: APIClient.MessageBody) throws -> [String: Any] {
        let data = try JSONEncoder().encode(body)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func newConversationCarriesContext() throws {
        let body = APIClient.MessageBody(
            text: "Hi", category: "bug", attachmentIds: [],
            context: ["source": "paywall", "items": 42, "price": 9.99, "trial": true]
        )
        let object = try json(body)
        let context = try #require(object["context"] as? [String: Any])
        #expect(context["source"] as? String == "paywall")
        #expect(context["items"] as? Int == 42)
        #expect(context["price"] as? Double == 9.99)
        #expect(context["trial"] as? Bool == true)
        #expect(object["category"] as? String == "bug")
    }

    @Test func noContextNoKey() throws {
        let object = try json(APIClient.MessageBody(text: "Hi", category: nil, attachmentIds: [], context: [:]))
        #expect(object["context"] == nil)
        #expect(object["category"] == nil)
        #expect(object["text"] as? String == "Hi")
    }

    @Test func contextIsCutToWhatTheServerAccepts() {
        var raw: [String: DevReplyAttribute] = [
            "ok key_1.x-y": "fine",
            "": "empty name",
            "émoji": "not ascii",
            String(repeating: "k", count: 41): "too long a name",
            "nan": .number(.nan),
            "long": .string(String(repeating: "a", count: 600)),
        ]
        for i in 0..<25 { raw[String(format: "n%02d", i)] = .number(Double(i)) }
        let context = DevReplyAttribute.context(raw)
        // Sorted by name, the first 20 valid ones: "long", n00…n18.
        #expect(context.count == 20)
        #expect(context["n18"] != nil && context["n19"] == nil && context["ok key_1.x-y"] == nil)
        #expect(context[""] == nil && context["émoji"] == nil && context["nan"] == nil)
        #expect(context[String(repeating: "k", count: 41)] == nil)
        if case .string(let s)? = context["long"] { #expect(s.count == 500) } else { Issue.record("long text kept, cut to 500") }
    }

    @Test func validContextIsKeptAsIs() {
        let raw: [String: DevReplyAttribute] = ["source": "paywall", "plan": "pro", "count": 3, "beta": false]
        #expect(DevReplyAttribute.context(raw) == raw)
    }
}

// MARK: - Remote on/off switch

@Suite struct AvailabilityTests {
    private func config(_ json: String) throws -> MessengerConfig {
        try APIClient.decoder.decode(MessengerConfig.self, from: Data(json.utf8))
    }

    @Test func enabledFromConfig() throws {
        #expect(!Messenger.isAvailable(configured: true, config: try config(#"{"app_name":"A","enabled":false}"#)))
        #expect(Messenger.isAvailable(configured: true, config: try config(#"{"app_name":"A","enabled":true}"#)))
        // Older servers don't send it: on.
        #expect(Messenger.isAvailable(configured: true, config: try config(#"{"app_name":"A"}"#)))
        // Before any config arrived (nothing cached): on.
        #expect(Messenger.isAvailable(configured: true, config: .placeholder))
        // Not configured: off.
        #expect(!Messenger.isAvailable(configured: false, config: .placeholder))
    }

    @Test func switchSurvivesTheCache() throws {
        let off = try config(#"{"app_name":"A","enabled":false}"#)
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let cached = try APIClient.decoder.decode(MessengerConfig.self, from: try encoder.encode(off))
        #expect(cached.enabled == false)
        #expect(cached == off)
    }
}

// MARK: - deleteUser that never gives up

/// Answers `DELETE /v1/me` by the token: `it_204`, `it_500`, `it_offline`…, and records who asked.
final class DeletionStub: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var seen: [(method: String, path: String, auth: String)] = []

    static func requests() -> [(method: String, path: String, auth: String)] { lock.withLock { seen } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let auth = request.value(forHTTPHeaderField: "Authorization") ?? ""
        Self.lock.withLock { Self.seen.append((request.httpMethod ?? "", request.url?.path() ?? "", auth)) }
        let answer = auth.replacingOccurrences(of: "Bearer it_", with: "")
        guard let status = Int(answer) else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite struct PendingDeletionTests {
    private let client: APIClient = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DeletionStub.self]
        return APIClient(baseURL: URL(string: "https://stub.devreply.test")!, session: URLSession(configuration: configuration))
    }()

    @Test func doneOnSuccessOrAlreadyGone() async {
        #expect(await Messenger.deleteOnServer(token: "it_204", client: client))
        #expect(await Messenger.deleteOnServer(token: "it_200", client: client))
        #expect(await Messenger.deleteOnServer(token: "it_401", client: client))
        #expect(await Messenger.deleteOnServer(token: "it_404", client: client))
    }

    @Test func queuedWhenUnreachableOrBusy() async {
        #expect(await !Messenger.deleteOnServer(token: "it_offline", client: client))
        #expect(await !Messenger.deleteOnServer(token: "it_500", client: client))
        #expect(await !Messenger.deleteOnServer(token: "it_503", client: client))
        #expect(await !Messenger.deleteOnServer(token: "it_429", client: client))
    }

    @Test func retriesEachWithItsOwnSavedToken() async {
        let tokens = ["it_204", "it_500", "it_404", "it_offline", "it_401", "it_429"]
        let remaining = await Messenger.retryDeletions(tokens, client: client)
        #expect(remaining == ["it_500", "it_offline", "it_429"])
        // Every retry is DELETE /v1/me with the saved token itself (never another install's).
        let sent = DeletionStub.requests().filter { tokens.contains($0.auth.replacingOccurrences(of: "Bearer ", with: "")) }
        for token in tokens {
            #expect(sent.contains { $0.method == "DELETE" && $0.path == "/v1/me" && $0.auth == "Bearer \(token)" })
        }
    }

    @Test func keychainKeepsASmallList() {
        let account = "test.devreply|pk_\(UUID().uuidString)"
        defer { Keychain.setPendingDeletions([], for: account) }
        #expect(Keychain.pendingDeletions(for: account).isEmpty)
        Keychain.setPendingDeletions(["it_a", "it_b"], for: account)
        // The simulator's test runner may have no Keychain access: then there's nothing to check here.
        guard !Keychain.pendingDeletions(for: account).isEmpty else { return }
        #expect(Keychain.pendingDeletions(for: account) == ["it_a", "it_b"])
        Keychain.setPendingDeletions((0..<15).map { "it_\($0)" }, for: account)
        #expect(Keychain.pendingDeletions(for: account) == (5..<15).map { "it_\($0)" })
        // Separate from the install token: a new install's token never mixes with the owed deletions.
        #expect(Keychain.token(for: account) == nil)
        Keychain.setPendingDeletions([], for: account)
        #expect(Keychain.pendingDeletions(for: account).isEmpty)
    }
}

// MARK: - Events

@Suite(.serialized) @MainActor struct EventTests {
    @Test func startedThenSentInOrder() {
        var seen: [DevReplyEvent] = []
        let subscription = DevReply.addEventListener { seen.append($0) }
        defer { subscription.cancel() }
        let id = UUID()
        Messenger.shared.conversationStarted(id, category: .bug)
        Messenger.shared.messageSent(conversationID: id)
        #expect(seen == [
            .conversationStarted(conversationID: id, category: .bug),
            .messageSent(conversationID: id),
            .messageSent(conversationID: id),
        ])
    }

    @Test func openedAndClosedOncePerPresentation() {
        var seen: [DevReplyEvent] = []
        let subscription = DevReply.addEventListener { seen.append($0) }
        defer { subscription.cancel() }
        let messenger = Messenger.shared
        messenger.messengerAppeared()
        messenger.messengerAppeared() // back from the photo viewer: still the same presentation
        messenger.isCovered = true
        messenger.messengerDisappeared() // the photo viewer covers it: not a close
        messenger.isCovered = false
        messenger.messengerDisappeared()
        messenger.messengerDisappeared()
        #expect(seen == [.messengerOpened, .messengerClosed])
    }

    @Test func manyListenersAndCancel() {
        var first: [DevReplyEvent] = []
        var second: [DevReplyEvent] = []
        let a = DevReply.addEventListener { first.append($0) }
        let b = DevReply.addEventListener { second.append($0) }
        Messenger.shared.messageSent(conversationID: UUID())
        a.cancel()
        a.cancel()
        Messenger.shared.messageSent(conversationID: UUID())
        b.cancel()
        Messenger.shared.messageSent(conversationID: UUID())
        #expect(first.count == 1)
        #expect(second.count == 2)
    }

    @Test func presentationExtrasLastUntilAConversationStarts() {
        let messenger = Messenger.shared
        messenger.setPresentation(message: "Prefilled text", attributes: ["source": "paywall", "bad name!": 1])
        #expect(messenger.presentationMessage == "Prefilled text")
        #expect(messenger.presentationContext == ["source": "paywall"])
        messenger.conversationStarted(UUID(), category: nil)
        #expect(messenger.presentationMessage == nil)
        #expect(messenger.presentationContext.isEmpty)

        // Closing the messenger clears them too.
        messenger.setPresentation(message: "Again", attributes: ["a": 1])
        messenger.messengerAppeared()
        messenger.messengerDisappeared()
        #expect(messenger.presentationMessage == nil)
        #expect(messenger.presentationContext.isEmpty)

        // A blank message prefills nothing.
        messenger.setPresentation(message: "   ", attributes: [:])
        #expect(messenger.presentationMessage == nil)
    }

    @Test func askNameFalseSkipsTheNameFormUntilTheMessengerCloses() {
        let messenger = Messenger.shared
        messenger.setPresentation(message: nil, attributes: [:])
        #expect(messenger.needsName)  // no profile name yet

        messenger.setPresentation(message: nil, attributes: [:], askName: false)
        messenger.messengerAppeared()
        #expect(!messenger.needsName)
        // Still skipped after the first message: the composer stays for the follow-ups.
        messenger.conversationStarted(UUID(), category: nil)
        #expect(!messenger.needsName)

        messenger.messengerDisappeared()
        #expect(messenger.needsName)
    }
}

// MARK: - Dark mode

@Suite(.serialized) @MainActor struct ThemeTests {
    private func hex(_ color: Color, _ style: UIUserInterfaceStyle = .light) -> String {
        let resolved = UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
        return [r, g, b].map { String(format: "%02X", Int(($0 * 255).rounded())) }.joined()
    }

    @Test func withoutDarkThemeTheLightLookIsUnchanged() {
        DevReply.darkTheme = nil
        let p = Palette.active
        // Exactly what 0.4.3 drew with.
        #expect(p.header == Brand.lemon && p.card == Brand.lemon && p.brand == Brand.lemon && p.tagText == Brand.lemon)
        #expect(p.accent == Brand.pink)
        #expect(p.ink == Brand.ink && p.outline == Brand.ink && p.shadow == Brand.ink && p.teamBubbleText == Brand.ink)
        #expect(p.onHeader == Brand.ink && p.onAccent == Brand.ink && p.onCard == Brand.ink && p.onBrand == Brand.ink)
        #expect(p.tagFill == Brand.ink && p.onResolved == Brand.ink)
        #expect(p.surface == .white && p.teamBubble == .white && p.notice == .white)
        #expect(p.muted == Brand.muted && p.mutedOnCard == Brand.muted)
        #expect(p.background == Brand.chalk)
        #expect(p.placeholder == Brand.grey)
        #expect(p.success == Brand.online)
        #expect(p.resolved == Color(red: 0.81, green: 0.95, blue: 0.89))
        #expect(p.error == Color(red: 0.7, green: 0.15, blue: 0.12))
        #expect(!Palette.followsAppearance)
        #expect(Palette.lineScale(.dark) == 1 && Palette.lineScale(.light) == 1)
    }

    @Test func customLightThemeFollowsItsSixColours() {
        let p = Palette(light: DevReplyTheme(primary: .blue, accent: .orange, background: .gray, ink: .green))
        #expect(p.header == .blue && p.card == .blue && p.brand == .blue)
        #expect(p.outline == .green && p.shadow == .green && p.onHeader == .green && p.onAccent == .green)
        #expect(p.accent == .orange && p.background == .gray && p.surface == .white)
    }

    @Test func deepBluePreset() {
        let t = DevReplyTheme.dark
        #expect(hex(t.background) == "0E1320" && hex(t.ink) == "EEF1F8" && hex(t.primary) == "2B50E0")
        #expect(hex(t.accent) == "FF5FA2" && hex(t.userBubble) == "3F6BFF" && hex(t.userBubbleText) == "FFFFFF")
    }

    @Test func darkIsDerivedFromTheSixColours() {
        let d = Palette(dark: .dark)
        // surface = card = notice = team bubble = 8 % from the page towards mix(ink, primary, 50 %).
        #expect(hex(d.surface) == "181E30")
        #expect(d.card == d.surface && d.notice == d.surface && d.teamBubble == d.surface && d.placeholder == d.surface)
        // muted = 35 % of the way from the ink to the page.
        #expect(hex(d.muted) == "A0A3AC")
        // Outlines in the ink (at half width), shadows 60 % towards black.
        #expect(hex(d.outline) == "EEF1F8")
        #expect(hex(d.shadow) == "06080D")
        #expect(hex(d.header) == "2B50E0" && hex(d.onHeader) == "FFFFFF")  // white reads better on cobalt
        #expect(hex(d.onAccent) == "111111")                              // dark text on pink
        #expect(hex(d.onCard) == "EEF1F8" && hex(d.teamBubbleText) == "EEF1F8")
        #expect(hex(d.error) == "FF8A7E")
        // The small brand touches stay lemon with dark text.
        #expect(hex(d.brand) == "F6EB37" && hex(d.onBrand) == "111111")
        #expect(hex(d.tagFill) == "F6EB37" && hex(d.tagText) == "111111")
    }

    @Test func textOnButtonsPicksTheBetterContrast() {
        #expect(RGB(.white).readableText == Color(hex: 0x111111))
        #expect(RGB(Color(hex: 0x111111)).readableText == .white)
        #expect(RGB(Brand.lemon).readableText == Color(hex: 0x111111))
        #expect(RGB(Brand.cobalt).readableText == .white)
    }

    @Test func darkThemeFollowsTheAppearance() {
        DevReply.darkTheme = .dark
        defer { DevReply.darkTheme = nil }
        let p = Palette.active
        #expect(Palette.followsAppearance)
        #expect(hex(p.background, .light) == "FFFDF2" && hex(p.background, .dark) == "0E1320")
        #expect(hex(p.header, .light) == "F6EB37" && hex(p.header, .dark) == "2B50E0")
        #expect(hex(p.outline, .light) == "111111" && hex(p.outline, .dark) == "EEF1F8")
        #expect(Palette.lineScale(.dark) == 0.5 && Palette.lineScale(.light) == 1)
    }

    @Test func darkCategoryArtworkExists() {
        for category in DevReplyCategory.allCases {
            #expect(UIImage(named: "devreply-\(category.rawValue)-dark", in: .devReply, with: nil) != nil)
            #expect(UIImage(named: "devreply-\(category.rawValue)", in: .devReply, with: nil) != nil)
        }
    }
}

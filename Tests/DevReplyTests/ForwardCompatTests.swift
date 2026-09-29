import Foundation
import Testing
@testable import DevReply

/// A future server must never break an old SDK in the field: new enum values, new fields and missing
/// optional fields all have to decode.
@Suite struct ForwardCompatTests {
    @Test func conversationWithUnknownCategoryAndStatus() throws {
        let json = """
        [{"id":"01a0e892-b653-7191-9df9-c7e19fc68be7","status":"waiting_on_user","category":"feedback",
          "started_by":"agent","last_text":"Hi","last_author":"bot","unread":1,
          "created_at":"2026-09-28T15:12:04Z","last_message_at":"2026-09-28T15:12:04Z","brand_new_field":{"x":1}}]
        """
        let list = try APIClient.decoder.decode(Lossy<Conversation>.self, from: Data(json.utf8)).items
        #expect(list.count == 1)
        #expect(list[0].category == .other)
    }

    @Test func messageWithUnknownAuthor() throws {
        let json = """
        {"id":"01a0e892-b653-7191-9df9-c7e19fc68be7","author":"bot","is_internal_note":false,
         "created_at":"2026-09-28T15:12:04Z","blocks":[{"type":"text","text":"hello"}]}
        """
        let m = try APIClient.decoder.decode(Message.self, from: Data(json.utf8))
        #expect(!m.isFromUser)
        #expect(m.plainText == "hello")
    }

    @Test func configWithMissingFieldsAndUnknownButtons() throws {
        let json = """
        {"app_name":"Fox Notes","start_buttons":[{"category":"feedback","emoji":"📣","title":"Feedback"},
                                                {"category":"bug","emoji":"🐞","title":"Broken"}]}
        """
        let c = try APIClient.decoder.decode(MessengerConfig.self, from: Data(json.utf8))
        #expect(c.teamName == "Fox Notes")
        #expect(!c.greeting.isEmpty)
        #expect(c.startButtons.count == 2)
    }

    @Test func oneBrokenConversationDoesNotHideTheOthers() throws {
        let json = """
        [{"id":"not-a-uuid"},
         {"id":"01a0e892-b653-7191-9df9-c7e19fc68be7","status":"open","unread":0,"last_message_at":"2026-09-28T15:12:04Z"}]
        """
        let list = try APIClient.decoder.decode(Lossy<Conversation>.self, from: Data(json.utf8)).items
        #expect(list.count == 1)
    }

    // MARK: 0.4: personas, app icon, team

    @Test func messageWithPersona() throws {
        let json = """
        {"id":"01a0e892-b653-7191-9df9-c7e19fc68be7","author":"admin","created_at":"2026-09-28T15:12:04Z",
         "blocks":[{"type":"text","text":"hi"}],
         "persona":{"name":"Anna","title":"Support","avatar_url":"https://api.devreply.com/i/01a0","extra":1}}
        """
        let m = try APIClient.decoder.decode(Message.self, from: Data(json.utf8))
        #expect(m.persona == Persona(name: "Anna", title: "Support", avatarUrl: URL(string: "https://api.devreply.com/i/01a0")))
    }

    @Test func missingOrBrokenPersonaIsJustAbsent() throws {
        for persona in ["", #","persona":null"#, #","persona":{"name":""}"#, #","persona":"Anna""#, #","persona":{"title":"x"}"#] {
            let json = """
            {"id":"01a0e892-b653-7191-9df9-c7e19fc68be7","author":"admin","created_at":"2026-09-28T15:12:04Z",
             "blocks":[{"type":"text","text":"hi"}]\(persona)}
            """
            let m = try APIClient.decoder.decode(Message.self, from: Data(json.utf8))
            #expect(m.persona == nil)
            #expect(m.plainText == "hi")
        }
        let noTitle = """
        {"id":"01a0e892-b653-7191-9df9-c7e19fc68be7","author":"agent","created_at":"2026-09-28T15:12:04Z",
         "blocks":[],"persona":{"name":"AI Assistant","avatar_url":null}}
        """
        let m = try APIClient.decoder.decode(Message.self, from: Data(noTitle.utf8))
        #expect(m.persona == Persona(name: "AI Assistant"))
    }

    @Test func configWithIconAndTeam() throws {
        let json = """
        {"app_name":"Fox Notes","app_icon_url":"https://api.devreply.com/i/01a0",
         "team":[{"name":"Anna","title":"Support","avatar_url":"https://api.devreply.com/i/01a1"},
                 {"broken":true},{"name":"Sergei"},{"name":"Mia"},{"name":"Four"}]}
        """
        let c = try APIClient.decoder.decode(MessengerConfig.self, from: Data(json.utf8))
        #expect(c.appIconUrl == URL(string: "https://api.devreply.com/i/01a0"))
        #expect(c.team.map(\.name) == ["Anna", "Sergei", "Mia"], "bad ones skipped, three at most")
        let old = try APIClient.decoder.decode(MessengerConfig.self, from: Data(#"{"app_name":"Fox Notes","team":"nope"}"#.utf8))
        #expect(old.appIconUrl == nil && old.team.isEmpty)
    }

    @Test func cachedConfigKeepsIconAndTeam() throws {
        let c = MessengerConfig(
            appName: "A", teamName: "A", greeting: "g", intro: "i", replyTime: "r", replyWithin: "w", startButtons: [],
            appIconUrl: URL(string: "https://x.test/i/1"), team: [Persona(name: "Anna", title: "Support")]
        )
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let back = try APIClient.decoder.decode(MessengerConfig.self, from: encoder.encode(c))
        #expect(back == c)
    }

    // MARK: 0.4: deep links, refused keys

    @Test func deepLinks() {
        let id = UUID(uuidString: "01a0e892-b653-7191-9df9-c7e19fc68be7")!
        #expect(DevReply.conversationID(inDeepLink: URL(string: "greekly://devreply?devreply=01a0e892-b653-7191-9df9-c7e19fc68be7")!) == id)
        #expect(DevReply.conversationID(inDeepLink: URL(string: "https://greekly.app/open?x=1&devreply=01A0E892-B653-7191-9DF9-C7E19FC68BE7")!) == id)
        #expect(DevReply.conversationID(inDeepLink: URL(string: "greekly://settings")!) == nil)
        #expect(DevReply.conversationID(inDeepLink: URL(string: "greekly://devreply?devreply=nope")!) == nil)
    }

    @Test func refusedKeyBacksOff() {
        #expect((0..<6).map { Messenger.keyRetryDelay(afterRefusals: $0) } == [60, 300, 1800, 21600, 21600, 21600])
    }

    @Test @MainActor func personaLabelOncePerGroup() throws {
        func msg(_ author: String, _ persona: String?, minute: Int) throws -> Message {
            let p = persona.map { #","persona":{"name":"\#($0)"}"# } ?? ""
            let json = """
            {"id":"\(UUID().uuidString)","author":"\(author)","created_at":"2026-09-28T15:\(String(format: "%02d", minute)):00Z",
             "blocks":[{"type":"text","text":"x"}]\(p)}
            """
            return try APIClient.decoder.decode(Message.self, from: Data(json.utf8))
        }
        let thread = [
            try msg("user", nil, minute: 0),
            try msg("admin", "Anna", minute: 1),   // label: after the user
            try msg("admin", "Anna", minute: 2),   // same group
            try msg("admin", "Sergei", minute: 3), // label: persona changed
            try msg("user", nil, minute: 4),
            try msg("admin", "Sergei", minute: 5), // label: after the user
            try msg("admin", nil, minute: 6),      // no persona: no label
        ]
        let labels = thread.indices.map { ConversationView.startsPersonaGroup(thread, at: $0, afterTimeLabel: false)?.name }
        #expect(labels == [nil, "Anna", nil, "Sergei", nil, "Sergei", nil])
        #expect(ConversationView.startsPersonaGroup(thread, at: 2, afterTimeLabel: true)?.name == "Anna", "a time label starts a group")
    }
}


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
}

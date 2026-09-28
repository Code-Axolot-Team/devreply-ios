import Foundation
import Testing
@testable import DevReply

@Suite struct BlockTests {
    private func message(_ blocks: String) throws -> Message {
        let json = """
        {"id":"01a0e892-b653-7191-9df9-c7e19fc68be7","author":"admin","is_internal_note":false,
         "created_at":"2026-09-28T15:12:04.177473Z","blocks":\(blocks)}
        """
        return try APIClient.decoder.decode(Message.self, from: Data(json.utf8))
    }

    @Test func textBlock() throws {
        let m = try message(#"[{"type":"text","text":"On it!"}]"#)
        #expect(m.blocks == [.text("On it!")])
        #expect(m.author == .admin && !m.isFromUser)
    }

    @Test func unknownTypeFallsBackToText() throws {
        let m = try message(#"[{"type":"carousel","items":[1,2],"fallback":"Open the app to see this."}]"#)
        #expect(m.plainText == "Open the app to see this.")
    }

    @Test func newerMinSDKFallsBack() throws {
        let m = try message(#"[{"type":"text","text":"new","min_sdk":"9.0.0","fallback":"Update the app"}]"#)
        #expect(m.blocks == [.unsupported(fallback: "Update the app")])
        let ok = try message(#"[{"type":"text","text":"old enough","min_sdk":"0.1.0"}]"#)
        #expect(ok.plainText == "old enough")
    }

    @Test func versionCompare() {
        #expect(Block.isVersion("0.1.0", olderThan: "0.2"))
        #expect(Block.isVersion("0.9.9", olderThan: "1.0.0"))
        #expect(!Block.isVersion("1.0.0", olderThan: "1.0"))
        #expect(!Block.isVersion("1.2.0", olderThan: "1.1.9"))
    }
}

@Suite struct DateTests {
    @Test func microsecondsFromTheServer() throws {
        let d = try #require(parseRFC3339("2026-09-28T15:12:04.177473Z"))
        #expect(abs(d.timeIntervalSince1970 - 1_790_608_324.177473) < 0.001)
    }

    @Test func withoutFractionAndWithOffset() {
        #expect(parseRFC3339("2026-09-28T15:12:04Z") != nil)
        #expect(parseRFC3339("2026-09-28T17:12:04.5+02:00") == parseRFC3339("2026-09-28T15:12:04.5Z"))
        #expect(parseRFC3339("nope") == nil)
    }
}

@Suite struct ConfigTests {
    @Test func decodesServerConfig() throws {
        let json = """
        {"app_name":"Fox Notes","team_name":"Fox Notes","greeting":"Hi there 👋","intro":"Ask us anything",
         "reply_time":"Usually replies within a few hours",
         "start_buttons":[{"category":"bug","emoji":"🐞","title":"Something's broken"}]}
        """
        let c = try APIClient.decoder.decode(MessengerConfig.self, from: Data(json.utf8))
        #expect(c.teamName == "Fox Notes")
        #expect(c.startButtons.first?.category == .bug)
        #expect(c.replyWithin == "3 working days", "older servers don't send it: the default")
    }

    @Test func decodesReplyWithin() throws {
        let json = #"{"app_name":"Fox Notes","reply_within":"an hour","reply_time":"Usually replies within an hour"}"#
        let c = try APIClient.decoder.decode(MessengerConfig.self, from: Data(json.utf8))
        #expect(c.replyWithin == "an hour")
        #expect(c.replyTime == "Usually replies within an hour")
    }
}

@Suite struct FileBlockTests {
    @Test func fileBlockDecodes() throws {
        let json = """
        {"id":"01a0e892-b653-7191-9df9-c7e19fc68be7","author":"user","is_internal_note":false,
         "created_at":"2026-09-28T15:12:04Z","blocks":[{"type":"file","attachment_id":"x","name":"log.txt",
         "mime":"text/plain","size":120,"min_sdk":"0.3.0","fallback":"File: log.txt","url":"https://example.com/f"}]}
        """
        let m = try APIClient.decoder.decode(Message.self, from: Data(json.utf8))
        #expect(m.blocks == [.file(url: URL(string: "https://example.com/f")!, name: "log.txt", size: 120, mime: "text/plain")])
    }

    @Test func fileWithoutURLShowsFallback() throws {
        let json = """
        {"id":"01a0e892-b653-7191-9df9-c7e19fc68be7","author":"user","is_internal_note":false,
         "created_at":"2026-09-28T15:12:04Z","blocks":[{"type":"file","name":"log.txt","fallback":"File: log.txt"}]}
        """
        let m = try APIClient.decoder.decode(Message.self, from: Data(json.utf8))
        #expect(m.plainText == "File: log.txt")
    }
}

@Suite struct AttributeTests {
    @Test func literalsEncodeAsJSONValues() throws {
        let attrs: [String: DevReplyAttribute] = ["plan": "pro", "decks": 12, "ratio": 0.5, "trial": false]
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(attrs)) as? [String: Any]
        #expect(json?["plan"] as? String == "pro")
        #expect(json?["decks"] as? Int == 12)
        #expect(json?["ratio"] as? Double == 0.5)
        #expect(json?["trial"] as? Bool == false)
    }
}

@Suite struct PushTests {
    @Test func recognisesDevReplyNotifications() {
        let id = UUID()
        #expect(PushHandling.conversationID(in: ["devreply": ["conversation_id": id.uuidString]]) == id)
        #expect(PushHandling.conversationID(in: ["aps": ["alert": "Sale!"]]) == nil)
        #expect(PushHandling.conversationID(in: ["devreply": ["conversation_id": "nope"]]) == nil)
    }
}

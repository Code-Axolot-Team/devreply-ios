import XCTest
@testable import DevReply

/// The chat's language (spec 05, "Languages"): the same rules and texts as the Android and web SDKs.
final class L10nTests: XCTestCase {
    /// Every case in sdk/conformance/strings/locale-vectors.json.
    func testLocaleVectors() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "conformance/strings/locale-vectors.json")
        struct Vectors: Decodable { struct Case: Decodable { let preferred: [String]; let expect: String }; let cases: [Case] }
        let vectors = try JSONDecoder().decode(Vectors.self, from: Data(contentsOf: url))
        XCTAssertGreaterThan(vectors.cases.count, 10)
        for c in vectors.cases {
            XCTAssertEqual(L10n.resolve(c.preferred).language, c.expect, "\(c.preferred)")
        }
    }

    func testEveryLanguageHasEveryText() {
        let keys = Set(DevReplyStrings.table("en").keys)
        XCTAssertEqual(DevReplyStrings.languages.count, 34)
        XCTAssertEqual(DevReplyStrings.rtl, ["ar", "he"])
        for language in DevReplyStrings.languages {
            XCTAssertEqual(Set(DevReplyStrings.table(language).keys), keys, language)
        }
    }

    @MainActor
    func testSetLocaleSwitchesTextsAndPlaceholders() {
        DevReply.setLocale("es-MX")
        defer { DevReply.setLocale(nil) }
        XCTAssertEqual(DevReply.locale, "es-MX")
        XCTAssertEqual(L10n.shared.language, "es")
        XCTAssertEqual(t("start_title"), "Inicia una conversación")
        XCTAssertEqual(t("notice.email", ["email": "a@b.co"]), "También te escribiremos a a@b.co.")
        XCTAssertEqual(DevReplyCategory.bug.defaultTitle, "Algo no funciona")
        DevReply.setLocale("ja")
        XCTAssertEqual(t("send"), "送信")
        DevReply.setLocale(nil)
        XCTAssertNil(DevReply.locale)
    }

    @MainActor
    func testDefaultsAreTranslatedTheTeamsOwnTextsAreNot() throws {
        DevReply.setLocale("de")
        defer { DevReply.setLocale(nil) }
        let json = """
        {"app_name":"Fox","greeting":"Hi there 👋","intro":"Custom intro from the team","reply_time":"Usually replies within a day",
         "reply_within":"a day","reply_within_key":"day","localize":["greeting","start_buttons","reply_time","reply_within"],
         "start_buttons":[{"category":"bug","emoji":"","title":"Something's broken"}]}
        """
        let config = try APIClient.decoder.decode(MessengerConfig.self, from: Data(json.utf8))
        XCTAssertEqual(config.greetingText, "Hallo 👋")
        XCTAssertEqual(config.introText, "Custom intro from the team", "not in localize: shown as written")
        XCTAssertEqual(config.title(for: config.startButtons[0]), "Etwas funktioniert nicht")
        XCTAssertEqual(config.replyTimeText, "Antwortet meist innerhalb eines Tages")
        XCTAssertEqual(config.replyAllowText, "Die Antwort kann bis zu einem Tag dauern.")
        // A server without the list or the key: DevReply's English defaults and the preset reply times are
        // still translated; the team's own words are shown as written.
        let old = try APIClient.decoder.decode(MessengerConfig.self, from: Data(#"""
        {"greeting":"Yo","intro":"Ask us anything, or tell us what's broken.","reply_time":"Usually replies within an hour","reply_within":"an hour",
         "start_buttons":[{"category":"idea","emoji":"","title":"I have an idea"},{"category":"bug","emoji":"","title":"Bugs here"}]}
        """#.utf8))
        XCTAssertEqual(old.greetingText, "Yo")
        XCTAssertEqual(old.introText, "Frag uns alles oder sag uns, was nicht funktioniert.")
        XCTAssertEqual(old.title(for: old.startButtons[0]), "Ich habe eine Idee")
        XCTAssertEqual(old.title(for: old.startButtons[1]), "Bugs here")
        XCTAssertEqual(old.replyTimeText, "Antwortet meist innerhalb einer Stunde")
        let custom = try APIClient.decoder.decode(MessengerConfig.self, from: Data(#"{"reply_time":"Usually replies whenever","reply_within":"whenever"}"#.utf8))
        XCTAssertEqual(custom.replyTimeText, "Usually replies whenever")
        XCTAssertEqual(custom.replyAllowText, "Please allow up to whenever for a reply.")
    }

    @MainActor
    func testResolvedLineIsTranslatedWithOrWithoutItsKey() throws {
        DevReply.setLocale("fr")
        defer { DevReply.setLocale(nil) }
        for block in [#"{"type":"text","text":"✓ Marked as resolved. Reply here any time to open it again.","key":"resolved"}"#,
                      #"{"type":"text","text":"✓ Marked as resolved. Reply here any time to open it again."}"#] {
            let b = try APIClient.decoder.decode(Block.self, from: Data(block.utf8))
            XCTAssertEqual(b.plainText, "✓ Marquée comme résolue. Répondez ici à tout moment pour la rouvrir.")
        }
        let plain = try APIClient.decoder.decode(Block.self, from: Data(#"{"type":"text","text":"Hello"}"#.utf8))
        XCTAssertEqual(plain, .text("Hello"))
    }
}

import XCTest
@testable import DevReply

/// DevReply Markdown (spec 05, 0.5.0): the parser passes every shared case, and the block decodes as the
/// server sends it.
final class MarkdownTests: XCTestCase {
    /// Every case in sdk/conformance/markdown/cases.json: the same tree and plain text as the reference.
    func testConformanceCases() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "conformance/markdown/cases.json")
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let cases = try XCTUnwrap(root["cases"] as? [[String: Any]])
        XCTAssertGreaterThan(cases.count, 30)
        for c in cases {
            let name = c["name"] as? String ?? "?"
            let markdown = try XCTUnwrap(c["markdown"] as? String)
            let blocks = Markdown.parse(markdown)
            XCTAssertEqual(try Self.canonical(blocks.map(Self.json)), try Self.canonical(c["blocks"] ?? []), name)
            XCTAssertEqual(Markdown.plain(blocks), c["plain"] as? String, name)
        }
    }

    /// A block without `min_sdk` (the example's stub; any server once this SDK is 0.5.0): formatted.
    func testMarkdownBlockDecodes() throws {
        let m = try message(#"{"type":"markdown","text":"Tap **Export**\n\n- one\n- two","fallback":"Tap Export"}"#)
        guard case .markdown(let blocks, let plain) = m.blocks.first else { return XCTFail("\(m.blocks)") }
        XCTAssertEqual(blocks, [
            .paragraph([MarkdownSpan(text: "Tap "), MarkdownSpan(text: "Export", bold: true)]),
            .list(ordered: false, start: 1, items: [[MarkdownSpan(text: "one")], [MarkdownSpan(text: "two")]]),
        ])
        XCTAssertEqual(plain, "Tap Export\n\n• one\n• two")
        XCTAssertEqual(m.plainText, "Tap Export\n\n• one\n• two", "previews and copies never show **")
    }

    /// The real server marks it `min_sdk: "0.5.0"`: this build (0.4.4 until the release) shows the fallback,
    /// and a 0.5.0 build shows it formatted.
    func testMinSdkGatesTheBlock() throws {
        let json = #"{"type":"markdown","text":"Tap **Export**","min_sdk":"0.5.0","fallback":"Tap Export"}"#
        let m = try message(json)
        if Block.isVersion(devReplySDKVersion, olderThan: "0.5.0") {
            XCTAssertEqual(m.blocks, [.unsupported(fallback: "Tap Export")])
        } else {
            guard case .markdown = m.blocks.first else { return XCTFail("\(m.blocks)") }
        }
        XCTAssertEqual(m.plainText, "Tap Export")
        XCTAssertTrue(Block.isVersion("0.4.4", olderThan: "0.5.0"))
        XCTAssertFalse(Block.isVersion("0.5.0", olderThan: "0.5.0"))
    }

    func testMarkdownBlockWithoutTextShowsTheFallback() throws {
        let m = try message(#"{"type":"markdown","fallback":"Plain"}"#)
        XCTAssertEqual(m.blocks, [.unsupported(fallback: "Plain")])
    }

    private func message(_ block: String) throws -> Message {
        let json = """
        {"id":"01a0e892-b653-7191-9df9-c7e19fc68be7","author":"admin","created_at":"2026-09-30T10:00:00Z","blocks":[\(block)]}
        """
        return try APIClient.decoder.decode(Message.self, from: Data(json.utf8))
    }

    // MARK: The reference's JSON shape

    private static func json(_ block: MarkdownBlock) -> [String: Any] {
        switch block {
        case .paragraph(let spans): ["type": "paragraph", "spans": spans.map(json)]
        case .heading(let spans): ["type": "heading", "spans": spans.map(json)]
        case .quote(let spans): ["type": "quote", "spans": spans.map(json)]
        case .code(let text): ["type": "code", "text": text]
        case .list(let ordered, let start, let items):
            ["type": "list", "ordered": ordered, "start": start, "items": items.map { $0.map(json) }]
        }
    }

    /// Only the marks that are on, like the reference.
    private static func json(_ span: MarkdownSpan) -> [String: Any] {
        var out: [String: Any] = ["text": span.text]
        if span.bold { out["bold"] = true }
        if span.italic { out["italic"] = true }
        if span.strike { out["strike"] = true }
        if span.code { out["code"] = true }
        if let link = span.link { out["link"] = link }
        return out
    }

    private static func canonical(_ value: Any) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed]), as: UTF8.self)
    }
}

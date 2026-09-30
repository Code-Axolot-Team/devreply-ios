import Foundation
import Testing
@testable import DevReply

// SDK 0.5.0: live updates over WebSocket (spec 05, "Live updates over WebSocket").

private let conversationID = UUID(uuidString: "01a0e892-b653-7191-9df9-c7e19fc68be7")!

private func messageJSON(_ id: String, author: String = "admin", text: String = "On it", at: String = "2026-09-30T10:00:00Z") -> String {
    #"{"id":"\#(id)","author":"\#(author)","created_at":"\#(at)","blocks":[{"type":"text","text":"\#(text)"}]}"#
}

private func event(_ id: String, author: String = "admin", text: String = "On it", at: String = "2026-09-30T10:00:00Z") -> String {
    #"{"type":"message","id":"\#(id)","conversation_id":"\#(conversationID.uuidString.lowercased())","message":\#(messageJSON(id, author: author, text: text, at: at))}"#
}

private func message(_ id: String, author: String = "admin", text: String = "On it", at: String = "2026-09-30T10:00:00Z") throws -> Message {
    try APIClient.decoder.decode(Message.self, from: Data(messageJSON(id, author: author, text: text, at: at).utf8))
}

// MARK: - Events

@Suite struct LiveEventTests {
    @Test func decodesAMessage() throws {
        let id = "01a0e892-b653-7191-9df9-c7e19fc68be8"
        guard case .message(let conversation, let m) = LiveEvent.decode(event(id)) else {
            Issue.record("not a message")
            return
        }
        #expect(conversation == conversationID)
        #expect(m.id == UUID(uuidString: id))
        #expect(m.author == .admin)
        #expect(m.plainText == "On it")
    }

    @Test func readyAndUnknownTypes() {
        #expect(LiveEvent.decode(#"{"type":"ready"}"#) == .ready)
        #expect(LiveEvent.decode(#"{"type":"typing","conversation_id":"x"}"#) == .unknown)
        #expect(LiveEvent.decode("not json") == .unknown)
        #expect(LiveEvent.decode(#"{"no":"type"}"#) == .unknown)
        // A message that doesn't decode (no id) is ignored, not a crash.
        #expect(LiveEvent.decode(#"{"type":"message","conversation_id":"01a0e892-b653-7191-9df9-c7e19fc68be7","message":{"author":"admin"}}"#) == .unknown)
    }

    @Test func readFrame() throws {
        let frame = LiveEvent.readFrame(conversationID)
        let json = try JSONSerialization.jsonObject(with: Data(frame.utf8)) as? [String: String]
        #expect(json == ["type": "read", "conversation_id": "01a0e892-b653-7191-9df9-c7e19fc68be7"])
    }

    @Test func afterIsAddedToTheTicketURL() {
        let ticket = URL(string: "wss://api.devreply.com/v1/live/ws?ticket=lt_abc")!
        #expect(LiveConnection.url(ticket, after: nil) == ticket)
        let after = UUID(uuidString: "01A0E892-B653-7191-9DF9-C7E19FC68BE8")!
        #expect(LiveConnection.url(ticket, after: after).absoluteString
            == "wss://api.devreply.com/v1/live/ws?ticket=lt_abc&after=01a0e892-b653-7191-9df9-c7e19fc68be8")
    }

    @Test func backoff() {
        #expect((0..<8).map { LiveConnection.delay(attempt: $0, random: 0.5) } == [1, 2, 4, 8, 16, 30, 30, 30])
        // ±20%.
        #expect(abs(LiveConnection.delay(attempt: 0, random: 0) - 0.8) < 1e-9)
        #expect(abs(LiveConnection.delay(attempt: 5, random: 0.999_999) - 36) < 1e-3)
    }
}

// MARK: - The connection (fake socket and clock)

@MainActor final class FakeSocket: LiveSocket {
    let url: URL
    private var inbox: [Result<String?, Error>] = []
    private var waiting: CheckedContinuation<String?, Error>?
    private(set) var sent: [String] = []
    private(set) var closed = false
    var answersPings = true

    init(url: URL) { self.url = url }

    func push(_ text: String) { deliver(.success(text)) }
    func drop() { deliver(.failure(URLError(.networkConnectionLost))) }

    private func deliver(_ result: Result<String?, Error>) {
        if let waiting {
            self.waiting = nil
            waiting.resume(with: result)
        } else {
            inbox.append(result)
        }
    }

    func receive() async throws -> String? {
        if closed { throw URLError(.cancelled) }
        if !inbox.isEmpty { return try inbox.removeFirst().get() }
        return try await withCheckedThrowingContinuation { waiting = $0 }
    }

    func send(_ text: String) async throws { sent.append(text) }

    func ping() async throws {
        if !answersPings { throw URLError(.timedOut) }
    }

    func close() {
        guard !closed else { return }
        closed = true
        deliver(.failure(URLError(.cancelled)))
    }
}

/// Tickets, sockets and time, all under the test's control. Sleeps return at once and move the clock.
@MainActor final class Harness {
    enum Ticket { case ok, unavailable, fails }

    var tickets: [Ticket] = []
    var defaultTicket: Ticket = .ok
    /// What each new socket does on connect: nil = nothing (the test drives it).
    var onConnect: ((FakeSocket) -> Void)?
    private(set) var sockets: [FakeSocket] = []
    private(set) var sleeps: [Double] = []
    private(set) var ticketCalls = 0
    private(set) var now: Double = 0
    private(set) var events: [LiveEvent] = []
    private(set) var states: [LiveConnection.State] = []
    var lastSeen: UUID?

    private(set) var connection: LiveConnection!

    init() {
        connection = makeConnection()
    }

    private func makeConnection() -> LiveConnection {
        let c = LiveConnection(environment: .init(
            ticket: { [weak self] in
                guard let self else { throw CancellationError() }
                self.ticketCalls += 1
                let next = self.tickets.isEmpty ? self.defaultTicket : self.tickets.removeFirst()
                switch next {
                case .ok: return URL(string: "wss://live.test/v1/live/ws?ticket=lt_\(self.ticketCalls)")!
                case .unavailable: throw LiveUnavailable()
                case .fails: throw DevReplyError.network
                }
            },
            connect: { [weak self] url in
                let socket = FakeSocket(url: url)
                self?.sockets.append(socket)
                self?.onConnect?(socket)
                return socket
            },
            sleep: { [weak self] seconds in
                guard let self else { throw CancellationError() }
                // Backoff waits are ≤ 36 s; the watchdog's are 15 s: keep them apart in `sleeps`.
                if seconds != LiveConnection.checkEvery { self.sleeps.append(seconds) }
                self.now += seconds
                await Task.yield()
            },
            now: { [weak self] in self?.now ?? 0 },
            random: { 0.5 }
        ))
        c.lastSeen = { [weak self] in self?.lastSeen }
        c.onEvent = { [weak self] in self?.events.append($0) }
        c.onStateChange = { [weak self] in self?.states.append($0) }
        return c
    }

    /// Lets the connection's tasks run until `condition` holds (or gives up after many turns).
    func settle(until condition: (() -> Bool)? = nil, turns: Int = 2000) async {
        for _ in 0..<turns {
            if condition?() == true { return }
            await Task.yield()
        }
    }
}

@Suite @MainActor struct LiveConnectionTests {
    @Test func readyMakesItLiveAndEventsFlow() async {
        let h = Harness()
        h.onConnect = { $0.push(#"{"type":"ready"}"#) }
        h.connection.start()
        await h.settle { h.connection.isLive }
        #expect(h.connection.state == .live)
        #expect(h.sockets.count == 1)
        #expect(h.sockets[0].url.absoluteString == "wss://live.test/v1/live/ws?ticket=lt_1", "no after without a seen message")

        h.sockets[0].push(event("01a0e892-b653-7191-9df9-c7e19fc68be8"))
        h.sockets[0].push(#"{"type":"typing"}"#)
        await h.settle { h.events.count == 3 }
        #expect(h.events.first == .ready)
        if case .message = h.events[1] {} else { Issue.record("\(h.events)") }
        #expect(h.events[2] == .unknown)

        h.connection.send(LiveEvent.readFrame(conversationID))
        await h.settle { !h.sockets[0].sent.isEmpty }
        #expect(h.sockets[0].sent == [LiveEvent.readFrame(conversationID)])
        h.connection.stop()
    }

    @Test func aNormalCloseDoesNotReconnect() async {
        let h = Harness()
        h.onConnect = { $0.push(#"{"type":"ready"}"#) }
        h.connection.start()
        await h.settle { h.connection.isLive }
        h.connection.stop()
        await h.settle(turns: 200)
        #expect(h.sockets[0].closed)
        #expect(h.connection.state == .off)
        #expect(h.sockets.count == 1)
        #expect(h.ticketCalls == 1)
        #expect(h.sleeps.isEmpty)
    }

    @Test func aDropReconnectsWithANewTicketAndAfter() async {
        let h = Harness()
        h.onConnect = { $0.push(#"{"type":"ready"}"#) }
        h.connection.start()
        await h.settle { h.connection.isLive }
        h.lastSeen = UUID(uuidString: "01a0e892-b653-7191-9df9-c7e19fc68be8")
        h.sockets[0].drop()
        await h.settle { h.sockets.count == 2 && h.connection.isLive }
        #expect(h.sleeps == [1], "1 s after a drop")
        #expect(h.ticketCalls == 2)
        #expect(h.sockets[1].url.absoluteString
            == "wss://live.test/v1/live/ws?ticket=lt_2&after=01a0e892-b653-7191-9df9-c7e19fc68be8")
        #expect(h.states.contains(.waiting))
        h.connection.stop()
    }

    @Test func backsOffAndGivesUpAfterFiveFailuresInARow() async {
        let h = Harness()
        h.onConnect = { $0.push(#"{"type":"ready"}"#) }
        h.connection.start()
        await h.settle { h.connection.isLive }
        // The server goes away: every ticket fails from now on.
        h.defaultTicket = .fails
        h.sockets[0].drop()
        await h.settle { h.connection.state == .gaveUp }
        #expect(h.connection.state == .gaveUp)
        #expect(h.sleeps == [1, 2, 4, 8, 16])
        #expect(h.ticketCalls == 1 + 5)
        // Stays on polling: nothing more happens.
        await h.settle(turns: 300)
        #expect(h.ticketCalls == 6)

        // Opened again: a fresh start.
        h.defaultTicket = .ok
        h.connection.start()
        await h.settle { h.connection.isLive }
        #expect(h.connection.isLive)
        h.connection.stop()
    }

    @Test func failuresBeforeReadyCountAndSocketsThatNeverGetReadyToo() async {
        let h = Harness()
        // Tickets work, but each socket fails before `ready` (e.g. the handshake is refused).
        h.onConnect = { $0.drop() }
        h.connection.start()
        await h.settle { h.connection.state == .gaveUp }
        #expect(h.sleeps == [1, 2, 4, 8])
        #expect(h.sockets.count == 5)
    }

    @Test func aSuccessResetsTheStreak() async {
        let h = Harness()
        h.tickets = [.fails, .fails, .ok]
        h.onConnect = { $0.push(#"{"type":"ready"}"#) }
        h.connection.start()
        await h.settle { h.connection.isLive }
        #expect(h.sleeps == [1, 2])
        h.sockets[0].drop()
        await h.settle { h.sockets.count == 2 && h.connection.isLive }
        #expect(h.sleeps == [1, 2, 1], "back to 1 s after being live")
        h.connection.stop()
    }

    @Test func unavailableMeansPollingWithoutRetries() async {
        let h = Harness()
        h.defaultTicket = .unavailable
        h.connection.start()
        await h.settle { h.connection.state == .unavailable }
        await h.settle(turns: 300)
        #expect(h.connection.state == .unavailable)
        #expect(h.ticketCalls == 1)
        #expect(h.sleeps.isEmpty)
    }

    @Test func seventyFiveSecondsWithoutAFrameIsDead() async {
        let h = Harness()
        h.onConnect = { socket in
            socket.answersPings = false
            socket.push(#"{"type":"ready"}"#)
        }
        h.connection.start()
        await h.settle { h.connection.isLive }
        let first = h.sockets[0]
        // The watchdog's 15 s ticks move the fake clock; no pong, no frame: closed at 75 s, then a reconnect.
        await h.settle { h.sockets.count == 2 }
        #expect(first.closed)
        #expect(h.sockets.count == 2)
        #expect(h.sleeps.first == 1)
        #expect(h.now >= LiveConnection.deadAfter)
        h.connection.stop()
    }

    @Test func pongsKeepItAlive() async {
        let h = Harness()
        h.onConnect = { $0.push(#"{"type":"ready"}"#) }
        h.connection.start()
        await h.settle { h.connection.isLive }
        await h.settle { h.now >= 300 }
        #expect(h.now >= 300, "five minutes of fake time passed")
        #expect(h.sockets.count == 1, "pongs came: never dead")
        #expect(!h.sockets[0].closed)
        h.connection.stop()
    }

    @Test func startWhileRunningIsANoOp() async {
        let h = Harness()
        h.onConnect = { $0.push(#"{"type":"ready"}"#) }
        h.connection.start()
        await h.settle { h.connection.isLive }
        h.connection.start()
        await h.settle(turns: 200)
        #expect(h.sockets.count == 1)
        #expect(h.ticketCalls == 1)
        h.connection.stop()
    }
}

// MARK: - Messages into the chat

@Suite @MainActor struct LiveMessagesTests {
    private func conversation(unread: Int = 0, at: String = "2026-09-30T09:00:00Z") throws -> Conversation {
        let json = #"{"id":"\#(conversationID.uuidString.lowercased())","status":"open","last_text":"Hi","last_author":"user","unread":\#(unread),"last_message_at":"\#(at)"}"#
        return try APIClient.decoder.decode(Conversation.self, from: Data(json.utf8))
    }

    @Test func threadDedupesAndReplacesById() throws {
        let model = ConversationModel(existing: try conversation(), category: nil)
        let a = try message("01a0e892-b653-7191-9df9-c7e19fc68be8", at: "2026-09-30T10:00:00Z")
        let b = try message("01a0e892-b653-7191-9df9-c7e19fc68be9", text: "Fixed", at: "2026-09-30T10:01:00Z")
        model.receive(b)
        model.receive(a)
        #expect(model.messages.map(\.id) == [a.id, b.id], "in time order")
        model.receive(b)
        #expect(model.messages.count == 2, "the same id twice shows once")
        let edited = try message("01a0e892-b653-7191-9df9-c7e19fc68be9", text: "Fixed in 2.4.1", at: "2026-09-30T10:01:00Z")
        model.receive(edited)
        #expect(model.messages.count == 2)
        #expect(model.messages.last?.plainText == "Fixed in 2.4.1", "a copy already shown is replaced")
    }

    @Test func listEntryFollowsLikeAPollWould() throws {
        let c = try conversation(unread: 1)
        let reply = try message("01a0e892-b653-7191-9df9-c7e19fc68be8", text: "On it", at: "2026-09-30T10:00:00Z")
        let off = c.receiving(reply, onScreen: false)
        #expect(off.unread == 2)
        #expect(off.lastText == "On it")
        #expect(off.lastAuthor == "admin")
        #expect(off.lastMessageAt == reply.createdAt)
        #expect(c.receiving(reply, onScreen: true).unread == 1, "on screen: read, not counted")
        let own = try message("01a0e892-b653-7191-9df9-c7e19fc68be8", author: "user", at: "2026-09-30T10:00:00Z")
        #expect(c.receiving(own, onScreen: false).unread == 1, "the user's own message (another device) isn't unread")
        #expect(c.receiving(own, onScreen: false).lastAuthor == "user")
        let old = try message("01a0e892-b653-7191-9df9-c7e19fc68be8", at: "2026-09-30T08:00:00Z")
        #expect(c.receiving(old, onScreen: false) == c, "not newer than the list: already counted")
    }

    @Test func messengerAppliesEventsOnceSendsReadAndAdvancesAfter() async throws {
        let messenger = Messenger()
        let h = Harness()
        h.onConnect = { $0.push(#"{"type":"ready"}"#) }
        messenger.useLiveForTesting(h.connection)
        messenger.upsert(try conversation(unread: 0))
        let model = ConversationModel(existing: try conversation(), category: nil)
        messenger.visibleModel = model
        h.connection.start()
        await h.settle { h.connection.isLive }
        #expect(messenger.isLive)

        let id = "01a0e892-b653-7191-9df9-c7e19fc68be8"
        h.sockets[0].push(event(id, text: "On it", at: "2026-09-30T10:00:00Z"))
        h.sockets[0].push(event(id, text: "On it", at: "2026-09-30T10:00:00Z")) // a backlog repeat
        await h.settle { h.sockets[0].sent.count == 2 }
        #expect(model.messages.map(\.id) == [UUID(uuidString: id)!])
        #expect(h.sockets[0].sent == [LiveEvent.readFrame(conversationID), LiveEvent.readFrame(conversationID)])
        #expect(messenger.conversations.first?.lastText == "On it")
        #expect(messenger.unreadCount == 0, "on screen")
        #expect(messenger.lastSeenMessage == UUID(uuidString: id))

        // Off screen: unread goes up once; no read frame.
        messenger.visibleModel = nil
        let next = "01a0e892-b653-7191-9df9-c7e19fc68bf0"
        h.sockets[0].push(event(next, text: "Fixed", at: "2026-09-30T10:05:00Z"))
        h.sockets[0].push(event(next, text: "Fixed", at: "2026-09-30T10:05:00Z"))
        await h.settle { messenger.lastSeenMessage == UUID(uuidString: next) }
        await h.settle(turns: 100)
        #expect(messenger.unreadCount == 1)
        #expect(h.sockets[0].sent.count == 2)

        // An older id never moves `after` back.
        messenger.saw(UUID(uuidString: id)!)
        #expect(messenger.lastSeenMessage == UUID(uuidString: next))
        h.connection.stop()
        #expect(!messenger.isLive)
    }
}

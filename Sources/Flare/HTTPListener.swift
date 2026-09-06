import Foundation
import Network

/// One parsed request. Only what the spec needs: method, path, Content-Length, body.
struct HTTPRequest {
    let method: String
    let path: String
    let body: Data

    enum ParseResult {
        case incomplete
        case malformed
        case ok(HTTPRequest)
    }

    static let maxHeaderBytes = 32 * 1024
    static let maxBodyBytes = 1024 * 1024

    static func parse(_ buffer: Data) -> ParseResult {
        guard let headerEnd = buffer.firstRange(of: Data("\r\n\r\n".utf8)) else {
            if buffer.count > maxHeaderBytes { return .malformed }
            return .incomplete
        }
        let headerData = buffer[buffer.startIndex..<headerEnd.lowerBound]
        guard let header = String(data: headerData, encoding: .utf8) else { return .malformed }

        var lines = header.components(separatedBy: "\r\n")
        guard !lines.isEmpty else { return .malformed }
        let requestLine = lines.removeFirst().split(separator: " ", omittingEmptySubsequences: true)
        guard requestLine.count >= 2 else { return .malformed }
        let method = String(requestLine[0]).uppercased()

        // Strip query string and any trailing slash, so /status?x=1 and /status/ both work.
        var path = String(requestLine[1].split(separator: "?", maxSplits: 1,
                                               omittingEmptySubsequences: false)[0])
        while path.count > 1 && path.hasSuffix("/") { path.removeLast() }

        var contentLength = 0
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[line.startIndex..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            guard name == "content-length" else { continue }
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            guard let n = Int(value), n >= 0 else { return .malformed }
            contentLength = n
        }
        if contentLength > maxBodyBytes { return .malformed }

        let bodyStart = headerEnd.upperBound
        let available = buffer.distance(from: bodyStart, to: buffer.endIndex)
        if available < contentLength { return .incomplete }
        let bodyEnd = buffer.index(bodyStart, offsetBy: contentLength)
        return .ok(HTTPRequest(method: method, path: path,
                               body: Data(buffer[bodyStart..<bodyEnd])))
    }
}

/// A "waiting" signal boiled down to what Flare stores.
struct Signal {
    let id: String
    let name: String
    let note: String?

    static let unknown = Signal(id: "unknown", name: "unknown", note: nil)

    /// Body is JSON in one of two shapes; detect by which fields are present.
    /// An explicit `agent` wins over a hook payload, so a caller that sets it
    /// always gets the name it asked for.
    static func parse(body: Data) -> Signal {
        guard !body.isEmpty,
              let obj = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        else { return .unknown }

        if let agent = trimmed(obj["agent"]) {
            return Signal(id: agent, name: agent, note: trimmed(obj["note"]).map(condense))
        }

        if let session = trimmed(obj["session_id"]) {
            var name = "claude"
            if let cwd = trimmed(obj["cwd"]) {
                let last = URL(fileURLWithPath: cwd).lastPathComponent
                if !last.isEmpty, last != "/" { name = last }
            }
            let event = trimmed(obj["hook_event_name"])
            var note = trimmed(obj["message"]) ?? trimmed(obj["notification_type"])
            if note == nil, let event {
                // PreToolUse/PostToolUse alone says nothing; name the tool.
                note = trimmed(obj["tool_name"]).map { "\(event): \($0)" } ?? event
            }
            return Signal(id: session, name: name, note: note.map(condense))
        }

        return .unknown
    }

    private static func trimmed(_ value: Any?) -> String? {
        guard let s = value as? String else { return nil }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    /// Collapse whitespace and cap length — notes land in a menu item.
    private static func condense(_ s: String) -> String {
        let flat = s.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return flat.count > 200 ? String(flat.prefix(199)) + "…" : flat
    }
}

/// Loopback-only HTTP/1.1 server. Answers in well under a millisecond so a hook
/// calling it can never stall an agent.
final class HTTPListener {
    static let shared = HTTPListener()
    static let stateChanged = Notification.Name("FlareListenerStateChanged")

    /// Invoked on the main queue after a POST /waiting is recorded.
    var onWaiting: (() -> Void)?

    private let queue = DispatchQueue(label: "com.priyomukul.flare.http", qos: .userInitiated)
    private var listener: NWListener?
    private var sessions: [ObjectIdentifier: Session] = [:]
    private var desiredPort = Prefs.defaultPort
    /// Bumped by every explicit start/stop, so a retry scheduled by an older
    /// attempt can never cancel or resurrect the listener that replaced it.
    private var generation: UInt64 = 0
    private var retryDelay: TimeInterval = 0
    private var retryPending = false
    private static let firstRetryDelay: TimeInterval = 2
    private static let maxRetryDelay: TimeInterval = 30

    private let statusLock = NSLock()
    private var _status = "stopped"
    private var _healthy = false
    /// Human-readable listener state for the menu: "listening on 4242", or an error.
    var status: String { statusLock.withLock { _status } }
    var isHealthy: Bool { statusLock.withLock { _healthy } }

    private static let connectionTimeout: TimeInterval = 5

    private final class Session {
        let connection: NWConnection
        var buffer = Data()
        var timeout: DispatchWorkItem?
        var answered = false
        init(_ connection: NWConnection) { self.connection = connection }
    }

    private init() {}

    // MARK: - Lifecycle

    func start(port: Int) {
        queue.async { [weak self] in self?.startOnQueue(port: port) }
    }

    /// No-op when the port has not changed and the listener is up or already
    /// waiting on a retry.
    func restartIfNeeded(port: Int) {
        queue.async { [weak self] in
            guard let self else { return }
            guard port != self.desiredPort
                    || (self.listener == nil && !self.retryPending) else { return }
            self.startOnQueue(port: port)
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.generation &+= 1
            self.retryPending = false
            self.teardown()
            self.setStatus("stopped", healthy: false)
        }
    }

    private func teardown() {
        listener?.stateUpdateHandler = nil
        listener?.cancel()
        listener = nil
        for session in sessions.values {
            session.timeout?.cancel()
            session.connection.cancel()
        }
        sessions.removeAll()
    }

    /// An explicit (re)start. Invalidates any retry still in flight.
    private func startOnQueue(port: Int) {
        generation &+= 1
        retryPending = false
        retryDelay = 0
        desiredPort = port
        bind(port: port, generation: generation)
    }

    /// Schedule another attempt at the same port. A busy port usually frees up
    /// (a leftover instance quitting, `make run` replacing the bundled app), and
    /// without this a conflict at launch would leave Flare deaf for the session.
    private func scheduleRetry(port: Int, generation gen: UInt64) -> TimeInterval {
        retryDelay = retryDelay == 0 ? Self.firstRetryDelay
                                     : min(retryDelay * 2, Self.maxRetryDelay)
        retryPending = true
        let delay = retryDelay
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, gen == self.generation else { return }
            self.retryPending = false
            self.bind(port: port, generation: gen)
        }
        return delay
    }

    private func bind(port: Int, generation gen: UInt64) {
        teardown()
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else {
            setStatus("invalid port \(port)", healthy: false)
            return
        }

        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.includePeerToPeer = false
        // 127.0.0.1 only — never 0.0.0.0.
        params.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: nwPort)
        if let tcp = params.defaultProtocolStack.internetProtocol as? NWProtocolTCP.Options {
            tcp.noDelay = true
        }

        do {
            let l = try NWListener(using: params)
            l.stateUpdateHandler = { [weak self] state in
                // Runs on `queue`, so reading generation here is safe.
                guard let self, gen == self.generation else { return }
                switch state {
                case .ready:
                    self.retryDelay = 0
                    self.setStatus("listening on 127.0.0.1:\(port)", healthy: true)
                case .waiting(let error):
                    // Network.framework retries this state on its own.
                    self.setStatus("port \(port) unavailable — \(Self.describe(error))",
                                   healthy: false)
                case .failed(let error):
                    let delay = self.scheduleRetry(port: port, generation: gen)
                    self.setStatus("port \(port) — \(Self.describe(error)); retrying in \(Int(delay))s",
                                   healthy: false)
                    self.queue.async { [weak self] in
                        guard let self, gen == self.generation else { return }
                        self.teardown()
                    }
                default:
                    break
                }
            }
            l.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }
            listener = l
            l.start(queue: queue)
        } catch {
            let delay = scheduleRetry(port: port, generation: gen)
            setStatus("could not listen on \(port) — \(error.localizedDescription); retrying in \(Int(delay))s",
                      healthy: false)
        }
    }

    private static func describe(_ error: NWError) -> String {
        if case .posix(let code) = error, code == .EADDRINUSE { return "already in use" }
        return error.localizedDescription
    }

    private func setStatus(_ text: String, healthy: Bool) {
        statusLock.withLock { _status = text; _healthy = healthy }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: HTTPListener.stateChanged, object: nil)
        }
    }

    // MARK: - Connections

    private func accept(_ connection: NWConnection) {
        let session = Session(connection)
        sessions[ObjectIdentifier(connection)] = session

        // A client that connects and says nothing must not leak a connection.
        let timeout = DispatchWorkItem { [weak self] in self?.close(session) }
        session.timeout = timeout
        queue.asyncAfter(deadline: .now() + Self.connectionTimeout, execute: timeout)

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled: self?.close(session)
            default: break
            }
        }
        connection.start(queue: queue)
        receive(session)
    }

    private func receive(_ session: Session) {
        session.connection.receive(minimumIncompleteLength: 1, maximumLength: 32 * 1024) {
            [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty { session.buffer.append(data) }

            switch HTTPRequest.parse(session.buffer) {
            case .ok(let request):
                self.handle(request, on: session)
                return
            case .malformed:
                self.respond(session, status: 400, reason: "Bad Request",
                             contentType: "text/plain; charset=utf-8", body: Data("bad request".utf8))
                return
            case .incomplete:
                break
            }

            if error != nil || isComplete {
                self.close(session)
                return
            }
            self.receive(session)
        }
    }

    private func close(_ session: Session) {
        session.timeout?.cancel()
        session.timeout = nil
        session.connection.stateUpdateHandler = nil
        session.connection.cancel()
        sessions.removeValue(forKey: ObjectIdentifier(session.connection))
    }

    // MARK: - Routing

    private func handle(_ request: HTTPRequest, on session: Session) {
        let store = AgentStore.shared

        switch (request.method, request.path) {
        case ("GET", "/health"):
            respondText(session, "ok")

        case ("GET", "/status"):
            respond(session, status: 200, reason: "OK",
                    contentType: "application/json; charset=utf-8", body: Self.statusJSON())

        case ("POST", "/waiting"):
            let signal = Signal.parse(body: request.body)
            store.upsert(id: signal.id, name: signal.name, note: signal.note)
            respondJSON(session, ["ok": true, "id": signal.id, "waiting": store.count])
            DispatchQueue.main.async { [weak self] in self?.onWaiting?() }

        case ("POST", "/clear"):
            let signal = Signal.parse(body: request.body)
            store.remove(id: signal.id)
            respondJSON(session, ["ok": true, "id": signal.id, "waiting": store.count])

        case ("POST", "/clear-all"):
            store.removeAll()
            respondJSON(session, ["ok": true, "waiting": 0])

        case (_, "/health"), (_, "/status"), (_, "/waiting"), (_, "/clear"), (_, "/clear-all"):
            respond(session, status: 405, reason: "Method Not Allowed",
                    contentType: "text/plain; charset=utf-8", body: Data("method not allowed".utf8))

        default:
            respond(session, status: 404, reason: "Not Found",
                    contentType: "text/plain; charset=utf-8", body: Data("not found".utf8))
        }
    }

    static func statusJSON() -> Data {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let rows: [[String: Any]] = AgentStore.shared.all.map { agent in
            [
                "id": agent.id,
                "name": agent.displayName,
                "note": agent.note ?? NSNull(),
                "since": iso.string(from: agent.since),
                "waitingSeconds": agent.waitingSeconds,
            ]
        }
        guard !rows.isEmpty else { return Data("[]".utf8) }
        return (try? JSONSerialization.data(withJSONObject: rows,
                                            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]))
            ?? Data("[]".utf8)
    }

    // MARK: - Responses

    private func respondText(_ session: Session, _ text: String) {
        respond(session, status: 200, reason: "OK",
                contentType: "text/plain; charset=utf-8", body: Data(text.utf8))
    }

    private func respondJSON(_ session: Session, _ object: [String: Any]) {
        let body = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
            ?? Data("{\"ok\":true}".utf8)
        respond(session, status: 200, reason: "OK",
                contentType: "application/json; charset=utf-8", body: body)
    }

    private func respond(_ session: Session, status: Int, reason: String,
                         contentType: String, body: Data) {
        guard !session.answered else { return }
        session.answered = true
        // Deliberately leave the watchdog armed. If the peer stops reading,
        // .contentProcessed never fires and this is the only thing that closes
        // the session.

        var head = "HTTP/1.1 \(status) \(reason)\r\n"
        head += "Content-Type: \(contentType)\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Connection: close\r\n\r\n"

        var out = Data(head.utf8)
        out.append(body)
        session.connection.send(content: out, completion: .contentProcessed { [weak self] _ in
            self?.close(session)
        })
    }
}

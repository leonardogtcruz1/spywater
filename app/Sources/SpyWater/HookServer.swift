import Foundation
import Network

final class HookResponder {
    private let lock = NSLock()
    private var responded = false
    private var disconnected = false
    private let connection: NWConnection
    private var onClientGone: (() -> Void)?

    init(connection: NWConnection) {
        self.connection = connection
    }

    var hasResponded: Bool {
        lock.lock()
        defer { lock.unlock() }
        return responded
    }

    func setOnClientGone(_ handler: @escaping () -> Void) {
        var shouldFireNow = false
        lock.lock()
        if disconnected && !responded {
            shouldFireNow = true
        } else if !responded {
            self.onClientGone = handler
        }
        lock.unlock()

        if shouldFireNow {
            DispatchQueue.main.async { handler() }
        }
    }

    func respond(statusCode: Int = 200, statusText: String = "OK", body: Data? = nil) {
        lock.lock()
        if responded {
            lock.unlock()
            return
        }
        responded = true
        onClientGone = nil
        lock.unlock()

        let payload = body ?? Data()
        let header = "HTTP/1.1 \(statusCode) \(statusText)\r\nContent-Type: application/json\r\nContent-Length: \(payload.count)\r\nConnection: close\r\n\r\n"
        var full = Data(header.utf8)
        full.append(payload)

        connection.send(content: full, completion: .contentProcessed { _ in
            self.connection.cancel()
        })
    }

    func markClientGone() {
        lock.lock()
        if responded || disconnected {
            lock.unlock()
            return
        }
        disconnected = true
        let handler = onClientGone
        onClientGone = nil
        lock.unlock()

        connection.cancel()
        if let handler {
            DispatchQueue.main.async { handler() }
        }
    }
}

final class HookServer {
    let port: UInt16
    let debugEnabled: Bool
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.leonardocruz.spywater.server")

    var onEvent: (([String: Any], [String: String]) -> Void)?
    var onBlockingHook: (([String: Any], [String: String], HookResponder) -> Void)?
    var onStatusline: (([String: Any]) -> Void)?
    var onError: ((String?) -> Void)?
    var onGetPending: ((@escaping ([[String: Any]]) -> Void) -> Void)?
    var onGetSessions: ((@escaping ([[String: Any]]) -> Void) -> Void)?
    var onDebugDecide: (([String: Any], @escaping (Bool) -> Void) -> Void)?

    init(
        port: UInt16 = UInt16(ProcessInfo.processInfo.environment["SPYWATER_PORT"] ?? "") ?? 47821,
        debugEnabled: Bool = ProcessInfo.processInfo.environment["SPYWATER_DEBUG"] == "1"
    ) {
        self.port = port
        self.debugEnabled = debugEnabled
    }

    func start() {
        stop()
        do {
            let params = NWParameters.tcp
            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                DispatchQueue.main.async {
                    self.onError?("Porta inválida: \(self.port)")
                }
                return
            }
            params.requiredLocalEndpoint = .hostPort(host: NWEndpoint.Host("127.0.0.1"), port: nwPort)
            params.allowLocalEndpointReuse = true

            let listener = try NWListener(using: params)
            self.listener = listener

            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    DispatchQueue.main.async { self.onError?(nil) }
                case .waiting(let err):
                    DispatchQueue.main.async {
                        self.onError?("Porta \(self.port) ocupada — outra instância aberta? (\(err.localizedDescription))")
                    }
                case .failed(let err):
                    DispatchQueue.main.async {
                        self.onError?("Falha no servidor (porta \(self.port)): \(err.localizedDescription)")
                    }
                case .cancelled:
                    break
                default:
                    break
                }
            }

            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }

            listener.start(queue: queue)
        } catch {
            DispatchQueue.main.async {
                self.onError?("Não foi possível iniciar o servidor na porta \(self.port): \(error.localizedDescription)")
            }
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func accept(_ connection: NWConnection) {
        let handler = ConnectionHandler(connection: connection, queue: queue, server: self)
        handler.start()
    }

    fileprivate func route(
        method: String,
        path: String,
        headers: [String: String],
        body: Data,
        connection: NWConnection
    ) {
        let responder = HookResponder(connection: connection)

        if headers["origin"] != nil {
            responder.respond(statusCode: 403, statusText: "Forbidden", body: jsonData(["error": "origin_forbidden"]))
            return
        }

        if method == "GET" && path == "/health" {
            responder.respond(body: jsonData(["ok": true, "app": "SpyWater"]))
            return
        }

        if method == "POST" && path == "/hook" {
            guard let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] else {
                responder.respond(statusCode: 400, statusText: "Bad Request", body: jsonData(["error": "invalid_json"]))
                return
            }
            if headers["x-spy-mode"] == "wait" {
                watchDisconnect(connection: connection, responder: responder)
                DispatchQueue.main.async {
                    self.onBlockingHook?(json, headers, responder)
                }
            } else {
                responder.respond(body: nil)
                DispatchQueue.main.async {
                    self.onEvent?(json, headers)
                }
            }
            return
        }

        if method == "POST" && path == "/statusline" {
            if let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] {
                DispatchQueue.main.async {
                    self.onStatusline?(json)
                }
            }
            responder.respond(body: nil)
            return
        }

        if debugEnabled {
            if method == "GET" && path == "/pending" {
                DispatchQueue.main.async {
                    guard let getPending = self.onGetPending else {
                        responder.respond(body: jsonData([]))
                        return
                    }
                    getPending { items in
                        responder.respond(body: jsonData(items))
                    }
                }
                return
            }

            if method == "GET" && path == "/sessions" {
                DispatchQueue.main.async {
                    guard let getSessions = self.onGetSessions else {
                        responder.respond(body: jsonData([]))
                        return
                    }
                    getSessions { items in
                        responder.respond(body: jsonData(items))
                    }
                }
                return
            }

            if method == "POST" && path == "/debug/decide" {
                guard let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] else {
                    responder.respond(statusCode: 400, statusText: "Bad Request", body: jsonData(["error": "invalid_json"]))
                    return
                }
                DispatchQueue.main.async {
                    guard let decide = self.onDebugDecide else {
                        responder.respond(statusCode: 404, statusText: "Not Found", body: jsonData(["error": "not_found"]))
                        return
                    }
                    decide(json) { ok in
                        if ok {
                            responder.respond(body: jsonData(["ok": true]))
                        } else {
                            responder.respond(statusCode: 404, statusText: "Not Found", body: jsonData(["error": "pending_not_found"]))
                        }
                    }
                }
                return
            }
        }

        responder.respond(statusCode: 404, statusText: "Not Found", body: jsonData(["error": "not_found"]))
    }

    private func watchDisconnect(connection: NWConnection, responder: HookResponder) {
        connection.stateUpdateHandler = { state in
            switch state {
            case .failed, .cancelled:
                responder.markClientGone()
            default:
                break
            }
        }
        func waitEOF() {
            guard !responder.hasResponded else { return }
            connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { _, _, isComplete, error in
                if isComplete || error != nil {
                    responder.markClientGone()
                } else if !responder.hasResponded {
                    waitEOF()
                }
            }
        }
        waitEOF()
    }
}

private final class ConnectionHandler {
    private let connection: NWConnection
    private let queue: DispatchQueue
    private weak var server: HookServer?
    private var buffer = Data()
    private var handled = false

    init(connection: NWConnection, queue: DispatchQueue, server: HookServer) {
        self.connection = connection
        self.queue = queue
        self.server = server
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            if case .failed = state {
                self?.connection.cancel()
            }
        }
        connection.start(queue: queue)
        receiveMore()
    }

    private func receiveMore() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
            if let data, !data.isEmpty {
                self.buffer.append(data)
            }
            if self.tryProcess() {
                return
            }
            if isComplete || error != nil {
                if !self.handled {
                    self.connection.cancel()
                }
                return
            }
            self.receiveMore()
        }
    }

    private func tryProcess() -> Bool {
        guard !handled else { return true }
        let separator = Data("\r\n\r\n".utf8)
        guard let headerRange = buffer.range(of: separator) else {
            return false
        }
        let headerData = buffer.subdata(in: 0..<headerRange.lowerBound)
        guard let headerString = String(data: headerData, encoding: .utf8) else {
            handled = true
            connection.cancel()
            return true
        }

        let lines = headerString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            handled = true
            connection.cancel()
            return true
        }
        let parts = requestLine.split(separator: " ", maxSplits: 2)
        guard parts.count >= 2 else {
            handled = true
            connection.cancel()
            return true
        }
        let method = String(parts[0]).uppercased()
        let rawPath = String(parts[1])
        let path = rawPath.split(separator: "?", maxSplits: 1).first.map(String.init) ?? rawPath

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let val = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[key] = val
        }

        let contentLength = Int(headers["content-length"] ?? "0") ?? 0
        let bodyStart = headerRange.upperBound
        guard buffer.count >= bodyStart + contentLength else {
            return false
        }

        handled = true
        let body = buffer.subdata(in: bodyStart..<(bodyStart + contentLength))
        server?.route(method: method, path: path, headers: headers, body: body, connection: connection)
        return true
    }
}

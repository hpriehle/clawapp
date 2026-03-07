import Vapor
import Fluent
import SharedModels
import Foundation
import NIOWebSocket

/// Connects to the OpenClaw gateway via WebSocket and relays chat messages.
/// Falls back to stub responses if the gateway is not configured.
actor OpenClawHTTPClient {
    private let url: String
    private let token: String
    private let logger: Logger
    private let app: Application

    private var ws: WebSocket?
    private var isConnected = false
    private var connectContinuation: CheckedContinuation<Void, Never>?
    private var pendingResponses: [String: CheckedContinuation<[String: Any]?, Error>] = [:]
    private var chatHandlers: [String: ChatHandler] = [:]

    final class ChatHandler: @unchecked Sendable {
        let onDelta: (String) -> Void
        let onFinal: (String) -> Void
        let onError: (String) -> Void
        private(set) var accumulatedText = ""

        init(onDelta: @escaping (String) -> Void, onFinal: @escaping (String) -> Void, onError: @escaping (String) -> Void) {
            self.onDelta = onDelta
            self.onFinal = onFinal
            self.onError = onError
        }

        func appendDelta(_ text: String) { accumulatedText += text }
        func replaceAccumulated(_ text: String) { accumulatedText = text }
    }

    init(baseURL: String, token: String, logger: Logger, app: Application) {
        self.url = baseURL
        self.token = token
        self.logger = logger
        self.app = app
    }

    // MARK: - Public API

    func sendChat(
        sessionId: UUID,
        content: String,
        db: Database,
        clientManager: ClientWSManager
    ) async {
        guard !url.isEmpty, !token.isEmpty else {
            logger.warning("AI backend not configured — sending stub response")
            await sendStubResponse(sessionId: sessionId, content: content, db: db, clientManager: clientManager)
            return
        }

        if !isConnected {
            await ensureConnected()
            guard isConnected else {
                logger.error("Failed to connect to OpenClaw gateway")
                await broadcastError(clientManager: clientManager, message: "AI gateway not reachable")
                return
            }
        }

        let sessionKey = "talkclaw-\(sessionId.uuidString)"
        let messageId = UUID()

        // Auto-subscribe all connected iOS clients to this session.
        // This ensures responses reach the app even if client-side subscribe failed.
        clientManager.subscribeAll(to: sessionId)

        logger.info("Sending chat: sessionId=\(sessionId), sessionKey=\(sessionKey)")

        do {
            let runId: String? = try await sendRequest(method: "chat.send", params: [
                "sessionKey": sessionKey,
                "message": content,
                "idempotencyKey": UUID().uuidString
            ])

            guard let runId else {
                logger.error("chat.send did not return a runId")
                return
            }

            logger.info("Chat started: runId=\(runId)")

            let fullResponse: String = await withCheckedContinuation { continuation in
                self.chatHandlers[runId] = ChatHandler(
                    onDelta: { text in
                        let delta = WSMessage.ChatDeltaPayload(sessionId: sessionId, delta: text, messageId: messageId)
                        Task { await clientManager.sendToSession(.chatDelta(delta), sessionId: sessionId, logger: self.logger) }
                    },
                    onFinal: { text in
                        self.chatHandlers.removeValue(forKey: runId)
                        continuation.resume(returning: text)
                    },
                    onError: { errMsg in
                        self.chatHandlers.removeValue(forKey: runId)
                        Task { await self.broadcastError(clientManager: clientManager, message: errMsg) }
                        continuation.resume(returning: "")
                    }
                )

                // Timeout: if no response in 10 minutes, clean up the handler
                Task {
                    try? await Task.sleep(for: .seconds(600))
                    if self.chatHandlers.removeValue(forKey: runId) != nil {
                        self.logger.warning("Chat handler timed out: runId=\(runId)")
                        Task { await self.broadcastError(clientManager: clientManager, message: "Chat timed out") }
                        continuation.resume(returning: "")
                    }
                }
            }

            guard !fullResponse.isEmpty else { return }

            let message = try Message(id: messageId, sessionId: sessionId, role: .assistant, content: .text(fullResponse))
            try await message.save(on: db)

            if let session = try await Session.find(sessionId, on: db) {
                session.lastMessageAt = Date()
                try await session.save(on: db)
            }

            let dto = try message.toDTO()
            await clientManager.sendToSession(.chatComplete(dto), sessionId: sessionId, logger: logger)

            // Auto-title: if the session has no title yet, generate one from the user's message
            if let session = try? await Session.find(sessionId, on: db),
               session.title == nil || session.title?.isEmpty == true {
                let firstUserMsg = try? await Message.query(on: db)
                    .filter(\.$session.$id == sessionId)
                    .filter(\.$role == "user")
                    .sort(\.$createdAt, .ascending)
                    .first()
                if let firstMsg = firstUserMsg, let text = firstMsg.textContent {
                    session.title = String(text.prefix(50))
                    try? await session.save(on: db)
                    await clientManager.sendToSession(.sessionUpdated(session.toDTO()), sessionId: sessionId, logger: logger)
                }
            }

            logger.info("AI response complete (\(fullResponse.count) chars)")

        } catch {
            logger.error("Chat error: \(error)")
            await broadcastError(clientManager: clientManager, message: "Chat error: \(error.localizedDescription)")
        }
    }

    // MARK: - WebSocket Connection

    private func ensureConnected() async {
        if isConnected || ws != nil { return }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            connectContinuation = continuation
            startConnection()

            Task {
                try? await Task.sleep(for: .seconds(10))
                if let cont = self.connectContinuation {
                    self.connectContinuation = nil
                    cont.resume()
                }
            }
        }
    }

    private func startConnection() {
        let wsURL = url
            .replacingOccurrences(of: "http://", with: "ws://")
            .replacingOccurrences(of: "https://", with: "wss://")

        logger.info("Connecting to OpenClaw gateway: \(wsURL)")

        Task { [self] in
            do {
                try await WebSocket.connect(
                    to: wsURL,
                    headers: ["Origin": "http://127.0.0.1:18789"],
                    on: app.eventLoopGroup.next()
                ) { ws in
                    ws.onText { [weak self] _, text in
                        guard let self else { return }
                        Task { await self.handleMessage(text) }
                    }
                    ws.onClose.whenComplete { [weak self] _ in
                        guard let self else { return }
                        Task { await self.handleDisconnect() }
                    }
                    Task { [self] in await self.setWebSocket(ws) }
                }
            } catch {
                self.logger.error("Failed to connect to OpenClaw: \(error)")
                await self.handleDisconnect()
            }
        }
    }

    private func setWebSocket(_ ws: WebSocket) {
        self.ws = ws
        logger.info("WebSocket connected to OpenClaw")
    }

    private func handleDisconnect() {
        logger.warning("OpenClaw WebSocket disconnected")
        ws = nil
        isConnected = false
        for (_, continuation) in pendingResponses {
            continuation.resume(throwing: RelayError.disconnected)
        }
        pendingResponses.removeAll()
        for (key, handler) in chatHandlers {
            handler.onError("Gateway disconnected")
            chatHandlers.removeValue(forKey: key)
        }
        // Auto-reconnect after 5s
        Task {
            try? await Task.sleep(for: .seconds(5))
            startConnection()
        }
    }

    // MARK: - Message Handling

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        let type = json["type"] as? String ?? ""

        switch type {
        case "event": handleEvent(json)
        case "res": handleResponse(json)
        default: break
        }
    }

    private func handleEvent(_ json: [String: Any]) {
        let event = json["event"] as? String ?? ""
        let payload = json["payload"] as? [String: Any] ?? [:]

        switch event {
        case "connect.challenge":
            sendConnect(nonce: payload["nonce"] as? String ?? "")
        case "chat":
            handleChatEvent(payload)
        case "agent":
            handleAgentEvent(payload)
        default: break
        }
    }

    private func handleChatEvent(_ payload: [String: Any]) {
        let state = payload["state"] as? String ?? ""
        let runId = payload["runId"] as? String ?? ""
        let message = payload["message"] as? [String: Any]
        let content = message?["content"] as? [[String: Any]]
        let text = content?.first?["text"] as? String ?? ""

        let handler = chatHandlers[runId] ?? chatHandlers.values.first
        guard let handler else { return }

        switch state {
        case "delta":
            // Only update accumulated text — agent events handle incremental deltas
            if !text.isEmpty { handler.replaceAccumulated(text) }
        case "final":
            handler.onFinal(text.isEmpty ? handler.accumulatedText : text)
        case "error":
            handler.onError(text.isEmpty ? "Unknown error" : text)
        case "aborted":
            handler.onError("Chat aborted")
        default: break
        }
    }

    private func handleAgentEvent(_ payload: [String: Any]) {
        let stream = payload["stream"] as? String ?? ""
        let runId = payload["runId"] as? String ?? ""

        if stream == "assistant" {
            let eventData = payload["data"] as? [String: Any]
            let delta = eventData?["delta"] as? String ?? ""

            if !delta.isEmpty {
                let handler = chatHandlers[runId] ?? chatHandlers.values.first
                if let handler {
                    handler.appendDelta(delta)
                    handler.onDelta(delta)
                }
            }
        }
    }

    private func handleResponse(_ json: [String: Any]) {
        guard let id = json["id"] as? String else { return }

        if let continuation = pendingResponses.removeValue(forKey: id) {
            let ok = json["ok"] as? Bool ?? false
            if ok {
                continuation.resume(returning: json["payload"] as? [String: Any])
            } else {
                let error = json["error"] as? [String: Any]
                continuation.resume(throwing: RelayError.requestFailed(error?["message"] as? String ?? "Unknown error"))
            }
            return
        }

        // Auth response (no pending continuation — it's the connect response)
        let ok = json["ok"] as? Bool ?? false
        if ok && !isConnected {
            isConnected = true
            logger.info("OpenClaw gateway authenticated")
            if let cont = connectContinuation {
                connectContinuation = nil
                cont.resume()
            }
        } else if !ok {
            let error = json["error"] as? [String: Any]
            logger.error("OpenClaw connect failed: \(error?["message"] as? String ?? "Unknown")")
            if let cont = connectContinuation {
                connectContinuation = nil
                cont.resume()
            }
        }
    }

    // MARK: - Send

    private func sendConnect(nonce: String) {
        sendJSON([
            "type": "req",
            "id": UUID().uuidString,
            "method": "connect",
            "params": [
                "minProtocol": 3, "maxProtocol": 3,
                "client": ["id": "gateway-client", "version": "0.1.0", "platform": "server", "mode": "webchat"] as [String: Any],
                "role": "operator",
                "scopes": ["operator.admin"],
                "auth": ["token": token],
                "caps": ["chat.stream", "agent.stream"] as [String]
            ] as [String: Any]
        ])
    }

    private func sendRequest<T>(method: String, params: [String: Any]) async throws -> T? {
        guard let ws, !ws.isClosed else { throw RelayError.disconnected }

        let id = UUID().uuidString
        let result: [String: Any]? = try await withCheckedThrowingContinuation { continuation in
            pendingResponses[id] = continuation
            sendJSON(["type": "req", "id": id, "method": method, "params": params])

            Task {
                try? await Task.sleep(for: .seconds(60))
                if let cont = self.pendingResponses.removeValue(forKey: id) {
                    cont.resume(throwing: RelayError.timeout)
                }
            }
        }

        if let payload = result, let runId = payload["runId"] as? String {
            return runId as? T
        }
        return result as? T
    }

    private func sendJSON(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let text = String(data: data, encoding: .utf8) else { return }
        ws?.send(text)
    }

    // MARK: - Helpers

    private func broadcastError(clientManager: ClientWSManager, message: String) async {
        await clientManager.broadcast(.error(.init(code: 500, message: message)))
    }

    private func sendStubResponse(sessionId: UUID, content: String, db: Database, clientManager: ClientWSManager) async {
        let responseText = "Echo: \(content) [AI backend not configured — this is a stub response]"
        do {
            let message = try Message(sessionId: sessionId, role: .assistant, content: .text(responseText))
            try await message.save(on: db)
            if let session = try await Session.find(sessionId, on: db) {
                session.lastMessageAt = Date()
                try await session.save(on: db)
            }
            let dto = try message.toDTO()
            await clientManager.sendToSession(.chatComplete(dto), sessionId: sessionId, logger: logger)
        } catch {
            logger.error("Failed to save stub response: \(error)")
        }
    }

    enum RelayError: Error, LocalizedError {
        case disconnected, timeout, requestFailed(String)
        var errorDescription: String? {
            switch self {
            case .disconnected: return "Gateway disconnected"
            case .timeout: return "Gateway request timed out"
            case .requestFailed(let msg): return msg
            }
        }
    }
}

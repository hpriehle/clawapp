import Vapor
import Fluent
import SharedModels
import Foundation
import AsyncHTTPClient
import NIOCore
import NIOHTTP1

struct OpenClawChannelClient: Sendable {
    let baseURL: String
    let token: String
    let logger: Logger
    let httpClient: HTTPClient

    /// Sends a user message to the OpenClaw gateway and streams the response
    /// back to iOS clients via WebSocket in real time.
    func sendChat(
        sessionId: UUID,
        content: String,
        manager: ClientWSManager,
        db: Database
    ) async {
        guard !baseURL.isEmpty else {
            logger.warning("OPENCLAW_URL not configured — message not sent to AI")
            return
        }

        let messageId = UUID()
        let sessionKey = "talkclaw:dm:\(sessionId.uuidString.lowercased())"

        let bodyJSON: [String: Any] = [
            "model": "openclaw:main",
            "messages": [["role": "user", "content": content]],
            "stream": true
        ]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: bodyJSON) else {
            logger.error("Failed to serialize chat request body")
            return
        }

        do {
            var request = HTTPClientRequest(url: "\(baseURL)/v1/chat/completions")
            request.method = .POST
            request.headers.add(name: "Authorization", value: "Bearer \(token)")
            request.headers.add(name: "Content-Type", value: "application/json")
            request.headers.add(name: "x-openclaw-session-key", value: sessionKey)
            request.body = .bytes(ByteBuffer(data: bodyData))

            let response = try await httpClient.execute(request, timeout: .seconds(120))

            guard response.status == .ok else {
                logger.error("OpenClaw returned HTTP \(response.status.code)")
                await manager.sendToSession(
                    .error(.init(code: Int(response.status.code), message: "AI backend returned HTTP \(response.status.code)")),
                    sessionId: sessionId, logger: logger
                )
                return
            }

            var accumulatedText = ""
            var lineBuffer = ""

            for try await buffer in response.body {
                let chunk = String(buffer: buffer)
                lineBuffer += chunk

                // Process complete lines
                while let newlineRange = lineBuffer.range(of: "\n") {
                    let line = String(lineBuffer[lineBuffer.startIndex..<newlineRange.lowerBound])
                    lineBuffer = String(lineBuffer[newlineRange.upperBound...])

                    guard line.hasPrefix("data: ") else { continue }
                    let payload = String(line.dropFirst(6))

                    if payload == "[DONE]" {
                        break
                    }

                    guard let data = payload.data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let choices = json["choices"] as? [[String: Any]],
                          let delta = choices.first?["delta"] as? [String: Any],
                          let deltaContent = delta["content"] as? String else {
                        continue
                    }

                    accumulatedText += deltaContent

                    let deltaPayload = WSMessage.ChatDeltaPayload(
                        sessionId: sessionId,
                        delta: deltaContent,
                        messageId: messageId
                    )
                    await manager.sendToSession(
                        .chatDelta(deltaPayload),
                        sessionId: sessionId, logger: logger
                    )
                }
            }

            // Process any remaining data in buffer
            if !lineBuffer.isEmpty && lineBuffer.hasPrefix("data: ") {
                let payload = String(lineBuffer.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)
                if payload != "[DONE]",
                   let data = payload.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let choices = json["choices"] as? [[String: Any]],
                   let delta = choices.first?["delta"] as? [String: Any],
                   let deltaContent = delta["content"] as? String {
                    accumulatedText += deltaContent
                }
            }

            guard !accumulatedText.isEmpty else {
                logger.warning("OpenClaw returned empty response for session \(sessionId)")
                return
            }

            let message = try Message(
                id: messageId,
                sessionId: sessionId,
                role: .assistant,
                content: .text(accumulatedText)
            )
            try await message.save(on: db)

            if let session = try await Session.find(sessionId, on: db) {
                session.lastMessageAt = Date()
                try await session.save(on: db)
            }

            let dto = try message.toDTO()
            await manager.sendToSession(
                .chatComplete(dto),
                sessionId: sessionId, logger: logger
            )

            try? await autoTitleIfNeeded(sessionId: sessionId, db: db, manager: manager)

        } catch {
            logger.error("OpenClaw streaming error: \(error)")
            await manager.sendToSession(
                .error(.init(code: 500, message: "AI streaming failed: \(error.localizedDescription)")),
                sessionId: sessionId, logger: logger
            )
        }
    }

    private func autoTitleIfNeeded(
        sessionId: UUID,
        db: Database,
        manager: ClientWSManager
    ) async throws {
        guard let session = try await Session.find(sessionId, on: db),
              session.title == nil || session.title?.isEmpty == true else {
            return
        }
        let firstUserMsg = try await Message.query(on: db)
            .filter(\.$session.$id == sessionId)
            .filter(\.$role == "user")
            .sort(\.$createdAt, .ascending)
            .first()
        if let firstMsg = firstUserMsg, let text = firstMsg.textContent {
            session.title = String(text.prefix(50))
            try await session.save(on: db)
            let lastMsg = try await Message.query(on: db)
                .filter(\.$session.$id == sessionId)
                .sort(\.$createdAt, .descending)
                .first()
            let preview: String? = try lastMsg.map { msg in
                let content = try JSONDecoder().decode(MessageContent.self, from: msg.contentJSON)
                return String(content.previewText.prefix(100))
            }
            await manager.sendToSession(
                .sessionUpdated(session.toDTO(lastMessagePreview: preview)),
                sessionId: sessionId, logger: logger
            )
        }
    }
}

import Vapor
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Client for communicating with the talkclaw-sandbox sidecar over a Unix domain socket.
/// Uses newline-delimited JSON-RPC protocol.
final class SandboxClient: Sendable {
    let socketPath: String

    init(socketPath: String) {
        self.socketPath = socketPath
    }

    /// Execute a widget route handler in the sandbox.
    func execute(
        widgetId: String,
        method: String,
        path: String,
        body: Any? = nil,
        query: [String: String]? = nil,
        headers: [String: String]? = nil
    ) async throws -> (status: Int, json: [String: Any]) {
        var params: [String: Any] = [
            "widgetId": widgetId,
            "method": method,
            "path": path,
        ]
        if let body { params["body"] = body }
        if let query { params["query"] = query }
        if let headers { params["headers"] = headers }

        let result = try await send(method: "execute", params: params)

        guard let dict = result as? [String: Any] else {
            return (200, [:])
        }

        let status = (dict["status"] as? Int) ?? 200
        let json = (dict["json"] as? [String: Any]) ?? [:]
        return (status, json)
    }

    /// Register widget routes with the sandbox.
    func register(widgetId: String, routes: [[String: Any]]) async throws {
        _ = try await send(method: "register", params: [
            "widgetId": widgetId,
            "routes": routes,
        ])
    }

    /// Unregister a widget from the sandbox.
    func unregister(widgetId: String) async throws {
        _ = try await send(method: "unregister", params: [
            "widgetId": widgetId,
        ])
    }

    /// Reload widget routes (unregister + re-register).
    func reload(widgetId: String, routes: [[String: Any]]) async throws {
        _ = try await send(method: "reload", params: [
            "widgetId": widgetId,
            "routes": routes,
        ])
    }

    /// Ping the sandbox.
    func ping() async throws -> Bool {
        let result = try await send(method: "ping", params: [:])
        if let dict = result as? [String: Any], let pong = dict["pong"] as? Bool {
            return pong
        }
        return false
    }

    // MARK: - Private

    private func send(method: String, params: [String: Any]) async throws -> Any {
        let id = UUID().uuidString
        let request: [String: Any] = [
            "id": id,
            "method": method,
            "params": params,
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: request)
        guard var payload = String(data: jsonData, encoding: .utf8) else {
            throw Abort(.internalServerError, reason: "Failed to serialize sandbox request")
        }
        payload += "\n"

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async { [socketPath] in
                do {
                    let result = try Self.syncSend(socketPath: socketPath, payload: payload)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Synchronous Unix socket send/receive on a background thread.
    private static func syncSend(socketPath: String, payload: String) throws -> Any {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw Abort(.serviceUnavailable, reason: "Failed to create Unix socket")
        }
        defer { close(fd) }

        // Set socket timeout (15 seconds)
        var timeout = timeval(tv_sec: 15, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        // Connect to Unix socket
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
            throw Abort(.internalServerError, reason: "Socket path too long")
        }
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { dest in
                for (i, byte) in pathBytes.enumerated() {
                    dest[i] = byte
                }
            }
        }

        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connectResult == 0 else {
            throw Abort(.serviceUnavailable, reason: "Cannot connect to sandbox at \(socketPath): \(String(cString: strerror(errno)))")
        }

        // Send payload
        let payloadData = Array(payload.utf8)
        var totalSent = 0
        while totalSent < payloadData.count {
            let sent = payloadData.withUnsafeBufferPointer { buf in
                Darwin.send(fd, buf.baseAddress!.advanced(by: totalSent), buf.count - totalSent, 0)
            }
            guard sent > 0 else {
                throw Abort(.internalServerError, reason: "Failed to send to sandbox")
            }
            totalSent += sent
        }

        // Read response until newline
        var responseBuffer = Data()
        var readBuf = [UInt8](repeating: 0, count: 4096)

        while true {
            let bytesRead = recv(fd, &readBuf, readBuf.count, 0)
            guard bytesRead > 0 else {
                if bytesRead == 0 {
                    break // Connection closed
                }
                throw Abort(.gatewayTimeout, reason: "Sandbox response timed out")
            }
            responseBuffer.append(contentsOf: readBuf[0..<bytesRead])

            // Check for newline (response delimiter)
            if responseBuffer.contains(UInt8(ascii: "\n")) {
                break
            }
        }

        // Parse response
        guard let response = try JSONSerialization.jsonObject(with: responseBuffer) as? [String: Any] else {
            throw Abort(.internalServerError, reason: "Invalid sandbox response")
        }

        if let error = response["error"] {
            if let errorDict = error as? [String: Any], let message = errorDict["message"] as? String {
                throw Abort(.internalServerError, reason: "Sandbox error: \(message)")
            }
            throw Abort(.internalServerError, reason: "Sandbox error: \(error)")
        }

        return response["result"] as Any
    }
}

// MARK: - Application storage key

struct SandboxClientKey: StorageKey {
    typealias Value = SandboxClient
}

extension Application {
    var sandboxClient: SandboxClient {
        get {
            guard let client = storage[SandboxClientKey.self] else {
                fatalError("SandboxClient not configured. Use app.sandboxClient = SandboxClient(socketPath:)")
            }
            return client
        }
        set { storage[SandboxClientKey.self] = newValue }
    }
}

extension Request {
    var sandboxClient: SandboxClient {
        application.sandboxClient
    }
}

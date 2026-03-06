import Vapor
import SharedModels
import Foundation

struct FileController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let files = routes.grouped("files")
        files.get(use: listRoot)
        files.get("**", use: listOrRead)
        files.on(.POST, "**", body: .collect(maxSize: "50mb"), use: upload)
        files.delete("**", use: deleteFile)
    }

    @Sendable
    func listRoot(req: Request) async throws -> [FileItem] {
        let root = req.application.filesRoot
        return try listDirectory(at: root, relativeTo: root)
    }

    @Sendable
    func listOrRead(req: Request) async throws -> Response {
        let root = req.application.filesRoot
        let pathComponents = req.parameters.getCatchall()
        let relativePath = pathComponents.joined(separator: "/")
        let fullPath = (root as NSString).appendingPathComponent(relativePath)

        // Security: ensure the resolved path is within root
        let resolvedPath = (fullPath as NSString).standardizingPath
        guard resolvedPath.hasPrefix((root as NSString).standardizingPath) else {
            throw Abort(.forbidden, reason: "Path traversal not allowed")
        }

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolvedPath, isDirectory: &isDir) else {
            throw Abort(.notFound)
        }

        if isDir.boolValue {
            let items = try listDirectory(at: resolvedPath, relativeTo: root)
            let data = try JSONEncoder().encode(items)
            return Response(
                status: .ok,
                headers: ["Content-Type": "application/json"],
                body: .init(data: data)
            )
        } else {
            // Return file contents
            return try await req.fileio.asyncStreamFile(at: resolvedPath)
        }
    }

    @Sendable
    func upload(req: Request) async throws -> FileItem {
        let root = req.application.filesRoot
        let pathComponents = req.parameters.getCatchall()
        let relativePath = pathComponents.joined(separator: "/")
        let fullPath = (root as NSString).appendingPathComponent(relativePath)

        let resolvedPath = (fullPath as NSString).standardizingPath
        guard resolvedPath.hasPrefix((root as NSString).standardizingPath) else {
            throw Abort(.forbidden, reason: "Path traversal not allowed")
        }

        // Create parent directories if needed
        let parentDir = (resolvedPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: parentDir, withIntermediateDirectories: true)

        // Write file
        guard let body = req.body.data else {
            throw Abort(.badRequest, reason: "No file data")
        }
        let data = Data(buffer: body)
        try data.write(to: URL(fileURLWithPath: resolvedPath))

        let attrs = try FileManager.default.attributesOfItem(atPath: resolvedPath)
        return FileItem(
            id: relativePath,
            name: (relativePath as NSString).lastPathComponent,
            isDirectory: false,
            size: (attrs[.size] as? Int64),
            modifiedAt: attrs[.modificationDate] as? Date
        )
    }

    @Sendable
    func deleteFile(req: Request) async throws -> HTTPStatus {
        let root = req.application.filesRoot
        let pathComponents = req.parameters.getCatchall()
        let relativePath = pathComponents.joined(separator: "/")
        let fullPath = (root as NSString).appendingPathComponent(relativePath)

        let resolvedPath = (fullPath as NSString).standardizingPath
        guard resolvedPath.hasPrefix((root as NSString).standardizingPath) else {
            throw Abort(.forbidden, reason: "Path traversal not allowed")
        }

        guard FileManager.default.fileExists(atPath: resolvedPath) else {
            throw Abort(.notFound)
        }

        try FileManager.default.removeItem(atPath: resolvedPath)
        return .noContent
    }

    // MARK: - Helpers

    private func listDirectory(at path: String, relativeTo root: String) throws -> [FileItem] {
        let contents = try FileManager.default.contentsOfDirectory(atPath: path)
        return try contents.sorted().compactMap { name -> FileItem? in
            // Skip hidden files
            guard !name.hasPrefix(".") else { return nil }

            let fullPath = (path as NSString).appendingPathComponent(name)
            let attrs = try FileManager.default.attributesOfItem(atPath: fullPath)
            let isDir = (attrs[.type] as? FileAttributeType) == .typeDirectory

            // Relative path from root
            let relativePath = String(fullPath.dropFirst(root.count + 1))

            return FileItem(
                id: relativePath,
                name: name,
                isDirectory: isDir,
                size: isDir ? nil : (attrs[.size] as? Int64),
                modifiedAt: attrs[.modificationDate] as? Date
            )
        }
    }
}
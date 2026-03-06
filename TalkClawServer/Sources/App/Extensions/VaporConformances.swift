import Vapor
import SharedModels

// Vapor Content conformances for SharedModels types
extension FileItem: @retroactive Content {}
extension SessionDTO: @retroactive Content {}
extension MessageDTO: @retroactive Content {}
extension HealthResponse: @retroactive Content {}
extension PaginatedResponse: @retroactive Content {}
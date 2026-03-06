import Vapor
import SharedModels

// Extend SharedModels types to conform to Vapor's Content protocol
// (Content = Codable + RequestDecodable + ResponseEncodable)

extension WidgetDTO: @retroactive Content {}
extension WidgetListItemDTO: @retroactive Content {}
extension DashboardItemDTO: @retroactive Content {}
extension WidgetVersionDTO: @retroactive Content {}
extension WidgetPayload: @retroactive Content {}
extension CreateWidgetRequest: @retroactive Content {}
extension UpdateWidgetSectionsRequest: @retroactive Content {}
extension UpdateRenderVarsRequest: @retroactive Content {}
extension PinWidgetRequest: @retroactive Content {}
extension ReorderDashboardRequest: @retroactive Content {}
extension UpdateDashboardItemRequest: @retroactive Content {}

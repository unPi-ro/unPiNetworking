import Foundation

struct ChatMessage: Codable, Sendable {
    let text: String
    let sender: String
}

struct ServerMessage: Codable, Sendable, Identifiable {
    let text: String
    let sender: String
    let timestamp: String

    var id: String { timestamp }
}

import Foundation

@available(iOS 15.0, macOS 10.15, *)
public enum WebSocketError: Error, Sendable {
    case invalidURL
    case connectionFailed(Error)
    case connectionClosed(closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?)
    case notConnected
    case sendFailed(Error)
    case receiveFailed(Error)
    case encodingError(Error)
    case decodingError(Error)
    case maxReconnectAttemptsExhausted
}

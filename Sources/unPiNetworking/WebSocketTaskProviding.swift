import Foundation

@available(iOS 15.0, macOS 10.15, *)
public protocol URLSessionWebSocketTaskProtocol: Sendable {
    func send(_ message: URLSessionWebSocketTask.Message) async throws
    func receive() async throws -> URLSessionWebSocketTask.Message
    func sendPing(pongReceiveHandler: @escaping @Sendable (Error?) -> Void)
    func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?)
    func resume()
}

@available(iOS 15.0, macOS 10.15, *)
public protocol WebSocketTaskProviding: Sendable {
    func createWebSocketTask(with request: URLRequest) throws -> URLSessionWebSocketTaskProtocol
}

@available(iOS 15.0, macOS 10.15, *)
extension URLSessionWebSocketTask: URLSessionWebSocketTaskProtocol {}

@available(iOS 15.0, macOS 10.15, *)
public final class URLSessionWebSocketTaskProvider: WebSocketTaskProviding, @unchecked Sendable {
    private let session: URLSession

    public init(timeoutInterval: TimeInterval = 30) {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeoutInterval
        self.session = URLSession(configuration: config)
    }

    public func createWebSocketTask(with request: URLRequest) -> URLSessionWebSocketTaskProtocol {
        session.webSocketTask(with: request)
    }
}

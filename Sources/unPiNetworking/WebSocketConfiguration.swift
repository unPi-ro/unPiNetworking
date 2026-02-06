import Foundation

public struct WebSocketConfiguration: Sendable {
    public let defaultHeaders: [String: String]
    public let timeoutInterval: TimeInterval
    public let retryCount: Int
    public let retryBaseDelay: TimeInterval
    public let retryMaxDelay: TimeInterval
    public let pingInterval: TimeInterval?
    public let maximumMessageSize: Int

    public init(
        defaultHeaders: [String: String] = [:],
        timeoutInterval: TimeInterval = 30,
        retryCount: Int = 3,
        retryBaseDelay: TimeInterval = 1.0,
        retryMaxDelay: TimeInterval = 30.0,
        pingInterval: TimeInterval? = 30.0,
        maximumMessageSize: Int = 1_048_576
    ) {
        self.defaultHeaders = defaultHeaders
        self.timeoutInterval = timeoutInterval
        self.retryCount = retryCount
        self.retryBaseDelay = retryBaseDelay
        self.retryMaxDelay = retryMaxDelay
        self.pingInterval = pingInterval
        self.maximumMessageSize = maximumMessageSize
    }
}

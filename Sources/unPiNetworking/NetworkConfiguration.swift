import Foundation

public struct NetworkConfiguration: Sendable {
    public let baseURL: URL
    public let defaultHeaders: [String: String]
    public let timeoutInterval: TimeInterval
    public let retryCount: Int
    public let cachePolicy: URLRequest.CachePolicy
    public let defaultContentType: String?
    
    public init(
        baseURL: URL,
        defaultHeaders: [String: String] = [:],
        timeoutInterval: TimeInterval = 30,
        retryCount: Int = 3,
        cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy,
        defaultContentType: String? = "application/json"
    ) {
        self.baseURL = baseURL
        self.defaultHeaders = defaultHeaders
        self.timeoutInterval = timeoutInterval
        self.retryCount = retryCount
        self.cachePolicy = cachePolicy
        self.defaultContentType = defaultContentType
    }
}

extension NetworkConfiguration {
    func makeURLSessionConfiguration()       -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = timeoutInterval
        configuration.timeoutIntervalForResource = timeoutInterval
        configuration.httpAdditionalHeaders = defaultHeaders
        configuration.requestCachePolicy = cachePolicy
        return configuration
    }
}




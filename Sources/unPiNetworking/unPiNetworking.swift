import Foundation

public protocol NetworkServiceProtocol {
    func request<T: Decodable & Sendable>(_ endpoint: Endpoint) async throws -> T
    func request<T: Decodable & Sendable, E: Encodable & Sendable>(_ endpoint: Endpoint, body: E) async throws -> T
}

@available(iOS 15.0, *)
public actor NetworkService: NetworkServiceProtocol {
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let configuration: NetworkConfiguration

    public init(
        configuration: NetworkConfiguration,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.configuration = configuration
        self.session = URLSession(configuration: configuration.makeURLSessionConfiguration())
        self.encoder = encoder
        self.decoder = decoder
    }

    public func request<T: Decodable & Sendable>(_ endpoint: Endpoint) async throws -> T {
        var endpoint = endpoint

        // Merge configuration headers with endpoint headers
        var headers = configuration.defaultHeaders
        if let endpointHeaders = endpoint.headers {
            headers.merge(endpointHeaders) { _, new in new }
        }
        endpoint.headers = headers
        
        let request = try endpoint.asURLRequest()
        return try await performRequest(request, retryCount: configuration.retryCount)
    }
    
    public func request<T: Decodable & Sendable, E: Encodable & Sendable>(_ endpoint: Endpoint, body: E) async throws -> T {
        var endpoint = endpoint
        let encodedData = try encoder.encode(body)
        endpoint.body = encodedData

        // Merge configuration headers with endpoint headers
        var headers = configuration.defaultHeaders
        if let endpointHeaders = endpoint.headers {
            headers.merge(endpointHeaders) { _, new in new }
        }

        // Only add Content-Type if it's not already set in headers
        if headers["Content-Type"] == nil, let contentType = configuration.defaultContentType {
            headers["Content-Type"] = contentType
        }

        endpoint.headers = headers

        let request = try endpoint.asURLRequest()
        return try await performRequest(request, retryCount: configuration.retryCount)
    }

    private func performRequest<T: Decodable & Sendable>(_ request: URLRequest,retryCount: Int) async throws -> T {
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NetworkError.invalidResponse
            }

            let processedData = try await processResponse(data, response: httpResponse)
            return try decoder.decode(T.self, from: processedData)
        } catch {
            if retryCount > 0 && shouldRetry(error) {
                return try await performRequest(request, retryCount: retryCount - 1)
            }
            throw error
        }
    }

    private func shouldRetry(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .networkConnectionLost, .notConnectedToInternet:
                return true
            default:
                return false
            }
        }
        return false
    }

    private func processResponse(_ data: Data, response: URLResponse) async throws -> Data {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw NetworkError.httpError(statusCode: httpResponse.statusCode, data: data)
        }

        return data
    }
}

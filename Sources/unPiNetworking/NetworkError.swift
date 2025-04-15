import Foundation

public enum NetworkError: Error, Sendable {
    case invalidURL
    case invalidRequest
    case invalidResponse
    case httpError(statusCode: Int, data: Data)
    case decodingError(Error)
    case unknown
    case cancelled
    case timeout
}

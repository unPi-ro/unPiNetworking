import XCTest
@testable import unPiNetworking

final class URLSessionTests: XCTestCase {
    private var session: URLSession!

    override func setUp() {
        super.setUp()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        session = URLSession(configuration: configuration)
    }

    override func tearDown() {
        session = nil
        URLProtocolStub.requestHandler = nil
        super.tearDown()
    }

    func test_successfulRequest_returnsExpectedData() async throws {
        // Given
        let expectedData = "Test response".data(using: .utf8)!
        let expectedResponse = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        URLProtocolStub.requestHandler = { request in
            return (expectedResponse, expectedData)
        }

        // When
        let (data, response) = try await session.data(from: URL(string: "https://example.com")!)

        // Then
        XCTAssertEqual(data, expectedData)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
    }

    func test_failedRequest_throwsError() async {
        // Given
        let expectedError = NSError(domain: "TestError", code: 1)
        URLProtocolStub.requestHandler = { _ in
            throw expectedError
        }

        // When/Then
        do {
            _ = try await session.data(from: URL(string: "https://example.com")!)
            XCTFail("Expected error to be thrown")
        } catch {
            let nsError = error as NSError
            XCTAssertEqual(nsError.domain, expectedError.domain)
            XCTAssertEqual(nsError.code, expectedError.code)
        }
    }

    func test_requestWithCustomHeaders_includesHeaders() async throws {
        // Given
        let expectedHeaders = ["Authorization": "Bearer token"]
        var capturedRequest: URLRequest?

        URLProtocolStub.requestHandler = { request in
            capturedRequest = request
            return (HTTPURLResponse(), Data())
        }

        // When
        var request = URLRequest(url: URL(string: "https://example.com")!)
        request.allHTTPHeaderFields = expectedHeaders
        _ = try await session.data(for: request)

        // Then
        XCTAssertEqual(capturedRequest?.allHTTPHeaderFields, expectedHeaders)
    }
}

final class URLProtocolStub: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        guard let handler = URLProtocolStub.requestHandler else {
            XCTFail("Received unexpected request with no handler set")
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

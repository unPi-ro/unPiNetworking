import XCTest
@testable import unPiNetworking

@available(iOS 15.0, macOS 10.15, *)
final class WebSocketServiceTests: XCTestCase {

    private var mockProvider: MockWebSocketTaskProvider!
    private var service: WebSocketService!
    private let testURL = URL(string: "wss://example.com/ws")!

    override func setUp() {
        super.setUp()
        mockProvider = MockWebSocketTaskProvider()
    }

    override func tearDown() {
        service = nil
        mockProvider = nil
        super.tearDown()
    }

    private func makeService(
        configuration: WebSocketConfiguration = WebSocketConfiguration(pingInterval: nil)
    ) -> WebSocketService {
        WebSocketService(
            configuration: configuration,
            taskProvider: mockProvider
        )
    }

    // MARK: - Connection Tests

    func test_connect_createsAndResumesTask() async throws {
        // Given
        service = makeService()

        // When
        try await service.connect(url: testURL, headers: nil)

        // Then
        let task = mockProvider.latestTask
        XCTAssertNotNil(task)
        XCTAssertTrue(task?.resumeCalled ?? false)
    }

    func test_connect_mergesHeaders() async throws {
        // Given
        let config = WebSocketConfiguration(
            defaultHeaders: ["Authorization": "Bearer token", "Accept": "application/json"],
            pingInterval: nil
        )
        service = makeService(configuration: config)

        // When
        try await service.connect(url: testURL, headers: ["Accept": "text/plain", "Custom": "value"])

        // Then
        let request = mockProvider.capturedRequests.first
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Authorization"), "Bearer token")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Accept"), "text/plain")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Custom"), "value")
    }

    func test_disconnect_cancelsWithCloseCode() async throws {
        // Given
        service = makeService()
        try await service.connect(url: testURL, headers: nil)
        let task = mockProvider.latestTask!

        // When
        await service.disconnect(
            closeCode: .goingAway,
            reason: "bye".data(using: .utf8)
        )

        // Then
        XCTAssertEqual(task.cancelCloseCode, .goingAway)
        XCTAssertEqual(task.cancelReason, "bye".data(using: .utf8))
    }

    func test_connect_transitionsToConnectedState() async throws {
        // Given
        service = makeService()

        // When
        try await service.connect(url: testURL, headers: nil)

        // Then
        let state = await service.currentState
        XCTAssertEqual(String(describing: state), String(describing: WebSocketConnectionState.connected))
    }

    func test_disconnect_transitionsToDisconnectedState() async throws {
        // Given
        service = makeService()
        try await service.connect(url: testURL, headers: nil)

        // When
        await service.disconnect()

        // Then
        let state = await service.currentState
        XCTAssertEqual(
            String(describing: state),
            String(describing: WebSocketConnectionState.disconnected)
        )
    }

    // MARK: - Send Tests

    func test_send_encodesMessageAsJSON() async throws {
        // Given
        struct TestMessage: Codable, Sendable {
            let text: String
        }
        service = makeService()
        try await service.connect(url: testURL, headers: nil)
        let task = mockProvider.latestTask!

        // When
        try await service.send(TestMessage(text: "hello"))

        // Then
        XCTAssertEqual(task.sentMessages.count, 1)
        if case .data(let data) = task.sentMessages.first {
            let decoded = try JSONDecoder().decode(TestMessage.self, from: data)
            XCTAssertEqual(decoded.text, "hello")
        } else {
            XCTFail("Expected data message")
        }
    }

    func test_send_whenNotConnected_throwsNotConnected() async {
        // Given
        service = makeService()

        // When/Then
        do {
            try await service.send(["key": "value"])
            XCTFail("Expected WebSocketError.notConnected")
        } catch {
            guard let wsError = error as? WebSocketError,
                  case .notConnected = wsError else {
                XCTFail("Expected WebSocketError.notConnected, got \(error)")
                return
            }
        }
    }

    func test_send_encodingFailure_throwsEncodingError() async throws {
        // Given
        service = makeService()
        try await service.connect(url: testURL, headers: nil)

        // When/Then
        do {
            try await service.send(Double.nan)
            XCTFail("Expected WebSocketError.encodingError")
        } catch {
            guard let wsError = error as? WebSocketError,
                  case .encodingError = wsError else {
                XCTFail("Expected WebSocketError.encodingError, got \(error)")
                return
            }
        }
    }

    // MARK: - Receive Tests

    func test_receive_decodesJSONMessages() async throws {
        // Given
        struct TestMessage: Codable, Sendable, Equatable {
            let value: Int
        }
        service = makeService()
        try await service.connect(url: testURL, headers: nil)
        let task = mockProvider.latestTask!

        // When
        let stream = await service.receive(TestMessage.self)

        // Yield a short delay so the receive loop can set up
        try await Task.sleep(nanoseconds: 50_000_000)

        let jsonData = try JSONEncoder().encode(TestMessage(value: 42))
        task.simulateReceive(.data(jsonData))

        // Then
        var iterator = stream.makeAsyncIterator()
        let received = try await iterator.next()
        XCTAssertEqual(received, TestMessage(value: 42))
    }

    func test_receive_stringMessage_decodesJSON() async throws {
        // Given
        struct TestMessage: Codable, Sendable, Equatable {
            let name: String
        }
        service = makeService()
        try await service.connect(url: testURL, headers: nil)
        let task = mockProvider.latestTask!

        // When
        let stream = await service.receive(TestMessage.self)

        try await Task.sleep(nanoseconds: 50_000_000)
        task.simulateReceive(.string("{\"name\":\"test\"}"))

        // Then
        var iterator = stream.makeAsyncIterator()
        let received = try await iterator.next()
        XCTAssertEqual(received, TestMessage(name: "test"))
    }

    func test_receive_decodingError_surfacesInStream() async throws {
        // Given
        struct TestMessage: Codable, Sendable {
            let value: Int
        }
        service = makeService()
        try await service.connect(url: testURL, headers: nil)
        let task = mockProvider.latestTask!

        // When
        let stream = await service.receive(TestMessage.self)

        try await Task.sleep(nanoseconds: 50_000_000)
        task.simulateReceive(.string("{\"invalid\": true}"))

        // Then
        var iterator = stream.makeAsyncIterator()
        do {
            _ = try await iterator.next()
            XCTFail("Expected WebSocketError.decodingError")
        } catch {
            guard let wsError = error as? WebSocketError,
                  case .decodingError = wsError else {
                XCTFail("Expected WebSocketError.decodingError, got \(error)")
                return
            }
        }
    }

    func test_receive_multipleConsumers_fanOut() async throws {
        // Given
        struct TestMessage: Codable, Sendable, Equatable {
            let idx: Int
        }
        service = makeService()
        try await service.connect(url: testURL, headers: nil)
        let task = mockProvider.latestTask!

        // When
        let stream1 = await service.receive(TestMessage.self)
        let stream2 = await service.receive(TestMessage.self)

        try await Task.sleep(nanoseconds: 50_000_000)

        let jsonData = try JSONEncoder().encode(TestMessage(idx: 1))
        task.simulateReceive(.data(jsonData))

        // Then
        var iter1 = stream1.makeAsyncIterator()
        var iter2 = stream2.makeAsyncIterator()

        let msg1 = try await iter1.next()
        let msg2 = try await iter2.next()

        XCTAssertEqual(msg1, TestMessage(idx: 1))
        XCTAssertEqual(msg2, TestMessage(idx: 1))
    }

    // MARK: - Reconnection Tests

    func test_reconnect_onReceiveError_attemptsReconnection() async throws {
        // Given
        let config = WebSocketConfiguration(
            retryCount: 2,
            retryBaseDelay: 0.05,
            retryMaxDelay: 0.1,
            pingInterval: nil
        )
        service = makeService(configuration: config)
        try await service.connect(url: testURL, headers: nil)
        let firstTask = mockProvider.latestTask!

        // When — simulate a receive error to trigger reconnection
        firstTask.simulateError(URLError(.networkConnectionLost))

        // Give time for reconnection
        try await Task.sleep(nanoseconds: 500_000_000)

        // Then — a new task should have been created
        XCTAssertGreaterThan(mockProvider.createdTasks.count, 1)
    }

    func test_intentionalDisconnect_preventsReconnection() async throws {
        // Given
        let config = WebSocketConfiguration(
            retryCount: 3,
            retryBaseDelay: 0.05,
            retryMaxDelay: 0.1,
            pingInterval: nil
        )
        service = makeService(configuration: config)
        try await service.connect(url: testURL, headers: nil)

        // When
        await service.disconnect()
        let taskCountAfterDisconnect = mockProvider.createdTasks.count

        try await Task.sleep(nanoseconds: 300_000_000)

        // Then — no new tasks created
        XCTAssertEqual(mockProvider.createdTasks.count, taskCountAfterDisconnect)
    }

    // MARK: - Configuration Tests

    func test_defaultConfiguration_hasExpectedValues() {
        // Given/When
        let config = WebSocketConfiguration()

        // Then
        XCTAssertEqual(config.defaultHeaders, [:])
        XCTAssertEqual(config.timeoutInterval, 30)
        XCTAssertEqual(config.retryCount, 3)
        XCTAssertEqual(config.retryBaseDelay, 1.0)
        XCTAssertEqual(config.retryMaxDelay, 30.0)
        XCTAssertEqual(config.pingInterval, 30.0)
        XCTAssertEqual(config.maximumMessageSize, 1_048_576)
    }

    func test_customConfiguration_storesValues() {
        // Given/When
        let config = WebSocketConfiguration(
            defaultHeaders: ["Auth": "token"],
            timeoutInterval: 60,
            retryCount: 5,
            retryBaseDelay: 2.0,
            retryMaxDelay: 60.0,
            pingInterval: 10.0,
            maximumMessageSize: 2_097_152
        )

        // Then
        XCTAssertEqual(config.defaultHeaders, ["Auth": "token"])
        XCTAssertEqual(config.timeoutInterval, 60)
        XCTAssertEqual(config.retryCount, 5)
        XCTAssertEqual(config.retryBaseDelay, 2.0)
        XCTAssertEqual(config.retryMaxDelay, 60.0)
        XCTAssertEqual(config.pingInterval, 10.0)
        XCTAssertEqual(config.maximumMessageSize, 2_097_152)
    }

    func test_configuration_nilPingInterval_disablesPing() async throws {
        // Given
        let config = WebSocketConfiguration(pingInterval: nil)
        service = makeService(configuration: config)

        // When
        try await service.connect(url: testURL, headers: nil)
        try await Task.sleep(nanoseconds: 200_000_000)

        // Then
        let task = mockProvider.latestTask!
        XCTAssertEqual(task.pingCount, 0)
    }

    func test_connectionState_stream_yieldsStateChanges() async throws {
        // Given
        service = makeService()
        let stateStream = service.connectionState

        // Collect states in background
        let collectedStates = CollectedStates()
        let collectTask = Task {
            for await state in stateStream {
                await collectedStates.append(state)
                if case .disconnected = state,
                   await collectedStates.count > 1 {
                    break
                }
            }
        }

        // When
        try await service.connect(url: testURL, headers: nil)
        await service.disconnect()

        // Wait for states to be collected
        try await Task.sleep(nanoseconds: 100_000_000)
        collectTask.cancel()

        // Then
        let states = await collectedStates.values
        XCTAssertTrue(states.count >= 3)
        XCTAssertEqual(
            String(describing: states[0]),
            String(describing: WebSocketConnectionState.connecting)
        )
        XCTAssertEqual(
            String(describing: states[1]),
            String(describing: WebSocketConnectionState.connected)
        )
        let lastState = try XCTUnwrap(states.last)
        XCTAssertEqual(
            String(describing: lastState),
            String(describing: WebSocketConnectionState.disconnected)
        )
    }
}

// MARK: - Helpers

@available(iOS 15.0, macOS 10.15, *)
private actor CollectedStates {
    var values: [WebSocketConnectionState] = []

    var count: Int {
        values.count
    }

    func append(_ state: WebSocketConnectionState) {
        values.append(state)
    }
}

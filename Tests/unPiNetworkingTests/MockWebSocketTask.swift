import Foundation
@testable import unPiNetworking

@available(iOS 15.0, macOS 10.15, *)
final class MockWebSocketTask: URLSessionWebSocketTaskProtocol, @unchecked Sendable {
    private let lock = NSLock()

    private var _sentMessages: [URLSessionWebSocketTask.Message] = []
    var sentMessages: [URLSessionWebSocketTask.Message] {
        lock.withLock { _sentMessages }
    }

    private var _resumeCalled = false
    var resumeCalled: Bool {
        lock.withLock { _resumeCalled }
    }

    private var _cancelCloseCode: URLSessionWebSocketTask.CloseCode?
    var cancelCloseCode: URLSessionWebSocketTask.CloseCode? {
        lock.withLock { _cancelCloseCode }
    }

    private var _cancelReason: Data?
    var cancelReason: Data? {
        lock.withLock { _cancelReason }
    }

    private var _pingCount = 0
    var pingCount: Int {
        lock.withLock { _pingCount }
    }

    private var receiveContinuation: CheckedContinuation<URLSessionWebSocketTask.Message, Error>?
    private var shouldFailOnReceive = false
    private var receiveError: Error?

    func send(_ message: URLSessionWebSocketTask.Message) async throws {
        lock.withLock { _sentMessages.append(message) }
    }

    func receive() async throws -> URLSessionWebSocketTask.Message {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if shouldFailOnReceive, let error = receiveError {
                shouldFailOnReceive = false
                receiveError = nil
                lock.unlock()
                continuation.resume(throwing: error)
            } else {
                receiveContinuation = continuation
                lock.unlock()
            }
        }
    }

    func sendPing(pongReceiveHandler: @escaping @Sendable (Error?) -> Void) {
        lock.withLock { _pingCount += 1 }
        pongReceiveHandler(nil)
    }

    func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        lock.withLock {
            _cancelCloseCode = closeCode
            _cancelReason = reason
        }
    }

    func resume() {
        lock.withLock { _resumeCalled = true }
    }

    func simulateReceive(_ message: URLSessionWebSocketTask.Message) {
        lock.lock()
        if let continuation = receiveContinuation {
            receiveContinuation = nil
            lock.unlock()
            continuation.resume(returning: message)
        } else {
            lock.unlock()
        }
    }

    func simulateError(_ error: Error) {
        lock.lock()
        if let continuation = receiveContinuation {
            receiveContinuation = nil
            lock.unlock()
            continuation.resume(throwing: error)
        } else {
            shouldFailOnReceive = true
            receiveError = error
            lock.unlock()
        }
    }
}

@available(iOS 15.0, macOS 10.15, *)
final class MockWebSocketTaskProvider: WebSocketTaskProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var _createdTasks: [MockWebSocketTask] = []
    private var _capturedRequests: [URLRequest] = []
    private var _createError: Error?

    var createdTasks: [MockWebSocketTask] {
        lock.withLock { _createdTasks }
    }

    var capturedRequests: [URLRequest] {
        lock.withLock { _capturedRequests }
    }

    var latestTask: MockWebSocketTask? {
        lock.withLock { _createdTasks.last }
    }

    func setCreateError(_ error: Error?) {
        lock.withLock { _createError = error }
    }

    func createWebSocketTask(with request: URLRequest) throws -> URLSessionWebSocketTaskProtocol {
        try lock.withLock {
            if let error = _createError {
                throw error
            }
            let task = MockWebSocketTask()
            _createdTasks.append(task)
            _capturedRequests.append(request)
            return task
        }
    }
}
